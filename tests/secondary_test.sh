#!/bin/bash

# tests/secondary_test.sh — the second laptop's side: import, diff, plan, apply.
#
#   tests/secondary_test.sh            UPDATE_SNAPSHOTS=1 to rewrite the dry-run snapshot
#
# A fake second laptop under a throwaway HOME (see tests/lib.sh) reads
# tests/fixtures/list.toml: what shows as missing, installed, manual or
# unavailable, the exact commands (checked against tests/snapshots/plan.txt),
# the install order and stop-on-failure, putting the theme back, the ignore
# file, the folder-missing fallback, and lists written to cause trouble.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FIX="$REPO/tests/fixtures/list.toml"
SNAP="$REPO/tests/snapshots/plan.txt"

# ------------------------------------------------------------ the machine

printf '%s\n' base git yay hyprland omarchy btop >"$S/installed"
printf '%s\n' core extra multilib >"$S/repos"
cat >"$S/sl" <<'EOF'
core base 3-1 [installed]
extra btop 1.4 [installed]
extra rclone 1.70
extra restic 0.18
extra nvidia-dkms 575
multilib steam 1.0
EOF
echo '[{"id": "omarchy.clock", "enabled": true, "firstParty": true, "kinds": ["bar-widget"]}]' >"$S/plugins.json"
printf 'flathub\n' >"$S/remotes"
printf '%s\n' "omarchy-install-gaming-steam - steam" "omarchy-install-browser brave brave-bin" >"$S/installer-pkgs"
cp "$S/installed" "$ROOT/installed.fresh"
: >"$S/flatpaks"
cat >"$S/url-ids" <<'EOF'
https://github.com/acme/omarchy-weather.git acme.weather
https://github.com/acme/off.git acme.off
git@github.com:acme/tallbar.git acme.tallbar
EOF
CUR="$H/.local/state/omarchy/current"
mkdir -p "$CUR" "$H/.config/omarchy/themes/already"
touch "$OP/themes/tokyo-night/bg.jpg"
echo tokyo-night >"$CUR/theme.name"
ln -s "$OP/themes/tokyo-night/bg.jpg" "$CUR/background"

# ------------------------------------------------------- folder missing

note "the shared folder"
us role secondary >/dev/null
out=$(us diff 2>&1); rc=$?
check "no folder and nothing imported: exit 3" test "$rc" = 3
check "says the folder does not exist and offers import" bash -c 'grep -q "does not exist" <<<"$1" && grep -q "understudy import PATH" <<<"$1"' _ "$out"
out=$(us import 2>&1); rc=$?
check "import with no folder says so too" bash -c '[[ $1 == 3 ]] && grep -q "does not exist" <<<"$2"' _ "$rc" "$out"
mkdir -p "$ROOT/usb" && cp "$FIX" "$ROOT/usb/understudy.toml"
check "import from any path" us import "$ROOT/usb"
check "keeps a copy" test -s "$H/.local/state/understudy/imported.toml"
check "diff then reads the copy" test "$(us diff --json | jq -r .list.label)" = tuf
mkdir -p "$H/Sync/understudy"
sed 's/^generated_at = .*/generated_at = "2026-10-30T13:00:00Z"/; s/^label = .*/label = "newer"/' "$FIX" >"$H/Sync/understudy/understudy.toml"
check "a newer list in the shared folder wins" test "$(us diff --json | jq -r .list.label)" = newer
cp "$FIX" "$H/Sync/understudy/understudy.toml"

# ------------------------------------------------------------------ diff

