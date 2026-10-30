#!/bin/bash

# tests/main_test.sh — the main laptop's side: scan and export.
#
#   tests/main_test.sh
#
# A fake main laptop under a throwaway HOME (see tests/lib.sh): what counts as
# a default, the installer map, hardware marking, themes, plugins, launchers,
# what the list file may and may not contain, the missing-folder fallback, and
# that scanning changes nothing.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ------------------------------------------------------------ the machine

# The pacstrap line names the base set; a later pacman -S line must not.
cat >"$S/pacman.log" <<'EOF'
[2026-08-19T16:23:52+0000] [PACMAN] Running 'pacman -b /mnt//var/lib/pacman/ -r /mnt -Sy --noconfirm --needed --config=/tmp/pacman.conf.x --cachedir=/mnt//var/cache/pacman/pkg/ base sudo linux linux-firmware amd-ucode'
[2026-08-19T16:30:00+0000] [PACMAN] Running 'pacman -S --noconfirm --needed vulkan-radeon'
EOF
printf '%s\n' base sudo linux linux-firmware amd-ucode git yay hyprland chromium omarchy jq \
  btop rclone steam brave-bin ghostty lutris wine-staging umu-launcher shared-first asusctl \
  nvidia-dkms vulkan-radeon my-aur-tool asus-tuf-keyboard-rgb-manager-git >"$S/explicit"
printf '%s\n' brave-bin my-aur-tool asus-tuf-keyboard-rgb-manager-git >"$S/foreign"
cp "$S/explicit" "$S/installed"
# omarchy depends on jq and on sh (which bash provides); hypridle comes in
# through jq to show the closure is followed.
cat >"$S/qi" <<'EOF'
Name            : omarchy
Version         : 4.0.6-1
Depends On      : jq>=1.7  sh
                  hypridle
Provides        : None

Name            : jq
Depends On      : None
Provides        : None

Name            : bash
Depends On      : None
Provides        : sh

Name            : hypridle
Depends On      : None
Provides        : None
EOF
cat >"$S/sl" <<'EOF'
core base 3-1 [installed]
core sudo 1.9 [installed]
extra btop 1.4 [installed]
extra rclone 1.70 [installed]
multilib steam 1.0 [installed]
extra ghostty 1.2 [installed]
extra lutris 0.5 [installed]
extra wine-staging 10 [installed]
extra umu-launcher 1 [installed]
extra shared-first 1 [installed]
g14 asusctl 6.1 [installed]
extra nvidia-dkms 575 [installed]
extra vulkan-radeon 25 [installed]
EOF
printf '%s\n' core extra multilib g14 >"$S/repos"
# What pacman -Ql says the packages put where, for their categories: a
# .desktop file says Office; a program in /usr/bin with no .desktop file is
# terminal-only.
printf '%s\n' /usr/bin/ /usr/bin/shared /usr/share/applications/shared.desktop >"$S/ql/shared-first"
printf '%s\n' /usr/bin/ /usr/bin/my-aur-tool /usr/share/man/man1/my-aur-tool.1.gz >"$S/ql/my-aur-tool"
printf '[Desktop Entry]\nType=Application\nName=Shared\nCategories=Office;Utility;\n' >"$ROOT/usr/share/applications/shared.desktop"
printf '[Desktop Entry]\nType=Application\nName=Tool\nCategories=Game;\n' >"$ROOT/flatpak/exports/share/applications/com.example.Tool.desktop"
printf 'com.example.Tool\tflathub\n' >"$S/flatpaks"

mkdir -p "$H/.local/state/omarchy/done" "$H/.local/state/omarchy/current"
touch -d 2026-08-19 "$H/.local/state/omarchy/done/first-run-user"

theme() { # folder, origin url or ""
  mkdir -p "$H/.config/omarchy/themes/$1"
  if [[ -n $2 ]]; then mkdir -p "$H/.config/omarchy/themes/$1/.git"; echo "$2" >"$H/.config/omarchy/themes/$1/.git/origin-url"; fi
}
theme sunset "https://github.com/someone/omarchy-sunset-theme.git"
theme secret "https://github.com/someone/omarchy-private-theme.git"
theme handmade ""
theme tokyo-night "https://github.com/basecamp/omarchy-tokyo-night.git"   # named like a built-in
mkdir -p "$H/.config/omarchy/themes/.sunset.bak"

