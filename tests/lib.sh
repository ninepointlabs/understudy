# tests/lib.sh — shared by the *_test.sh scripts; sourced, not run.
#
# Builds a throwaway world under $ROOT: a HOME, a fake $OMARCHY_PATH with
# installer scripts and package lists to read, and stub commands for pacman,
# pacman-conf, yay, git, flatpak, sudo, the omarchy commands and the terminal
# launcher. Every stub logs its call to $LOG and acts only on files under
# $ROOT. Nothing reaches the network or the real config.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO/bin/understudy"
pass=0
fail=0

ok()   { printf '  ok    %s\n' "$*"; pass=$((pass + 1)); }
bad()  { printf '  FAIL  %s\n' "$*"; fail=$((fail + 1)); }
note() { printf '\n%s\n' "$*"; }
check() { # description, then a command that must succeed
  local desc="$1"; shift
  if "$@"; then ok "$desc"; else bad "$desc"; fi
}
finish() {
  printf '\n%d passed, %d failed\n' "$pass" "$fail"
  (( fail == 0 ))
}

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/understudy-test.XXXXXX")"
trap "${KEEP_ROOT:+:} rm -rf \"$ROOT\"" EXIT   # KEEP_ROOT=1 keeps the world for a look
[[ -n ${KEEP_ROOT:-} ]] && echo "test world: $ROOT" >&2
H="$ROOT/home"
OP="$ROOT/omarchy"
STUB="$ROOT/stub"
S="$ROOT/state"          # what the stubs answer with
LOG="$ROOT/calls"
mkdir -p "$ROOT/usr/share/applications" "$ROOT/flatpak/exports/share/applications" "$S/si" "$S/ql"
mkdir -p "$H" "$OP/bin" "$OP/install/hardware" "$OP/applications" "$OP/themes/tokyo-night" "$STUB" "$S"
: >"$LOG"

# The helper's PATH is the stubs plus a handful of plain system tools the
# stubs use. Omarchy installs its commands into /usr/bin, so /usr/bin itself
# is never on it: a command that is not stubbed does not exist.
SYS="$ROOT/sys"
mkdir -p "$SYS"
for tool in bash cat grep mkdir ln basename sed tr cut mv rm awk jq printf head; do
  ln -s "$(command -v "$tool")" "$SYS/$tool"
done

# Runs the helper in the throwaway world.
us() {
  env -i HOME="$H" OMARCHY_PATH="$OP" PATH="$STUB:$SYS" LANG=C.UTF-8 \
    XDG_DATA_DIRS="$ROOT/usr/share" FLATPAK_SYSTEM_DIR="$ROOT/flatpak" \
    UNDERSTUDY_PACMAN_LOG="$S/pacman.log" STUB_STATE="$S" STUB_LOG="$LOG" STUB_HOME="$H" \
    "$HELPER" "$@"
}
# So `check "..." bash -c '! "$@"' _ us ...` runs the helper, rather than
# failing because a function is not a command.
export -f us
export H OP STUB S SYS LOG ROOT HELPER

calls() { cat "$LOG"; }
reset_log() { : >"$LOG"; }

stub() { # name, body (bash)
  printf '#!/bin/bash\nprintf "%%s\\n" "%s $*" >>"$STUB_LOG"\n%s\n' "$1" "$2" >"$STUB/$1"
  chmod +x "$STUB/$1"
}

# ------------------------------------------------------------------- stubs

stub pacman '
case "$1" in
  -Qqe) cat "$STUB_STATE/explicit" ;;
  -Qqm) cat "$STUB_STATE/foreign" ;;
  -Qq) cat "$STUB_STATE/installed" ;;
  -Qi) cat "$STUB_STATE/qi" ;;
  -Sl) cat "$STUB_STATE/sl" ;;
  # One file per package: $STUB_STATE/si/NAME (pacman -Si) and
  # $STUB_STATE/ql/NAME (the paths pacman -Ql lists).
  -Si) shift; [[ $1 == -- ]] && shift; rc=0
    for p in "$@"; do if [[ -f $STUB_STATE/si/$p ]]; then cat "$STUB_STATE/si/$p"; echo; else echo "error: package '"'"'$p'"'"' was not found" >&2; rc=1; fi; done
    exit $rc ;;
  -Ql) shift; [[ $1 == -- ]] && shift
    for p in "$@"; do [[ -f $STUB_STATE/ql/$p ]] && sed "s|^|$p |" "$STUB_STATE/ql/$p"; done; exit 0 ;;
  -Q) [[ $2 == omarchy ]] && echo "omarchy 4.0.6-1" || exit 1 ;;
  *) echo "pacman stub: refusing $*" >&2; exit 1 ;;
esac'
stub pacman-conf '[[ $1 == --repo-list ]] && cat "$STUB_STATE/repos"'
stub sudo 'echo "sudo must never run" >&2; exit 1'
stub yay 'echo "yay must not be called directly" >&2; exit 1'
stub git '
if [[ $1 == -C && $3 == remote && $4 == get-url ]]; then
  cat "$2/.git/origin-url" 2>/dev/null || exit 2
elif [[ $* == *ls-remote* ]]; then
  [[ $* == *private* ]] && { echo "fatal: could not read Username" >&2; exit 128; }
  exit 0
else
  echo "git stub: refusing $*" >&2; exit 1
fi'
stub flatpak '
case "$1" in
  list) cat "$STUB_STATE/flatpaks" 2>/dev/null ;;
  remotes) cat "$STUB_STATE/remotes" 2>/dev/null ;;
  install) echo "$3" >>"$STUB_STATE/flatpaks" ;;
  *) exit 1 ;;