note "what is missing here"
d=$(us diff --json)
st() { jq -r --arg k "$1" '.items[] | select(.key == $k) | "\(.status) \(.default)"' <<<"$d"; }
nt() { jq -r --arg k "$1" '.items[] | select(.key == $k) | .note' <<<"$d"; }
check "btop is already here" test "$(st package:btop)" = "installed false"
check "rclone is missing and ticked" test "$(st package:rclone)" = "missing true"
check "an installer that exists here is offered" test "$(st installer:omarchy-install-gaming-steam)" = "missing true"
check "a browser installer branch is offered" test "$(st installer:omarchy-install-browser=brave)" = "missing true"
check "an installer this Omarchy lacks is unavailable" test "$(st installer:omarchy-install-gaming-mystery)" = "unavailable false"
check "a package from a repo this machine lacks is skipped, naming the repo" \
  bash -c '[[ $(jq -r ".items[] | select(.key == \"package:asusctl\") | .status" <<<"$1") == unavailable ]] && jq -r ".items[] | select(.key == \"package:asusctl\") | .note" <<<"$1" | grep -q "needs the \[g14\] repo"' _ "$d"
check "a hardware package is shown, unticked, labelled" bash -c '[[ $1 == "missing false" ]] && grep -q hardware-specific <<<"$2"' _ "$(st package:nvidia-dkms)" "$(nt package:nvidia-dkms)"
check "a package no repo has is unavailable" test "$(st package:gone-pkg)" = "unavailable false"
check "AUR package offered" test "$(st aur:my-aur-tool)" = "missing true"
check "flatpak from a known remote offered" test "$(st flatpak:com.example.Tool)" = "missing true"
check "flatpak from an unknown remote is unavailable" test "$(st flatpak:org.other.App)" = "unavailable false"
check "a theme already here is installed (never replaced)" test "$(st theme:already)" = "installed false"
check "a local-only theme is manual: no source URL" bash -c '[[ $1 == "manual false" ]] && [[ $2 == "manual: no source URL" ]]' _ "$(st theme:handmade)" "$(nt theme:handmade)"
check "a private repo says it needs gh auth here" bash -c 'grep -q "gh auth login" <<<"$1"' _ "$(nt theme:secret)"
check "a local-only plugin is manual" test "$(st plugin:acme.local)" = "manual false"
check "a whole-bar plugin says it will not be switched to" bash -c 'grep -q "not switched to" <<<"$1"' _ "$(nt plugin:acme.tallbar)"
check "AppImages are manual" test "$(st appimage:Tool-1.0.AppImage)" = "manual false"
check "no errors in a good list" test "$(jq '.errors | length' <<<"$d")" = 0

note "ignore"
us ignore package:restic
d=$(us diff --json)
check "an ignored item is no longer ticked" test "$(st package:restic)" = "missing false"
check "and is marked ignored" test "$(jq -r '.items[] | select(.key == "package:restic") | .ignored' <<<"$d")" = true
check "the ignore file is plain text" grep -qx 'package:restic' "$H/.config/understudy/ignore"
us unignore package:restic
d=$(us diff --json)
check "unignore brings it back" test "$(st package:restic)" = "missing true"
check "a bad key is refused" bash -c '! "$@" 2>/dev/null' _ us ignore 'package:$(id)'

# ------------------------------------------------------------- dry run

note "dry run"
reset_log
plan=$(us plan)
if [[ ${UPDATE_SNAPSHOTS:-} == 1 ]]; then
  printf '%s\n' "$plan" | sed "s|$ROOT|<root>|g" >"$SNAP"
fi
check "the plan matches tests/snapshots/plan.txt" diff <(printf '%s\n' "$plan" | sed "s|$ROOT|<root>|g") "$SNAP"
check "the dry run runs nothing" bash -c '! grep -E "^(omarchy-pkg|omarchy-theme|omarchy-plugin-(add|enable)|omarchy-install|omarchy-webapp|omarchy-tui|setsid|sudo|yay|flatpak install)" "$1"' _ "$LOG"
pj=$(us plan --json)
check "--json carries the same commands" test "$(jq -r '.groups[].commands[]' <<<"$pj" | head -1)" = "omarchy-install-browser brave"
check "--only narrows the plan" test "$(us plan --json --only package:rclone aur:my-aur-tool | jq -c '[.groups[].commands[]]')" = '["omarchy-pkg-add rclone","omarchy-pkg-aur-add my-aur-tool"]'
check "a hardware item can be ticked by hand" test "$(us plan --json --only package:nvidia-dkms | jq -r '.groups[0].commands[0]')" = "omarchy-pkg-add nvidia-dkms"
out=$(us plan --only package:asusctl 2>&1); rc=$?
check "an item that cannot be installed here is refused" bash -c '[[ $1 == 2 ]] && grep -q "cannot be installed here" <<<"$2"' _ "$rc" "$out"
out=$(us plan --only package:nope 2>&1); rc=$?
check "an item not in the list is refused" bash -c '[[ $1 == 2 ]] && grep -q "not in the list" <<<"$2"' _ "$rc" "$out"

