#!/bin/bash

# tests/menu_test.sh — `understudy setup omarchy` and `understudy remove omarchy`.
#
#   tests/menu_test.sh
#
# Runs against copies of tests/fixtures/omarchy-menu*.jsonc in a throwaway
# HOME (see tests/lib.sh), never the real menu: the managed block goes in
# and comes out, the hand-added "understudy" line is replaced, every other
# entry and comment is left as it was, a backup is kept, and running it twice
# changes nothing.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MENU="$H/.config/omarchy/extensions/omarchy-menu.jsonc"
REAL="$REPO/tests/fixtures/omarchy-menu.jsonc"     # the shape of Tim's file: a hand-added line, OmaForge and HEY blocks
OTHER="$REPO/tests/fixtures/omarchy-menu-other.jsonc"
BEGIN='  // >>> understudy — managed by `understudy setup omarchy`, do not edit between the markers'
END='  // <<< understudy'

# The menu the way Omarchy's shell reads it (MenuModel.js stripJsonc: whole
# -line // comments and trailing commas go, then JSON.parse); a key given
# twice is an error here, where JSON.parse would keep the last.
parse() {
  python3 -c '
import json, re, sys
t = open(sys.argv[1], encoding="utf-8").read()
t = re.sub(r"^\s*//[^\n]*(\n|$)", "", t, flags=re.M)
t = re.sub(r",(\s*[}\]])", r"\1", t)
def pairs(kv):
    keys = [k for k, _ in kv]
    assert len(keys) == len(set(keys)), "duplicate key"
    return dict(kv)
print(json.dumps(json.loads(t, object_pairs_hook=pairs), ensure_ascii=False, sort_keys=True))' "$1"
}
backups() { find "$(dirname "$MENU")" -name 'omarchy-menu.jsonc.bak.*' | wc -l; }
# The file without our block, for comparing with what it was.
without_block() { sed "/^  \/\/ >>> understudy /,/^  \/\/ <<< understudy\$/d" "$1"; }
export -f parse without_block

# --------------------------------------------------------------- no file

note "no menu file yet"
check "setup creates it" us setup omarchy
check "in the standard shape, with the marked block" \
  test "$(cat "$MENU")" = "$(printf '{\n%s\n%s\n%s\n}' "$BEGIN" "$(sed -n 3p "$MENU")" "$END")"
check "Omarchy can read it" parse "$MENU"
entry=$(parse "$MENU" | jq -c .understudy)
check "the entry has the icon, label and description" \
  test "$(jq -r '"\(.icon)|\(.label)|\(.description)"' <<<"$entry")" = "󰌢|Understudy|Make this Omarchy laptop match the main one"
check "it toggles the overlay" test "$(jq -r .action <<<"$entry")" = "omarchy-shell shell toggle ninepointlabs.understudy"
check "it shows only when the plugin is installed" \
  test "$(jq -r .when <<<"$entry")" = 'test -f "$HOME/.config/omarchy/plugins/ninepointlabs.understudy/manifest.json"'
check "the when check fails without the plugin" bash -c '! HOME="$1" bash -c "$2"' _ "$H" "$(jq -r .when <<<"$entry")"
mkdir -p "$H/.config/omarchy/plugins/ninepointlabs.understudy" && echo '{}' >"$H/.config/omarchy/plugins/ninepointlabs.understudy/manifest.json"
check "and passes with it" bash -c 'HOME="$1" bash -c "$2"' _ "$H" "$(jq -r .when <<<"$entry")"
check "no backup of a file that did not exist" test "$(backups)" = 0
check "a new file is readable by others, like the rest of ~/.config" test "$(stat -c %a "$MENU")" = 644
check "remove takes the block out again" us remove omarchy
check "leaving the empty object" test "$(parse "$MENU")" = "{}"
rm -f "$MENU" "$MENU".bak.*

# ------------------------------------------------------- Tim's menu file

note "a menu like the one on both laptops"
mkdir -p "$(dirname "$MENU")"
cp "$REAL" "$MENU"
chmod 600 "$MENU"
check "the fixture has the hand-added line" grep -q '^  "understudy": {' "$MENU"
before=$(parse "$REAL")
out=$(us setup omarchy); rc=$?
check "setup succeeds" test "$rc" = 0
check "and says where the backup is" bash -c 'grep -q "Backed up the old one to ~/.config/omarchy/extensions/omarchy-menu.jsonc.bak." <<<"$1"' _ "$out"
check "the backup is the file as it was" cmp -s "$REAL" "$(find "$(dirname "$MENU")" -name 'omarchy-menu.jsonc.bak.*')"
check "Omarchy can read the result, with no key twice" parse "$MENU"
check "there is one understudy entry, inside the markers" \
  test "$(grep -c '"understudy":' "$MENU") $(grep -c -- '// >>> understudy' "$MENU") $(grep -c -- '// <<< understudy' "$MENU")" = "1 1 1"
