# Understudy v0.1 — status

- **Branch:** `feat/v0.1`, pushed to https://github.com/ninepointlabs/understudy (public) and merged to `main` through PR #1
- **Code commit:** `7cdce3e` ("Understudy v0.1: make a second Omarchy laptop match the main one"), followed by this STATUS.md,
  committed as Nine Point Labs <179739321+ninepointlabs@users.noreply.github.com>

## What was built

| File | What |
|---|---|
| `manifest.json` | id `ninepointlabs.understudy`, name Understudy, 0.1.0, MIT, kinds `["overlay"]` (no service needed) |
| `Understudy.qml` | the overlay: role switch (Main/Secondary), main view (scan, export, export to path, auto-export toggle), secondary view (grouped missing items with checkboxes and notes, dry-run pane, install confirm → terminal, import from path, show all), folder prompt. Keyboard-driven; uses the shell's menu theme tokens, no hardcoded colors |
| `UnderstudyModel.js` | pure model: parsing helper output, default ticks, tick/untick → ignore/unignore, grouping, navigation |
| `bin/understudy` | the helper: `role`, `status`, `config`, `scan`, `export`, `import`, `diff`, `plan`, `apply`, `terminal`, `ignore`/`unignore`; no args toggles the overlay |
| `tests/` | `main_test.sh`, `secondary_test.sh`, `model_test.sh`, shared `lib.sh` stubs, `fixtures/list.toml`, `snapshots/plan.txt` |
| `README.md`, `LICENSE` | install + removal, key binding, menu entry, both roles, Syncthing setup, plain-file fallback, dry run, sample list, safety, dependencies |

### Decisions (flagged)

- **Helper is Python 3, standard library only** (not bash + jq like NPL Inventory). The secondary must parse an untrusted TOML
  file; `tomllib` does that properly and bash cannot. It runs as `/usr/bin/python3 -I -S` (shebang and overlay argv), so a
  mise/conda Python on PATH is never used.
- **Settings live in `~/.config/understudy/config.toml`** (role, folder, label, auto_export), not in shell.json. Shell plugin
  settings are inline entries in `shell.json` aimed at bar widgets; a file of our own keeps the helper usable from a terminal and
  means Understudy never writes the shell's file.
- **"Enabled on main"** = `omarchy plugin list --json` `.enabled` **or** id in `shell.json plugins[]`. On TUF, `plugins[]` lists only 6
  of the 13 enabled plugins (bar widgets placed in the bar are enabled but not in `plugins[]`), so `plugins[]` alone would have
  turned most of them off on the secondary. It is used alone only when the shell isn't running.
- **Installer mapping rule** (built from `$OMARCHY_PATH/bin/omarchy-install-*` at runtime): a package maps to an installer when it is
  the first literal package that installer (or one `case` branch of it, e.g. `browser brave`) adds, and it appears in no other
  installer. `omarchy-install-terminal`'s `omarchy-pkg-add $package` maps each choice to the same-named package. Skipped as
  generic or out of scope: `install-app`, `install-and-launch`, `install-font`, `install-preinstalls`, `install-dev-env` (mise),
  `install-docker-dbs`, `install-gaming-gpu-lib32`, and anything whose args are flags (`hermes-cli`, `openclaw-cli`).
- **Defaults** = the two `.packages` lists + the dependency closure of `omarchy`/`omarchy-settings` (via `pacman -Qi`, following
  `Provides`) + the first pacstrap line. That is why "beyond defaults" on TUF is 63, not the 71 you get from the two lists alone.
- **AUR** = `pacman -Qqm` minus defaults, as briefed (25 on TUF; 24 of those are explicit).
- **Unticking remembers** the item in `~/.config/understudy/ignore` (it stays in view for the rest of that visit, then hides; H shows
  it, ticking it un-ignores it). Hardware items start unticked and ticking/unticking them is not remembered.
- **Credentials in a git remote** (anything before `@` in an https URL, user:pass or a token) make export **refuse** for the whole
  list, naming the item, never echoing the secret. Web apps whose URL query looks like it carries a token are left out with a warning.
- **Private repos** are detected at export with an anonymous `git -c credential.helper= ls-remote` (parallel, 15 s timeout each);
  `--offline` skips it and the overlay's scan is always offline. For my TUF runs I used `--offline` only, to stay within the
  read-only commands the brief lists, so private detection is verified with stubs only.
- **Install terminal** = `setsid uwsm-app -- xdg-terminal-exec --app-id=org.omarchy.terminal --title=Understudy -e /usr/bin/python3 -I -S
  <helper> apply --hold --list <path> --only <keys…>` — the same launcher shape as `omarchy-launch-floating-terminal-with-presentation`,
  but as an argv with no `bash -c` string.
- Commands run as the direct binaries (`omarchy-pkg-add`, `omarchy-theme-install`, …) rather than `omarchy pkg add`; the dry run
  shows exactly what runs.
- Hardware marking is applied again on the secondary (kernel/ucode/dkms/driver/g14 patterns + `$OMARCHY_PATH/install/hardware/**`),
  and whether a just-added plugin is a whole bar is read from the shell after it is installed, not from the list, so a list
  cannot get a bar switched on.

## Verification