# ---------------------------------------------------------------- apply

note "apply: saying no"
reset_log
out=$(printf 'n\n' | us apply 2>&1); rc=$?
check "prints the plan and asks" bash -c 'grep -q "Continue? \[y/N\]" <<<"$1" && grep -q "omarchy-pkg-add rclone restic" <<<"$1"' _ "$out"
check "no means nothing runs" bash -c '[[ $1 != 0 ]] && ! grep -E "^(omarchy-pkg|omarchy-theme-install|omarchy-plugin-add|omarchy-install)" "$2"' _ "$rc" "$LOG"
out=$(us apply </dev/null 2>&1)
check "no answer at all is a no" bash -c '! grep -E "^(omarchy-pkg|omarchy-install)" "$1"' _ "$LOG"

note "apply: stop on the first failure"
echo rclone >"$S/fail-pkgs"
cp "$S/installed" "$ROOT/installed.before"
reset_log
out=$(printf 'y\n' | us apply 2>&1); rc=$?
check "exits non-zero" test "$rc" != 0
check "installers ran first" bash -c 'head -n 2 <(grep -E "^omarchy-install" "$1") | grep -q steam' _ "$LOG"
check "nothing after the failed group ran" bash -c '! grep -E "^(omarchy-pkg-aur-add|omarchy-theme-install|omarchy-plugin-add|omarchy-webapp|omarchy-tui|flatpak install)" "$1"' _ "$LOG"
check "the summary says where it stopped" bash -c 'grep -q "Stopped: \`omarchy-pkg-add rclone restic\` exited 1" <<<"$1"' _ "$out"
rm -f "$S/fail-pkgs"
cp "$ROOT/installed.before" "$S/installed"

note "apply: everything"
reset_log
out=$(printf 'y\n' | us apply 2>&1); rc=$?
check "exits 0" test "$rc" = 0
order=$(grep -E "^(omarchy-install|omarchy-pkg|flatpak install|omarchy-theme-(install|set|bg-set)|omarchy-plugin-(add|enable)|omarchy-webapp|omarchy-tui)" "$LOG" | sed "s|$ROOT|<root>|g; s/ *$//")
expected="omarchy-install-browser brave
omarchy-install-gaming-steam
omarchy-pkg-add rclone restic
omarchy-pkg-aur-add my-aur-tool
flatpak install flathub com.example.Tool
omarchy-theme-install https://github.com/someone/omarchy-sunset-theme.git
omarchy-theme-set tokyo-night
omarchy-theme-bg-set <root>/omarchy/themes/tokyo-night/bg.jpg
omarchy-theme-install https://github.com/someone/omarchy-private-theme.git
omarchy-theme-set tokyo-night
omarchy-theme-bg-set <root>/omarchy/themes/tokyo-night/bg.jpg
omarchy-plugin-add https://github.com/acme/omarchy-weather.git --yes
omarchy-plugin-enable acme.weather
omarchy-plugin-add https://github.com/acme/off.git --yes
omarchy-plugin-add git@github.com:acme/tallbar.git --yes
omarchy-webapp-install Notes https://notes.example.com/app
omarchy-tui-install Top btop float utilities-terminal"
check "one group at a time, in order, with the theme put back after each" test "$order" = "$expected"
[[ $order == "$expected" ]] || diff <(echo "$expected") <(echo "$order")
check "the theme in use is the one from before" test "$(cat "$CUR/theme.name")" = tokyo-night
check "and so is the background" test "$(readlink "$CUR/background")" = "$OP/themes/tokyo-night/bg.jpg"
check "the whole-bar plugin was not enabled" bash -c '! grep -q "omarchy-plugin-enable acme.tallbar" "$1"' _ "$LOG"
check "a plugin off on main was not enabled" bash -c '! grep -q "omarchy-plugin-enable acme.off" "$1"' _ "$LOG"
check "the theme already here was not touched" bash -c '! grep -q "^omarchy-theme-install .*already-theme" "$1"' _ "$LOG"
check "sudo and yay were never called directly" bash -c '! grep -qE "^(sudo|yay) " "$1"' _ "$LOG"
check "prints a summary" bash -c 'grep -q "^== Summary ==" <<<"$1" && grep -q "^Done." <<<"$1"' _ "$out"
reset_log
out=$(printf 'y\n' | us apply 2>&1)
check "a second run has nothing left to do" bash -c 'grep -q "Nothing to install." <<<"$1" && ! grep -qE "^omarchy-(pkg|theme-install|plugin-add)" "$2"' _ "$out" "$LOG"