plugin() { # folder, id, origin url or ""
  local d="$H/.config/omarchy/plugins/$1"
  mkdir -p "$d"
  printf '{"id":"%s","name":"%s","kinds":["bar-widget"]}\n' "$2" "$2" >"$d/manifest.json"
  if [[ -n $3 ]]; then mkdir -p "$d/.git"; echo "$3" >"$d/.git/origin-url"; fi
}
plugin acme.weather acme.weather "https://github.com/acme/omarchy-weather.git"
plugin odd-folder tim.odd "git@github.com:tim/odd.git"
plugin acme.local acme.local ""
plugin acme.tallbar acme.tallbar "https://github.com/acme/tallbar.git"
plugin acme.off acme.off "https://github.com/acme/off.git"
printf '{"id":"acme.off","name":"acme.off","kinds":["bar-widget"],"description":"Unread e-mail in the bar"}\n' >"$H/.config/omarchy/plugins/acme.off/manifest.json"
# A backup copy with the same id and no remote must not hide the real one.
plugin .acme.weather.bak.123 acme.weather ""
cat >"$S/plugins.json" <<'EOF'
[
  {"id": "omarchy.clock", "name": "Clock", "enabled": true, "firstParty": true, "kinds": ["bar-widget"]},
  {"id": "acme.weather", "name": "Weather", "enabled": true, "firstParty": false, "kinds": ["bar-widget"]},
  {"id": "tim.odd", "name": "Odd", "enabled": false, "firstParty": false, "kinds": ["overlay"]},
  {"id": "acme.local", "name": "Local", "enabled": true, "firstParty": false, "kinds": ["service"]},
  {"id": "acme.tallbar", "name": "Tall Bar", "enabled": true, "firstParty": false, "kinds": ["bar"]},
  {"id": "acme.off", "name": "Off", "enabled": false, "firstParty": false, "kinds": ["bar-widget"]}
]
EOF
printf '{"plugins": [{"id": "tim.odd"}]}\n' >"$H/.config/omarchy/shell.json"

A="$H/.local/share/applications"
mkdir -p "$A" "$H/Applications/build" "$H/Applications/tools" "$H/.local/bin"
printf '[Desktop Entry]\nName=Notes\nExec=omarchy-launch-webapp "https://notes.example.com/app"\nIcon=notes\n' >"$A/Notes.desktop"
printf '[Desktop Entry]\nName=X\nExec=omarchy-launch-webapp https://x.com/\n' >"$A/X.desktop"
printf '[Desktop Entry]\nName=Leaky\nExec=omarchy-launch-webapp https://leaky.example.com/?token=abc123\n' >"$A/Leaky.desktop"
printf '[Desktop Entry]\nName=Top\nExec=xdg-terminal-exec --app-id=TUI.float -e btop\nIcon=/home/someone/icons/top.png\n' >"$A/Top.desktop"
printf '[Desktop Entry]\nName=Files\nExec=nautilus\n' >"$A/Files.desktop"
touch "$H/Applications/Tool-1.0.AppImage" "$H/Applications/tools/Other.AppImage" "$H/Applications/build/Junk.AppImage"

# ------------------------------------------------------------------ scan

note "the defaults"
scan=$(us scan --json --offline)
check "scan exits 0" test -n "$scan"
names() { jq -r --arg k "$1" '[.rows[] | select(.kind == $k) | .name] | join(" ")' <<<"$scan"; }
pkgs=$(names package)
check "repo packages are what was added, by name ($pkgs)" test "$pkgs" = "asusctl btop nvidia-dkms rclone shared-first vulkan-radeon"
check "lists in install/*.packages are defaults (git, hyprland, chromium)" bash -c '! grep -qw -e git -e hyprland -e chromium <<<"$1"' _ "$pkgs"
check "the pacstrap set is a default (base, sudo, linux, amd-ucode)" bash -c '! grep -qw -e base -e sudo -e linux -e amd-ucode <<<"$1"' _ "$pkgs"
check "omarchy's dependency closure is a default (jq, via sh)" bash -c '! grep -qw -e jq <<<"$1"' _ "$pkgs"
check "AUR packages are the foreign ones not covered by an installer" test "$(names aur)" = "asus-tuf-keyboard-rgb-manager-git my-aur-tool"
check "counts explicit and beyond the defaults" test "$(jq -c .packages <<<"$scan")" = '{"explicit":25,"beyond_defaults":14,"foreign":3}'

note "installer map"
inst=$(names installer)
check "steam, lutris, a browser branch and a terminal map to installers ($inst)" \
  test "$inst" = "omarchy-install-browser brave omarchy-install-gaming-lutris omarchy-install-gaming-steam omarchy-install-terminal ghostty"