| Check | Result |
|---|---|
| `omarchy plugin validate .` | passes (silent, exit 0) |
| `qmllint -I "$OMARCHY_PATH/shell" *.qml` (`/usr/lib/qt6/bin/qmllint`; not on PATH) | exit 0; 49 warnings, all the same classes NPL Inventory's overlay has (80 there): `unqualified` access to the shell's `Style`/`Util` singletons and to `parent` inside `qs.Ui` types, and `ConfirmDialog.selectedIndex` "missing" — qmllint can't resolve the `qs.*` imports. Not clean, but nothing new in kind |
| `tests/main_test.sh` | 61 passed, 0 failed |
| `tests/secondary_test.sh` | 73 passed, 0 failed |
| `tests/model_test.sh` (node) | 34 passed, 0 failed |
| Symlinks in repo | none |
| Headless QML load | **not done** — NPL Inventory has none to copy, and loading the overlay needs the running shell (`qs.*` imports); I did not install it into your live config |

Tests cover: default set (lists, closure, pacstrap) and diff, installer mapping (incl. case branches, `$package`, ambiguity, flag
installers), hardware marking (repo, patterns, Omarchy hardware scripts, re-marked on secondary), themes/plugins/launchers/flatpak/
AppImage detection, hidden `.bak` plugin folders not shadowing real ones, manifest round-trip, no personal paths/hostname in the
file, credentials refusal, hostile lists (bad names, `--`/`-` options, `ext::`, `file://`, `http://`, creds, `git@…:-o…`, `..`,
`/` in names, multi-line TUI command, wrong types, duplicates, >1 MiB, wrong format, non-TOML, checker refusal/absence), command
building, dry-run snapshot, apply order, "no" and EOF answers, stop on first failure, theme + background switch-back, existing-theme
skip, whole-bar plugin not enabled, terminal argv, shared-folder-missing fallback, newer-list-wins, ignore file. Every external
command is a stub; the helper's PATH holds only stubs and a few coreutils (Omarchy installs its commands into `/usr/bin`, so
`/usr/bin` is deliberately not on it).

## TUF scan summary (counts only, `scan --offline`)

- Omarchy 4.0.6-1, first install 2026-08-19
- 227 explicit packages · 63 beyond all defaults (71 beyond the two `.packages` lists alone) · 25 foreign
- Omarchy installers 12 · repo packages 20 (3 hardware-specific) · AUR 25 (1 hardware-specific)
- Themes 12 (11 with git URL, 1 manual) · plugins 14 (11 with git URL, 3 manual)
- Web apps 0 · TUI launchers 0 · Flatpaks 0 (flatpak not installed) · AppImages 0
- Exported to `./tmp/understudy.toml` (gitignored, not committed): 83 entries; `diff` against TUF itself reports everything as
  already here, `plan` says "Nothing to install". No home paths or credentials in the file.
- Nothing was written to `~/.config/understudy`, `~/.local/state/understudy`, `~/.config/omarchy`, bindings or menu.

## Hand-test on the Surface

1. On TUF: `omarchy plugin add https://github.com/ninepointlabs/understudy.git --enable`, open the overlay, press M (Main), then S to scan.
   Check the counts match the summary above.
2. Set up `~/Sync/understudy` in Syncthing and share it with the Surface (README, "Set up the shared folder"). Press Enter to export.
   Open the file and read it: names and URLs only.
3. On the Surface: install the plugin, accept the Syncthing share at the same path, open Understudy, press S (Secondary).
4. Check: btop-style packages already there show only with H; `asusctl`, `rog-control-center`, `supergfxctl` show as
   hardware-specific and unticked (and `needs the [g14] repo` where the Surface lacks it); grok theme and the npl-inventory,
   update-arcade and omostrich plugins show "manual: no source URL"; private repos say they need `gh auth login`.
5. Untick one item, close and reopen: it is gone; H shows it as ignored.
6. Press D and read the commands. Then tick a small set (one repo package, one theme, one plugin) and press Enter → Open terminal.
   The terminal prints the plan and asks `Continue? [y/N]`; answer y. pacman asks for the password there.
7. After it finishes: your theme and background are the ones you had; the plugin is enabled only if it was on TUF; reopening the
   overlay shows those items as installed.
8. Fallback: `understudy export /some/stick/` on TUF and `understudy import /some/stick/understudy.toml` on the Surface.

## Caveats

- The overlay was not run inside the shell (not installed, per the brief), so its layout, key handling and focus are untested
  beyond qmllint and the model tests. Most likely spots to need a tweak: the prompt bar, the plan pane's scrolling, and the
  role-chooser buttons.
- `pacman -Sl` repo attribution takes the first repo listing a package; on TUF `supergfxctl` shows `[omarchy]` because that repo
  is listed before `[g14]`. Harmless (it is still marked hardware-specific), but the repo label can be the "wrong" one.
- Packages in one group are installed with a single `omarchy-pkg-add a b c`; one bad name fails the whole group (then it stops).
- Omarchy installers may themselves prompt, open apps or start services (e.g. Tailscale runs `tailscale up`). That is the point of
  using them, but the terminal session can be interactive.
- TUI launchers carry a command line that runs when the launcher is opened; it is validated (printable, ≤512 chars, no newline,
  no leading `-`) and shown in full, but it is a command by nature.
- Flatpak installs use `flatpak install <remote> <id>` (system-wide by default), as briefed.
- Anonymous private-repo detection treats "gone" and "private" the same.

## Before a marketplace submission

- The repo is public at https://github.com/ninepointlabs/understudy, matching the README install URL.
- No `preview.png` (couldn't render the overlay without installing it). Optional, but worth adding after the Surface test.
- Check the id/name against the live registry (publish skill step 2) — I did not fetch the registry.
- Expect `review-required`: README and code mention `sudo`, `omarchy pkg add`/`omarchy-pkg-add`, `yay`, `pacman` (→ `privilege`,
  `package-manager`, likely `installer`).
- A hand test on real hardware (above) should precede submission.

DONE