note "a list that hides a whole bar"
cp "$ROOT/installed.fresh" "$S/installed"
cat >"$ROOT/sneaky.toml" <<'EOT'
format = 1
generated_at = "2026-10-30T12:00:00Z"
label = "sneaky"

[[plugins]]
id = "acme.sneakybar"
source = "https://github.com/acme/sneakybar.git"
enabled = true

[[packages]]
name = "linux-zen"
repo = "extra"
EOT
echo "https://github.com/acme/sneakybar.git acme.sneakybar" >>"$S/url-ids"
echo acme.sneakybar >"$S/bar-ids"
check "a kernel the list did not mark is hardware-specific here anyway" \
  test "$(us diff --json --list "$ROOT/sneaky.toml" | jq -r '.items[] | select(.key == "package:linux-zen") | "\(.hardware) \(.default)"')" = "true false"
reset_log
out=$(printf 'y\n' | us apply --list "$ROOT/sneaky.toml" 2>&1)
check "a bar the list called a widget is added but not switched to" \
  bash -c 'grep -q "^omarchy-plugin-add https://github.com/acme/sneakybar.git --yes" "$1" && ! grep -q "^omarchy-plugin-enable" "$1" && grep -q "is a whole bar" <<<"$2"' _ "$LOG" "$out"

note "terminal"
rm -rf "$H/.config/omarchy/themes/sunset"
reset_log
check "opens a terminal" us terminal --only theme:sunset
line=$(grep '^setsid ' "$LOG")
check "through the Omarchy terminal" bash -c 'grep -q "^setsid uwsm-app -- xdg-terminal-exec --app-id=org.omarchy.terminal --title=Understudy -e /usr/bin/python3 -I -S " <<<"$1"' _ "$line"
check "running apply with the item keys as arguments, no shell string" bash -c 'grep -q " apply --hold --list .* --only theme:sunset$" <<<"$1" && ! grep -q "bash -c" <<<"$1"' _ "$line"
reset_log
out=$(us terminal --only package:asusctl 2>&1); rc=$?
check "refuses before opening anything for an item it would skip" bash -c '[[ $1 != 0 ]] && ! grep -q "^setsid" "$2"' _ "$rc" "$LOG"

# -------------------------------------------------------- hostile lists

note "lists written to cause trouble"
cp "$ROOT/installed.fresh" "$S/installed"
HOST="$ROOT/hostile.toml"
cat >"$HOST" <<'EOF'
format = 1
generated_at = "2026-10-30T12:00:00Z"
label = "evil"

[[packages]]
name = "rclone"
repo = "extra"

[[packages]]
name = "foo; rm -rf ~"

[[packages]]
name = "--overwrite=*"

[[aur]]
name = "-Syu"

[[installers]]
command = "omarchy-install-../../../bin/sh"
packages = ["x"]

[[installers]]
command = "omarchy-install-gaming-steam"
args = ["--now"]
packages = ["steam"]