check "lutris covers what its installer adds (wine-staging, umu-launcher)" bash -c '! grep -qw -e wine-staging -e umu-launcher <<<"$1"' _ "$pkgs"
check "a package first in two installers stays a package" bash -c 'grep -qw shared-first <<<"$1"' _ "$pkgs"
check "installers taking flags or free-form args are never used" bash -c '! grep -q -e hermes -e install-app <<<"$1"' _ "$inst"

note "hardware"
hw() { jq -r --arg n "$1" '.rows[] | select(.name == $n) | .note' <<<"$scan" | grep -q hardware-specific; }
check "a package from the [g14] repo is hardware-specific" hw asusctl
check "a -dkms package is hardware-specific" hw nvidia-dkms
check "a GPU driver is hardware-specific" hw vulkan-radeon
check "an asus AUR package is hardware-specific" hw asus-tuf-keyboard-rgb-manager-git
check "btop is not" bash -c '! jq -r ".rows[] | select(.name == \"btop\") | .note" <<<"$1" | grep -q hardware' _ "$scan"

note "themes, plugins, launchers"
check "user themes, minus one named like a built-in and the hidden backup" test "$(names theme)" = "handmade secret sunset"
check "a theme without a remote is manual" bash -c 'jq -r ".rows[] | select(.name == \"handmade\") | .note" <<<"$1" | grep -q "manual: no source URL"' _ "$scan"
check "user plugins only, never omarchy.*" test "$(names plugin)" = "acme.local acme.off acme.tallbar acme.weather tim.odd"
check "the backup folder did not hide the real plugin's remote" bash -c 'jq -r ".rows[] | select(.name == \"acme.weather\") | .note" <<<"$1" | grep -q github.com/acme/omarchy-weather' _ "$scan"
check "a plugin in a folder named unlike its id still finds its remote" bash -c 'jq -r ".rows[] | select(.name == \"tim.odd\") | .note" <<<"$1" | grep -q "git@github.com:tim/odd.git"' _ "$scan"
check "web app found; the shipped one and one with a token in its URL are not" test "$(names webapp)" = "Notes"
check "the token URL is named in a warning" bash -c 'jq -r ".warnings[]" <<<"$1" | grep -q Leaky' _ "$scan"
check "TUI launcher found" test "$(names tui)" = "Top"
check "flatpak found" test "$(names flatpak)" = "com.example.Tool"
check "AppImages by file name, skipping build folders" test "$(names appimage)" = "Other.AppImage Tool-1.0.AppImage"
check "first install date from first-run-user" test "$(jq -r .first_install <<<"$scan")" = "2026-08-19"

note "no plugin list from the shell"
touch "$S/no-shell"
noshell=$(us scan --json --offline)
check "falls back to the plugin folders and shell.json" bash -c 'jq -r "[.rows[] | select(.kind == \"plugin\") | .name] | join(\" \")" <<<"$1" | grep -q "acme.weather"' _ "$noshell"
check "and says so" bash -c 'jq -r ".warnings[]" <<<"$1" | grep -q "did not answer"' _ "$noshell"
rm -f "$S/no-shell"

note "categories"
cat_of() { jq -r --arg n "$1" '.rows[] | select(.name == $n) | .category' <<<"$scan"; }
check "a known game installer is Gaming" test "$(cat_of omarchy-install-gaming-steam)" = Gaming
check "the lutris installer is Gaming" test "$(cat_of omarchy-install-gaming-lutris)" = Gaming
check "a browser installer is Internet/Communication" test "$(cat_of "omarchy-install-browser brave")" = Internet/Communication
check "the terminal installer is CLI/TUI" test "$(cat_of "omarchy-install-terminal ghostty")" = CLI/TUI
check "a known CLI tool (btop) is CLI/TUI" test "$(cat_of btop)" = CLI/TUI
check "a known name (rclone) is Internet/Communication" test "$(cat_of rclone)" = Internet/Communication
check "a package's .desktop Categories decide when the name is unknown (Office)" test "$(cat_of shared-first)" = Office
check "a program with no .desktop file is CLI/TUI" test "$(cat_of my-aur-tool)" = CLI/TUI
check "hardware-specific packages are System/Hardware" bash -c '[[ $(jq -r "[.rows[] | select(.name == \"asusctl\" or .name == \"nvidia-dkms\" or .name == \"vulkan-radeon\" or .name == \"asus-tuf-keyboard-rgb-manager-git\") | .category] | unique | join(\" \")" <<<"$1") == System/Hardware ]]' _ "$scan"
check "themes are Themes/Look" test "$(jq -r '[.rows[] | select(.kind == "theme") | .category] | unique | join(" ")' <<<"$scan")" = Themes/Look
check "a whole-bar plugin is Themes/Look" test "$(cat_of acme.tallbar)" = Themes/Look
check "a plugin's description words decide (e-mail: Internet/Communication)" test "$(cat_of acme.off)" = Internet/Communication
check "a plugin with nothing to go on is Other" test "$(cat_of acme.weather)" = Other
check "a web app named for notes is Office" test "$(cat_of Notes)" = Office
check "a TUI launcher is CLI/TUI" test "$(cat_of Top)" = CLI/TUI
check "a flatpak's exported .desktop file decides (Game)" test "$(cat_of com.example.Tool)" = Gaming
check "an AppImage with nothing to go on is Other" test "$(cat_of Other.AppImage)" = Other
check "every row has exactly one known category" \
  test "$(jq -r '[.rows[] | select(.category | IN("Gaming","Dev","CLI/TUI","Office","Media","Internet/Communication","System/Hardware","Themes/Look","Other") | not)] | length' <<<"$scan")" = 0