esac'
stub omarchy-plugin-list '[[ -e $STUB_STATE/no-shell ]] && exit 1; cat "$STUB_STATE/plugins.json"'
add_pkgs='
for p in "$@"; do grep -qx -- "$p" "$STUB_STATE/fail-pkgs" 2>/dev/null && { echo "error: target not found: $p" >&2; exit 1; }; done
printf "%s\n" "$@" >>"$STUB_STATE/installed"'
stub omarchy-pkg-add "$add_pkgs"
stub omarchy-pkg-aur-add "$add_pkgs"
stub omarchy-theme-install '
url="$1"; slug=$(basename "$url" .git | sed -E "s/^omarchy-//; s/-theme$//" | tr A-Z a-z)
mkdir -p "$STUB_HOME/.config/omarchy/themes/$slug"
echo "$slug" >"$STUB_HOME/.local/state/omarchy/current/theme.name"
ln -sfn "$STUB_HOME/.config/omarchy/themes/$slug/bg.jpg" "$STUB_HOME/.local/state/omarchy/current/background"'
stub omarchy-theme-set 'echo "$1" >"$STUB_HOME/.local/state/omarchy/current/theme.name"'
stub omarchy-theme-bg-set 'ln -sfn "$1" "$STUB_HOME/.local/state/omarchy/current/background"'
stub omarchy-plugin-add '
id=$(grep -F -- "$1 " "$STUB_STATE/url-ids" | cut -d" " -f2)
mkdir -p "$STUB_HOME/.config/omarchy/plugins/$id"
printf "{\"id\":\"%s\"}\n" "$id" >"$STUB_HOME/.config/omarchy/plugins/$id/manifest.json"
kind=bar-widget; grep -qx -- "$id" "$STUB_STATE/bar-ids" 2>/dev/null && kind=bar
jq --arg id "$id" --arg kind "$kind" ". + [{id: \$id, enabled: false, firstParty: false, kinds: [\$kind]}]" "$STUB_STATE/plugins.json" >"$STUB_STATE/p.tmp" && mv "$STUB_STATE/p.tmp" "$STUB_STATE/plugins.json"'
stub omarchy-plugin-enable 'exit 0'
stub omarchy-webapp-install 'mkdir -p "$STUB_HOME/.local/share/applications"; echo "Exec=omarchy-launch-webapp $2" >"$STUB_HOME/.local/share/applications/$1.desktop"'
stub omarchy-tui-install 'mkdir -p "$STUB_HOME/.local/share/applications"; echo "Exec=xdg-terminal-exec --app-id=TUI.$3 -e $2" >"$STUB_HOME/.local/share/applications/$1.desktop"'
for i in omarchy-install-gaming-steam omarchy-install-browser omarchy-install-terminal omarchy-install-gaming-lutris; do
  stub "$i" 'grep -qx -- "'"$i"'" "$STUB_STATE/fail-installers" 2>/dev/null && exit 1
awk -v c="'"$i"'" -v a="${1:--}" '"'"'$1 == c && $2 == a { print $3 }'"'"' "$STUB_STATE/installer-pkgs" 2>/dev/null >>"$STUB_STATE/installed"'
done
stub setsid 'exit 0'
# The stock checker's rules: no options, no `helper::`, only known transports.
stub omarchy-git-url-check '
url="${1-}"
[[ -n $url && $url != -* && ! $url =~ ^[A-Za-z0-9][A-Za-z0-9+.-]*:: ]] || exit 1
if [[ $url =~ ^([A-Za-z0-9][A-Za-z0-9+.-]*):// ]]; then
  case "${BASH_REMATCH[1]}" in ssh|git|git+ssh|ssh+git|http|https|ftp|ftps|file) exit 0 ;; *) exit 1 ;; esac
fi
exit 0'

# ------------------------------------------------------------- fake omarchy

printf '# base\ngit\nyay\n\nhyprland # the compositor\n' >"$OP/install/omarchy-base.packages"
printf 'chromium\n' >"$OP/install/omarchy-other.packages"
echo "4.0.0" >"$OP/version"
cat >"$OP/install/hardware/asus.sh" <<'EOF'
if omarchy-hw-asus; then
  omarchy-pkg-add asusctl
fi
EOF

installer() { # name, args spec, body
  printf '#!/bin/bash\n\n# omarchy:summary=test\n%s\n%s\n' "${2:+# omarchy:args=$2}" "$3" >"$OP/bin/$1"
}
installer omarchy-install-gaming-steam "" 'omarchy-pkg-add steam'
installer omarchy-install-gaming-lutris "" 'omarchy-pkg-add lutris umu-launcher wine-staging'
installer omarchy-install-gaming-battlenet "" 'omarchy-pkg-add umu-launcher'
installer omarchy-install-browser "<chrome|brave|firefox>" 'case $1 in
chrome)
  omarchy-pkg-aur-add google-chrome || exit 1
  ;;
brave)
  omarchy-pkg-aur-add brave-bin || exit 1
  ;;
firefox)
  omarchy-pkg-add firefox || exit 1
  ;;
esac'
installer omarchy-install-terminal "<alacritty|ghostty>" 'package="$1"
if omarchy-pkg-add $package; then echo ok; fi'
installer omarchy-install-app "<display-name> <packages>" 'omarchy-pkg-add $2'
installer omarchy-install-shared-a "" 'omarchy-pkg-add shared-first'
installer omarchy-install-shared-b "" 'omarchy-pkg-add shared-first other'
installer omarchy-install-hermes-cli "<--check|--now>" 'omarchy-pkg-add hermes-desktop'
printf '[Desktop Entry]\nName=X\nExec=omarchy-launch-webapp https://x.com/\n' >"$OP/applications/X.desktop"