[[themes]]
name = "ext"
source = "ext::sh -c touch% /tmp/pwned"

[[themes]]
name = "local"
source = "file:///etc"

[[themes]]
name = "creds"
source = "https://tim:hunter2@github.com/x/omarchy-y-theme.git"

[[themes]]
name = "plain-http"
source = "http://github.com/x/omarchy-z-theme.git"

[[themes]]
name = ".."
source = "https://github.com/x/omarchy-dots-theme.git"

[[plugins]]
id = "x.proxy"
source = "git@github.com:-oProxyCommand=touch/tmp/pwned"

[[plugins]]
id = "--yes"
source = "https://github.com/x/y.git"

[[webapps]]
name = "Evil"
url = "javascript:alert(1)"

[[webapps]]
name = "../../.config/hypr/hyprland"
url = "https://example.com"

[[tuis]]
name = "Multi"
command = """btop
Exec=touch /tmp/pwned"""
style = "float"

[[flatpaks]]
id = "--user"
remote = "flathub"

[[packages]]
name = "rclone"
repo = "extra"

[[plugins]]
id = "x.notalist"
source = ["https://github.com/x/y.git"]
EOF
reset_log
hd=$(us diff --json --list "$HOST")
check "a hostile list still loads" test -n "$hd"
check "only the good entry survives, once" test "$(jq -c '[.items[].key]' <<<"$hd")" = '["package:rclone"]'
check "every bad entry is reported" test "$(jq '.errors | length' <<<"$hd")" = 17
check "credentials are never echoed back" bash -c '! grep -q hunter2 <<<"$1"' _ "$hd"
hp=$(us plan --list "$HOST")
check "the plan holds only the good entry" test "$(grep -c '^  \$ ' <<<"$hp")" = 1
check "nothing ran" bash -c '! grep -E "^(omarchy-pkg|omarchy-theme|omarchy-plugin-(add|enable)|omarchy-install|omarchy-webapp|omarchy-tui|setsid|sudo|yay|flatpak install)" "$1"' _ "$LOG"
check "no file was dropped" test ! -e /tmp/pwned

# The stock URL checker has the last word on any URL that gets past ours.
mv "$STUB/omarchy-git-url-check" "$ROOT/checker"
stub omarchy-git-url-check 'exit 1'
check "a URL the stock checker refuses is skipped" test "$(us diff --json --list "$FIX" | jq '[.items[] | select(.kind == "theme" and .status != "manual")] | length')" = 0
rm "$STUB/omarchy-git-url-check"
check "and with no checker at all, every source is refused" test "$(us diff --json --list "$FIX" | jq '[.errors[] | select(test("omarchy-git-url-check"))] | length')" = 6
mv "$ROOT/checker" "$STUB/omarchy-git-url-check"

note "files that are not lists"
head -c 1100000 /dev/zero | tr '\0' '#' >"$ROOT/huge.toml"
out=$(us diff --list "$ROOT/huge.toml" 2>&1); rc=$?
check "a file over 1 MiB is not read" bash -c '[[ $1 != 0 ]] && grep -q "never more than" <<<"$2"' _ "$rc" "$out"
printf 'format = 2\n' >"$ROOT/f2.toml"
out=$(us diff --list "$ROOT/f2.toml" 2>&1); rc=$?
check "another format is refused" bash -c '[[ $1 != 0 ]] && grep -q "not an Understudy list" <<<"$2"' _ "$rc" "$out"
printf '<html>nope</html>\n' >"$ROOT/junk.toml"
out=$(us diff --list "$ROOT/junk.toml" 2>&1); rc=$?
check "something that is not TOML is refused" bash -c '[[ $1 != 0 ]] && grep -q "not a readable Understudy list" <<<"$2"' _ "$rc" "$out"
printf 'format = 1\npackages = "rclone"\n' >"$ROOT/shape.toml"
check "a category that is not a list of entries is an error, not a crash" \
  test "$(us diff --json --list "$ROOT/shape.toml" | jq '.errors | length')" = 1

finish