# ---------------------------------------------------------------- export

note "export"
before=$(cd "$H" && find . -printf '%p %s %T@\n' | sort | md5sum)
reset_log
out=$(us export 2>&1); rc=$?
check "export with no shared folder fails with code 3" test "$rc" = 3
check "and says so plainly, offering a path" bash -c 'grep -q "does not exist" <<<"$1" && grep -q "understudy export PATH" <<<"$1"' _ "$out"
mkdir -p "$H/Sync/understudy"
before=$(cd "$H" && find . -path ./Sync -prune -o -printf '%p %s %T@\n' | sort | md5sum)
check "export to the shared folder" us export
L="$H/Sync/understudy/understudy.toml"
check "the list is there" test -s "$L"
after=$(cd "$H" && find . -path ./Sync -prune -o -printf '%p %s %T@\n' | sort | md5sum)
check "scan and export changed nothing else under HOME" test "$before" = "$after"
check "and ran no installer, package, theme or plugin command" bash -c '! grep -E "^(omarchy-pkg|omarchy-theme|omarchy-plugin-(add|enable)|omarchy-install|omarchy-webapp|omarchy-tui|sudo|yay|flatpak install)" "$1"' _ "$LOG"
check "has format, date, version and the label" bash -c 'grep -qx "format = 1" "$1" && grep -q "^generated_at = \"20" "$1" && grep -qx "omarchy_version = \"4.0.6-1\"" "$1" && grep -qx "label = \"main\"" "$1"' _ "$L"
check "no hostname in it" bash -c '! grep -qi -- "$(cat /etc/hostname 2>/dev/null || echo no-hostname-here)" "$1"' _ "$L"
check "no personal paths in it (HOME, the icon path)" bash -c '! grep -q -e "$2" -e /home/ "$1"' _ "$L" "$H"
check "the private repo is marked private (anonymous ls-remote refused)" \
  bash -c 'python3 -c "import tomllib,sys; d=tomllib.load(open(sys.argv[1],\"rb\")); t={x[\"name\"]:x for x in d[\"themes\"]}; sys.exit(0 if t[\"secret\"].get(\"private\") and not t[\"sunset\"].get(\"private\") else 1)" "$1"' _ "$L"
check "the TUI icon path became a plain icon name" grep -q 'icon = "utilities-terminal"' "$L"
check "main writes each item's category into the list" \
  python3 -c 'import tomllib,sys; d=tomllib.load(open(sys.argv[1],"rb")); i={x["command"]:x for x in d["installers"]}; t=[x for k in d for x in (d[k] if isinstance(d[k], list) else [])]; sys.exit(0 if i["omarchy-install-gaming-steam"]["category"] == "Gaming" and all("category" in x for x in t) else 1)' "$L"
check "enabled and bar flags carried" \
  python3 -c 'import tomllib,sys; d={p["id"]:p for p in tomllib.load(open(sys.argv[1],"rb"))["plugins"]}; sys.exit(0 if d["acme.weather"]["enabled"] and not d["acme.off"]["enabled"] and d["tim.odd"]["enabled"] and d["acme.tallbar"].get("bar") else 1)' "$L"
reset_log
us export --offline >/dev/null
check "--offline asks no remote anything" bash -c '! grep -q ls-remote "$1"' _ "$LOG"

