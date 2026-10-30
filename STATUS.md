# Understudy v0.2 — status

- **Branch:** `feat/v0.2`, from `origin/main` at `ed51af4` (v0.1 merged). PR https://github.com/ninepointlabs/understudy/pull/2 merged to `main` on 2026-10-30 as `8a5ea66`.
- Commits are by Nine Point Labs <179739321+ninepointlabs@users.noreply.github.com>.
- Manifest version 0.2.0. The list format stays `format = 1`: `category` is an optional key, so v0.1 lists still import here and
  v0.1 secondaries ignore it.

## What was built

| Feature | Where |
|---|---|
| **Categories.** Every item gets one of Gaming, Dev, CLI/TUI, Office, Media, Internet/Communication, System/Hardware, Themes/Look, Other. Main writes it into the list; the secondary works it out when the list has none (or one it doesn't know) | `bin/understudy` `categorize()`, `package_facts()`, `set_categories()`; `scan`, `export`, `diff` |
| **Overrides** in `~/.config/understudy/config.toml` `[categories]` (`"package:steam" = "Other"`); `understudy category KEY CATEGORY`, `--clear`, and no args to list. The secondary's override wins over main's category | `cmd_category`, `read_config`/`write_config` |
| **Skip by type**: `skip_categories = ["Gaming"]`, `understudy skip CATEGORY` / `unskip`, and in the overlay `C` → Space per category | `diff()`, `left_out()`, `cmd_skip`; QML category panel |
| **Removed on main**: history of lists read on the secondary in `~/.local/state/understudy/history.json` (last 50); a reminder section with a copyable remove command per item; `X` / `understudy dismiss KEY` (`undismiss`) | `record_history`, `removed_on_main`, `cmd_removed`, `cmd_dismiss` |
| **Menu entry**: `understudy setup omarchy` / `understudy remove omarchy`, a marked block in `~/.config/omarchy/extensions/omarchy-menu.jsonc` | `cmd_setup`, `cmd_remove`, `jsonc_scan`, `omarchy_menu_parse` |
| **Overlay**: sections by category with counts (`N · x to install · y ticked`), fold with ←/→ or Space on a section, `C` category panel (skip checkboxes on the secondary, Enter = show only that category), `G` switches back to v0.1's by-type grouping, "Removed on main" section with `Y` copy (via `wl-copy`) and `X` dismiss | `Understudy.qml`, `UnderstudyModel.js` (`buildCategoryRows`, `buildMainCategoryRows`, `buildCategoryPanelRows`, `toggleSkip`, `toggleCollapsed`, …) |
| README: install and removal steps with `setup omarchy` / `remove omarchy`, categories, overrides, skipping, Removed on main, new keys and commands, list sample with `category` | `README.md` |

### Decisions (flagged)

- **Category order of precedence**: user override → known names (a built-in list, plus `omarchy-install-gaming-*` etc. by installer
  name, plus name patterns such as `ttf-*` fonts → Themes/Look, `wine*`/`proton*` → Gaming, `python-*`/`*-sdk` → Dev) → hardware-specific
  → `.desktop` Categories → **terminal-only program** (files in `/usr/bin`, no `.desktop`) → pacman groups → description keywords →
  Other. The brief listed the terminal-only rule without a slot; I put it right after `.desktop` because "has a binary and no
  launcher" is as hard a fact as a `.desktop` file and much more reliable than description keywords. Themes are always Themes/Look,
  TUI launchers always CLI/TUI, a whole-bar plugin Themes/Look, a web app with nothing else to go on Internet/Communication.
- **Where the facts come from.** Main: `pacman -Qi` (already read; now also Groups and Description) and one `pacman -Ql -- names…`
  call; `.desktop` files are read from `$XDG_DATA_DIRS/applications`; Flatpaks from their exported `.desktop`; plugins from their
  manifest's `description`. Secondary (only for items with no usable category): `pacman -Si -- names…` for packages it does not
  have (description and groups; no `.desktop` without the files db), `-Qi`/`-Ql` for ones it does.
- **Skipped = folded and unticked** (both). The section starts folded, so the Surface opens without Gaming in view, and when Tim
  unfolds it nothing in it is ticked. `plan`/`apply` with no `--only` never include a skipped item and the plan says
  "Left out: N items in categories this machine skips (Gaming)". Only keys passed with `--only` — which the overlay builds from what
  Tim ticked by hand — can include one. Hiding alone would make "show it, then tick it" awkward; unticked alone would leave a
  long Gaming section on the Surface every time.
- **Removed on main: reminder only, no uninstall action.** Each item shows a command to copy: `omarchy pkg drop NAME` for packages,
  AUR packages and installers (the installer's own package), `omarchy theme remove`, `omarchy plugin remove`,
  `omarchy webapp remove`, `omarchy tui remove`, `flatpak uninstall`, `rm ~/Applications/NAME.AppImage`. For installers I did **not**
  suggest Omarchy's `omarchy remove …` scripts: some delete data (`omarchy-remove-gaming-steam` deletes `~/.steam` and the game
  libraries). Understudy runs none of these.
- **What counts as "Removed on main"**: in a list from main older than the current one, not in the current one, not dismissed,
  and present here: packages installed **explicitly** (`pacman -Qqe`, so nothing that is only a dependency) and **not an Omarchy
  default on this machine** (same default set as main uses); user theme folders (not built-ins); user plugin folders (not
  `omarchy.*`); web app / TUI `.desktop` files; Flatpaks; AppImages. I read "(or that are non-default here)" as a filter on
  "installed", not as "anything this machine added that main doesn't have" — the latter would list the Surface's own hardware
  packages as "removed on main".
- **History**: recorded when the secondary reads its list (from the shared folder or the imported copy; `diff`, which the overlay
  runs on every open) and on `import`. Once per list, keyed by `generated_at`; a list named with `--list` is a one-off and not
  recorded. The first v0.2 run on the Surface has no history, so the section stays empty until main exports a changed list (the
  last imported copy, if older, is recorded too). Dismissals are in `config.toml` (`dismissed = [...]`), not the ignore file:
  "don't offer to install" and "don't remind me it was dropped" are different.
- **Menu**: the block goes right after the top-level `{` (as OmaForge does). The `when` is
  `test -f "$HOME/.config/omarchy/plugins/ninepointlabs.understudy/manifest.json"`. Setup removes any top-level `"understudy"`
  entry outside the markers (one-line or multi-line, found with a small JSONC scanner that skips strings and comments), and
  `"install.understudy"` only when its value toggles `ninepointlabs.understudy` (v0.1's README suggested that key). Remove takes out
  the block and those same entries when they toggle Understudy. Unlike OmaForge it does not rewrite or back up when nothing would
  change, so running it twice leaves one backup, not two. It refuses (and changes nothing) when the file is not a JSONC object it
  can read, and checks the result parses the way Omarchy's `MenuModel.js` parses it (whole-line `//` comments and trailing commas
  stripped, then JSON) with no repeated key. File mode is kept; backups are `omarchy-menu.jsonc.bak.<YYYYmmdd-HHMMSS>[-n]`.
- **No category override in the overlay** — helper command only, as the brief asked. Easy to add (a key on an item) if wanted.
- **v0.1 by-type grouping kept** behind `G`, so the old view (and its model tests) still work.

### Fixed along the way

- In `tests/lib.sh`, `us` was a shell function, so checks written `check "…" bash -c '! "$@"' _ us …` (bad role, hostile folder,
  bad ignore key, …) ran a command that didn't exist and passed whatever the helper did. `us` and the variables it needs are now
  exported, and `main_test.sh` checks the helper really runs inside `bash -c`. All of those checks still pass, now for real.
- `tests/fixtures/list.toml` is renamed `list-v0.1.toml` (it is the v0.1 shape, the "old list" fixture); `list-v0.2.toml` is new.
- `KEEP_ROOT=1 tests/…_test.sh` keeps the throwaway world for debugging.

## Verification

| Check | Result |
|---|---|
| `tests/main_test.sh` | **92 passed**, 0 failed (v0.1: 61) |
| `tests/secondary_test.sh` | **140 passed**, 0 failed (v0.1: 73) |
| `tests/model_test.sh` (node) | **68 passed**, 0 failed (v0.1: 34) |
| `tests/menu_test.sh` (new) | **43 passed**, 0 failed |
| Total | **343 passed**, 0 failed |
| `omarchy plugin validate .` | passes (silent, exit 0) |
| `qmllint -I "$OMARCHY_PATH/shell" Understudy.qml` | 49 warnings, the same as v0.1 in number and kind (48 `unqualified`, 1 `missing-property`: the `qs.*` singletons and `ConfirmDialog.selectedIndex`); no new kinds |
| Plan snapshot (`tests/snapshots/plan.txt`) | unchanged |

New tests cover: the category of each kind and each rule (known names, installer names, hardware, `.desktop` Categories, terminal-only
programs, Flatpak `.desktop`, plugin description words, whole-bar plugins, web apps, groups and description via `pacman -Si` on the
secondary), main writing categories into the list, overrides on main (into the list) and on the secondary (winning over main's),
`--clear`, bad keys and categories refused, a v0.1 list (all 23 items read, every one categorized here), a v0.2 list (main's category
kept, an unknown one re-derived), skip/unskip (config, any case, order, unknown refused), skipped items shown but unticked, left out of
`plan`/`apply` with the "Left out" line, included when passed by hand; history recorded once per list, not for `--list`, on `import`,
capped at 50, a tampered or non-JSON history file; Removed on main per kind with its command, not for Omarchy defaults, dependencies,
built-in themes, items not here or still on main, nothing run or removed, dismiss/undismiss, older-list ordering; menu setup on no
file, on a copy of the menu file shaped like both laptops' (hand-added line replaced, OmaForge and HEY blocks byte-identical, every
other line and comment kept, backup equals the original, mode kept), idempotent setup and remove, round trip, multi-line and
`install.understudy` hand entries, look-alike keys left alone, an unreadable file refused untouched, and that the real menu file is
never the one used. The model tests cover parsing categories/removed/skip, folded sections, filter, panel rows, skip toggling,
section navigation, and that skipped items are never remembered as ignored.

Read-only on TUF: `scan --offline` puts the 83 items in all nine categories (e.g. Gaming 9: steam and lutris installers, OmaForge,
ProtonUp-Qt…; Themes/Look 15; System/Hardware 9 incl. the g14 packages). `diff --list ./tmp/understudy.toml` (TUF's own v0.1 export)
reads all 83 with 0 errors and works out every category. Nothing was written to `~/.config/understudy`, `~/.local/state/understudy`
(still absent), `~/.config/omarchy` or the installed plugin copy. The real `omarchy-menu.jsonc` is byte-identical to the fixture I
copied from it.

## Hand test

On TUF (main):

1. Update the installed copy (`git -C ~/.config/omarchy/plugins/ninepointlabs.understudy pull` once merged, or check out
   `feat/v0.2` there), then `~/.config/omarchy/plugins/ninepointlabs.understudy/bin/understudy setup omarchy`. It should say it
   backed up the menu. Open the Omarchy menu: one Understudy row, OmaForge, HEY and Barkeep still there. Run it again: "already in
   the Omarchy menu".
2. Open Understudy: sections by category with counts. ←/→ folds, G switches to by-type and back, C → Enter on Gaming shows only
   Gaming, C → Enter on All shows everything.
3. `understudy category package:discord Media`, rescan (S): discord is under Media. Export (Enter). `--clear` it afterwards.

On the Surface (secondary):

4. Update the plugin, run `understudy setup omarchy` as on TUF.
5. Open Understudy: sections by category. Press C, Space on Gaming ("skipped on this laptop"), Esc: Gaming is folded; → unfolds it
   with nothing ticked. D: no Steam/Lutris commands, and a "Left out: … (Gaming)" line. Tick one Gaming item by hand, D: it is there.
6. Close and reopen: Gaming still folded (`skip_categories = ["Gaming"]` in `~/.config/understudy/config.toml`).
7. Removed on main, without changing TUF: once the Surface has read the current list, copy it
   (`cp ~/Documents/understudy/understudy.toml /tmp/u.toml`), delete one entry the Surface has installed (e.g. a `[[packages]]`
   block), make `generated_at` later, and `understudy import /tmp/u.toml`. Reopen: the item is under "Removed on main" with e.g.
   `omarchy pkg drop NAME`. Y copies it (paste to check), X hides it. Nothing is removed. Export on TUF again afterwards (or
   `rm ~/.local/state/understudy/imported.toml`) to go back to the real list.
8. `understudy remove omarchy` and `understudy setup omarchy` once each, to see both work on the real file (each keeps a backup).

## Caveats

- The overlay still has not been run inside the shell (same as v0.1): layout, key handling and the new section rows are covered by
  the model tests and qmllint only. Likely spots for a tweak: the longer key hints in the footer (they may crowd the status text on
  a narrow screen) and focus after the C panel closes.
- Categories are heuristics. On TUF a few land oddly (Barkeep → System/Hardware from its description, the Understudy plugin itself →
  Internet/Communication from "sync"); overrides are the fix. The known-names list is short on purpose.
- Removing an item from the list on main by hand-editing the file changes nothing until `generated_at` changes (history is per list).
- `wl-copy` is assumed for Y (it is on stock Omarchy); if it fails the overlay says so.
- Everything in v0.1's caveats still applies.

DONE