check "the hand-added line is gone" bash -c '! without_block "$1" | grep -q "\"understudy\":"' _ "$MENU"
check "it now has the when check" test "$(parse "$MENU" | jq -r '.understudy.when | startswith("test -f")')" = true
check "every other entry is the same" \
  test "$(parse "$MENU" | jq -c 'del(.understudy)')" = "$(jq -c 'del(.understudy)' <<<"$before")"
check "the OmaForge and HEY blocks are untouched, byte for byte" \
  bash -c 'diff <(sed -n "/>>> omaforge/,/<<< hey-cli/p" "$1") <(sed -n "/>>> omaforge/,/<<< hey-cli/p" "$2")' _ "$REAL" "$MENU"
check "the rest of the file is the same apart from the hand-added line, comments and all" \
  bash -c 'diff <(grep -v "^  \"understudy\": {" "$1") <(without_block "$2")' _ "$REAL" "$MENU"
check "the file mode is kept" test "$(stat -c %a "$MENU")" = 600
cp "$MENU" "$ROOT/after-setup"
out=$(us setup omarchy)
check "a second setup changes nothing" cmp -s "$MENU" "$ROOT/after-setup"
check "says so, and keeps no extra backup" bash -c 'grep -q "already in the Omarchy menu" <<<"$1" && [[ $2 == 1 ]]' _ "$out" "$(backups)"

note "removing it"
check "remove succeeds" us remove omarchy
check "the block is gone" bash -c '! grep -q -e "understudy" "$1"' _ "$MENU"
check "everything else is as it was, comments and all" \
  bash -c 'diff <(grep -v "^  \"understudy\": {" "$1") "$2"' _ "$REAL" "$MENU"
check "a backup was kept" test "$(backups)" = 2
cp "$MENU" "$ROOT/after-remove"
out=$(us remove omarchy)
check "a second remove changes nothing" bash -c 'cmp -s "$1" "$2" && grep -q "not in the Omarchy menu" <<<"$3"' _ "$MENU" "$ROOT/after-remove" "$out"
check "setup again puts it back the same way" bash -c 'us setup omarchy >/dev/null && cmp -s "$1" "$2"' _ "$MENU" "$ROOT/after-setup"
rm -f "$MENU".bak.*

note "other hand-added shapes"
cp "$OTHER" "$MENU"
check "setup succeeds" us setup omarchy
keys=$(parse "$MENU" | jq -r 'keys | join(" ")')
check "a multi-line hand-added entry and v0.1's install.understudy are both replaced" \
  test "$keys" = "install.other personal personal.notes understudy"
check "a key that only mentions understudy in its action or label is left alone" \
  test "$(parse "$MENU" | jq -r '"\(.["install.other"].action)|\(.["personal.notes"].label)"')" = "omarchy-shell shell toggle acme.understudy-helper|Notes {understudy}"
check "the comment at the top is kept" test "$(head -1 "$MENU")" = "$(head -1 "$OTHER")"
check "remove leaves the other entries" bash -c 'us remove omarchy >/dev/null && [[ $(parse "$1" | jq -r "keys | join(\" \")") == "install.other personal personal.notes" ]]' _ "$MENU"
rm -f "$MENU".bak.*

note "a file Understudy cannot read"
printf '{\n  "a": {"icon": "x",\n' >"$MENU"
cp "$MENU" "$ROOT/broken"
out=$(us setup omarchy 2>&1); rc=$?
check "setup refuses" bash -c '[[ $1 != 0 ]] && grep -q "not JSONC Understudy can read" <<<"$2"' _ "$rc" "$out"
check "and changes nothing, not even a backup" bash -c 'cmp -s "$1" "$2" && [[ $3 == 0 ]]' _ "$MENU" "$ROOT/broken" "$(backups)"
out=$(us remove omarchy 2>&1); rc=$?
check "so does remove" bash -c '[[ $1 != 0 ]] && cmp -s "$2" "$3"' _ "$rc" "$MENU" "$ROOT/broken"
printf '[1, 2]\n' >"$MENU"
check "an array is not a menu" bash -c '! "$@" 2>/dev/null' _ us setup omarchy
check "a bad argument is refused" bash -c '! "$@" 2>/dev/null' _ us setup hyprland

note "the real menu"
check "the tests never touched the real menu file" bash -c '[[ $1 != "$2" ]]' _ "$MENU" "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

finish