note "round trip"
rt=$(us diff --json --list "$L")
total=$(jq '[.rows[]] | length' <<<"$scan")
check "everything exported reads back ($total items)" test "$(jq '.items | length' <<<"$rt")" = "$total"
check "and none of it is reported broken" test "$(jq '.errors | length' <<<"$rt")" = 0
check "on the machine it came from, it is all here or manual" test "$(jq '[.items[] | select(.status == "missing")] | length' <<<"$rt")" = 0

note "fallback path"
mkdir -p "$ROOT/usb"
check "export to any folder" us export "$ROOT/usb" --offline
check "writes understudy.toml there" test -s "$ROOT/usb/understudy.toml"
echo "precious" >"$ROOT/usb/notes.txt"
out=$(us export "$ROOT/usb/notes.txt" --offline 2>&1); rc=$?
check "refuses to overwrite a file that is not a list" bash -c '[[ $1 != 0 ]] && grep -q "not an Understudy list" <<<"$2" && [[ $(cat "$3") == precious ]]' _ "$rc" "$out" "$ROOT/usb/notes.txt"
out=$(us export "$ROOT/nowhere/x.toml" 2>&1); rc=$?
check "a missing parent folder is an error" bash -c '[[ $1 != 0 ]] && grep -q "does not exist" <<<"$2"' _ "$rc" "$out"

note "credentials in a remote"
echo "https://tim:hunter2@github.com/acme/omarchy-weather.git" >"$H/.config/omarchy/plugins/acme.weather/.git/origin-url"
cp "$L" "$ROOT/before.toml"
out=$(us export --offline 2>&1); rc=$?
check "export refuses" test "$rc" != 0
check "names the plugin and the problem" bash -c 'grep -q acme.weather <<<"$1" && grep -q credentials <<<"$1"' _ "$out"
check "never prints the password" bash -c '! grep -q hunter2 <<<"$1"' _ "$out"
check "and leaves the old list alone" cmp -s "$L" "$ROOT/before.toml"
echo "https://ghp_abcdef@github.com/acme/omarchy-weather.git" >"$H/.config/omarchy/plugins/acme.weather/.git/origin-url"
check "a token as the user name is refused too" bash -c '! "$@" >/dev/null 2>&1' _ us export --offline
echo "https://github.com/acme/omarchy-weather.git" >"$H/.config/omarchy/plugins/acme.weather/.git/origin-url"

note "role and settings"
check "the helper runs inside bash -c, so the refusal checks below are real" bash -c 'us --help | grep -q "understudy role"'
check "role starts unset" test "$(us role)" = unset
us role main >/dev/null
check "role main is kept in config.toml" grep -qx 'role = "main"' "$H/.config/understudy/config.toml"
check "a bad role is refused" bash -c '! "$@" 2>/dev/null' _ us role boss
check "label can be set" us config label "tuf"
check "a hostile folder is refused" bash -c '! "$@" 2>/dev/null' _ us config folder "relative/path"
check "status reports the folder" test "$(us status --json | jq -r .folderExists)" = true
us export --offline >/dev/null
check "the label goes in the list" grep -qx 'label = "tuf"' "$L"

note "category overrides"
check "an override is set with understudy category" us category package:btop media
check "kept in config.toml's [categories] table" bash -c 'grep -qx "\[categories\]" "$1" && grep -qx "\"package:btop\" = \"Media\"" "$1"' _ "$H/.config/understudy/config.toml"
check "and the other settings are kept" grep -qx 'label = "tuf"' "$H/.config/understudy/config.toml"
check "the override wins over the built-in mapping" test "$(us scan --json --offline | jq -r '.rows[] | select(.name == "btop") | .category')" = Media
us export --offline >/dev/null
check "and main writes it into the list" python3 -c 'import tomllib,sys; d=tomllib.load(open(sys.argv[1],"rb")); sys.exit(0 if {x["name"]:x for x in d["packages"]}["btop"]["category"] == "Media" else 1)' "$L"
check "an unknown category is refused" bash -c '! "$@" 2>/dev/null' _ us category package:btop Snacks
check "a bad key is refused" bash -c '! "$@" 2>/dev/null' _ us category 'package:$(id)' Dev
check "understudy category lists the override" bash -c '"$@" | grep -q "package:btop = Media"' _ us category
check "--clear takes it out" us category package:btop --clear
check "and the built-in category is back" test "$(us scan --json --offline | jq -r '.rows[] | select(.name == "btop") | .category')" = CLI/TUI
check "the config still reads after all that" test "$(us role)" = main

finish
