# Understudy

Make a second Omarchy laptop match the main one.

On the **main** laptop, Understudy lists what you added after the first
Omarchy install: packages, AUR packages, Omarchy installers, themes, plugins,
web apps and TUI launchers (and Flatpaks and AppImages, if you have any). It
writes that list to one plain, readable file in a shared folder.

On the **second** laptop, Understudy reads the file, shows only what is
missing there, grouped by what it is for (Gaming, Dev, Media…), lets you tick
what you want, shows exactly what will run, and then installs it in a
terminal. Categories you never want there (say, Gaming on a work laptop) can
be skipped. It never removes anything: when the main laptop drops something,
Understudy only reminds you, with the command to remove it yourself.

## What it does not do

- No dotfiles, app settings, plugin settings, mise tools, keys, SSH or GPG,
  browser profiles or secrets. It carries a list of names and source URLs,
  nothing else.
- It does not set up Syncthing (or anything else) to move the file, and it
  never reads Syncthing's config.
- It never removes, downgrades or replaces anything, never edits
  `/etc/pacman.conf`, and never runs `sudo` on its own.
- It does not keep the two machines in sync continuously. You export on the
  main laptop, and install on the second when you choose to.

## Install

```bash
omarchy plugin add https://github.com/ninepointlabs/understudy.git --enable
~/.config/omarchy/plugins/ninepointlabs.understudy/bin/understudy setup omarchy
```

Do this on both laptops. The second line adds Understudy to the Omarchy menu
(see below); leave it out if you don't want that.

### Open it

```bash
omarchy-shell shell toggle ninepointlabs.understudy
```

To bind a key, add one line to `~/.config/hypr/bindings.lua` (Hyprland
reloads on save):

```lua
o.bind("SUPER + SHIFT + U", "Understudy", "omarchy-shell shell toggle ninepointlabs.understudy")
```

`SUPER + SHIFT + U` is free in stock Omarchy; check `omarchy menu keybindings
--print` if you have your own bindings.

`understudy setup omarchy` puts it in the Omarchy menu. It writes one marked
block to `~/.config/omarchy/extensions/omarchy-menu.jsonc` (creating the file
if there is none), the same way OmaForge and HEY do:

```jsonc
  // >>> understudy — managed by `understudy setup omarchy`, do not edit between the markers
  "understudy": {"icon":"󰌢","label":"Understudy","description":"Make this Omarchy laptop match the main one","action":"omarchy-shell shell toggle ninepointlabs.understudy","when":"test -f \"$HOME/.config/omarchy/plugins/ninepointlabs.understudy/manifest.json\""},
  // <<< understudy
```

The row only shows while the plugin is installed. Running it again changes
nothing; every other entry and comment in the file is left as it is, and the
old file is kept next to it as `omarchy-menu.jsonc.bak.<date>`. An
`"understudy"` entry you added by hand (or the `"install.understudy"` one
v0.1's README suggested) is replaced, so there is never a second one.

## Remove

```bash
~/.config/omarchy/plugins/ninepointlabs.understudy/bin/understudy remove omarchy
omarchy plugin remove ninepointlabs.understudy
```

The first line takes Understudy out of the Omarchy menu (with a backup of the
file, as above). Run it before removing the plugin, while the helper is still
there.

Then delete Understudy's own files if you want them gone too:

```bash
rm -rf ~/.config/understudy ~/.local/state/understudy
```

and the list in the shared folder (`~/Sync/understudy/understudy.toml`), and
the key binding if you added one. Nothing Understudy installed is removed;
those are ordinary packages, themes and plugins.

## Set up the shared folder

Understudy reads and writes `~/Sync/understudy/understudy.toml` by default.
Syncthing moves it between the laptops. Understudy does not configure
Syncthing for you; do this once:

1. On the main laptop, create the folder: `mkdir -p ~/Sync/understudy`.
2. Add it in Syncthing as a folder (in the web UI at `http://127.0.0.1:8384`,
   or from the OmaSyncthing bar widget).
3. Share it with the second laptop's device.
4. On the second laptop, accept the share, at the same path
   (`~/Sync/understudy`).
5. Open Understudy on each laptop and choose its role: **Main** on the main
   one, **Secondary** on the other.

To use a different folder, press `F` in the overlay or run
`understudy config folder ~/some/other/folder`.

### No Syncthing? Use a plain file

The list is a single file, so anything that moves a file works: a USB stick,
LocalSend, rclone, email.

- Main: press `P` in the overlay and type a path, or run
  `understudy export /run/media/you/stick/`.
- Second laptop: press `I` and type the path, or run
  `understudy import /run/media/you/stick/understudy.toml`.

`import` checks the file and keeps a copy, so the stick can go away. If the
shared folder has a newer list later, the newer one wins.

## Using it

### On the main laptop

| Key | Does |
|-----|------|
| S | scan again |
| Enter / E | export the list to the shared folder |
| P | export to a path you type |
| A | turn re-exporting on every open on or off (off by default) |
| C | categories: Enter shows only one (All shows everything) |
| G | group by category (the default) or by type |
| ← / → , Space on a section | fold or unfold a category |
| F | change the shared folder |
| Tab | switch this laptop to Secondary |
| Esc | close |

Scan and export change nothing on the main laptop except the list file.

### On the second laptop

| Key | Does |
|-----|------|
| ↑ / ↓, PgUp / PgDn, Home / End | move |
| Space | tick or untick (on a section: fold or unfold it) |
| ← / → | fold or unfold the category the cursor is in |
| C | categories: Space skips one on this laptop, Enter shows only one |
| G | group by category (the default) or by type |
| Y / X | on a "Removed on main" item: copy its remove command / stop reminding |
| D | show the exact commands (dry run) |
| Enter | install what is ticked (asks first, then opens a terminal) |
| I | import a list from a path you type |
| H | show everything, including what is installed or ignored |
| F | change the shared folder |
| Tab | switch this laptop to Main |
| Ctrl+R | read the list again |
| Esc | close the commands, then close |

Each item has a short note: the repo it comes from, the URL, or why it can't
be installed here. Anything you untick is remembered in
`~/.config/understudy/ignore` and stops showing (H shows it again; ticking it
brings it back).

### Categories

Every item has one: **Gaming**, **Dev**, **CLI/TUI**, **Office**, **Media**,
**Internet/Communication**, **System/Hardware**, **Themes/Look** or
**Other**. The main laptop works it out and writes it into the list; the
second laptop works it out itself for a list that has none (one from v0.1).
In order, the first that applies:

1. your own override (below),
2. a known name (Steam, Lutris, Heroic, ProtonUp-Qt, gamescope, MangoHud,
   OmaForge, Wine… are Gaming; the `omarchy-install-gaming-*` installers too),
3. hardware-specific items are System/Hardware; themes are Themes/Look; TUI
   launchers are CLI/TUI,
4. the `Categories` of the package's `.desktop` file (Game, Development,
   Office, AudioVideo/Audio/Video/Graphics, Network/Chat/Email,
   System/Settings),
5. a program with no `.desktop` file is CLI/TUI,
6. its pacman groups, then words in its description,
7. Other.

To put an item somewhere else, on either laptop:

```bash
understudy category package:steam Other     # set
understudy category package:steam --clear   # back to Understudy's choice
understudy category                         # list the categories and your overrides
```

Overrides live in `~/.config/understudy/config.toml` under `[categories]`.
The main laptop's override goes into the list; the second laptop's own
override wins over that.

### Skipping a category

Press `C` and tick **skip on this laptop** with Space, or run
`understudy skip Gaming` (and `understudy unskip Gaming`). It is kept as
`skip_categories = ["Gaming"]` in `config.toml`.

A skipped category is **folded and unticked**: its section starts closed, so
the list opens without it, and when you open it (→) nothing in it is ticked.
`plan` and `apply` leave it out (the plan says how many it left out); only an
item you tick by hand goes in.

### Removed on main

The second laptop remembers which items each list it has read had
(`~/.local/state/understudy/history.json`, the last 50 lists). When the main
laptop's list no longer has something an older one did, and this laptop has
it (installed explicitly, and not an Omarchy default here), it shows under
**Removed on main** with the command that would remove it, for example
`omarchy pkg drop restic`, `omarchy plugin remove acme.weather` or
`omarchy theme remove sunset`.

That is all it does. Understudy never removes anything; copy the command
(`Y`) and run it yourself if you want it gone. `X` (or
`understudy dismiss KEY`) stops the reminder for that item; `understudy
undismiss KEY` brings it back. `understudy removed` lists them in a terminal.

### What gets marked

- **hardware-specific**: kernels, microcode, boot packages, drivers, `-dkms`
  packages, what Omarchy's own hardware setup installs, and anything from a
  hardware repo such as `[g14]`. Shown, but unticked.
- **needs the [repo] repo**: the main laptop installed it from a repo the
  second one doesn't have. Skipped; Understudy never edits `pacman.conf`.
- **manual: no source URL**: a theme or plugin that is not a git clone on the
  main laptop. Copy it over yourself.
- **private repo**: cloning needs `gh auth login` on the second laptop first.
- AppImages are always **manual**.

### How things are installed

| Category | Command |
|---|---|
| Omarchy installers | `omarchy-install-…` (it also sets the app up, as Omarchy's menu would) |
| Repo packages | `omarchy-pkg-add <names>` (pacman; asks for your password) |
| AUR packages | `omarchy-pkg-aur-add <names>` (yay) |
| Flatpaks | `flatpak install <remote> <id>` |
| Themes | `omarchy-theme-install <url>`, then switches back to the theme and background you had |
| Plugins | `omarchy-plugin-add <url> --yes`, then `omarchy-plugin-enable <id>` only if it was on on the main laptop (a whole bar is never switched to) |
| Web apps | `omarchy-webapp-install <name> <url> ''` (fetches the site's icon) |
| TUI launchers | `omarchy-tui-install <name> <command> <float\|tile> <icon>` |

A package that one of Omarchy's installer scripts installs (Steam, Signal,
Spotify, 1Password, Tailscale, a browser, a terminal, an editor…) is carried
as that installer instead of the bare package. Understudy works this out by
reading the installer scripts in `$OMARCHY_PATH/bin`, not from a list of its
own.

## The dry run

Press `D`, or run `understudy plan`. Example:

```
Understudy plan from ~/Sync/understudy/understudy.toml (label main, 2026-10-30T12:00:00Z)

Omarchy installers:
  $ omarchy-install-gaming-steam

Repo packages:
  $ omarchy-pkg-add rclone restic

Themes:
  $ omarchy-theme-install https://github.com/someone/omarchy-sunset-theme.git
    then switch back to the tokyo-night theme and its background

Plugins:
  $ omarchy-plugin-add https://github.com/acme/omarchy-weather.git --yes
  $ omarchy-plugin-enable acme.weather
```

Install runs exactly these commands, in this order.

## Safety

- **Install opens a terminal.** It prints the whole plan, asks
  `Continue? [y/N]`, and only then runs anything. pacman and yay ask for your
  password there. Understudy never stores a password and never runs `sudo`
  itself.
- **Nothing is removed, downgraded or overwritten.** Anything already
  installed is shown as installed and skipped, and each step checks again
  right before it runs. A theme folder that already exists is skipped, since
  `omarchy theme install` would replace it.
- **One group at a time, stop on the first failure**, with a short summary at
  the end.
- **The list is treated as untrusted** on the second laptop. Every name is
  checked against a strict pattern (no leading `-`, no paths, no shell
  characters); only `https://` and `git@` URLs are accepted, and each must
  also pass Omarchy's own `omarchy-git-url-check`; URLs with credentials are
  refused; files over 1 MiB are not read. A bad entry is shown as an error and
  skipped. Every command is built as an argument list and run without a
  shell.
- **The list never holds secrets**: no tokens, keys, passwords, environment
  values, config file contents, plugin settings or personal paths. Export
  refuses outright if a theme or plugin's git remote has credentials in it,
  and leaves out web apps whose URL looks like it carries a token. There is no
  hostname in it unless you put one in the label.
- **TUI launchers carry a command.** That command runs when you open the
  launcher, so the plan shows it in full; untick it if you don't recognise it.

## The list file

Plain TOML, one table per category. A short one:

```toml
# Understudy list: what was added to an Omarchy laptop after its first install.
# Written by `understudy export`. Plain text; no secrets, settings or personal paths.
format = 1
generated_at = "2026-10-30T15:20:00Z"
omarchy_version = "4.0.6-1"
label = "main"

# Omarchy installers
[[installers]]
command = "omarchy-install-gaming-steam"
args = []
packages = ["steam"]
category = "Gaming"

# Repo packages
[[packages]]
name = "rclone"
repo = "extra"
category = "Internet/Communication"

[[packages]]
name = "asusctl"
repo = "g14"
hardware = true
category = "System/Hardware"

# AUR packages
[[aur]]
name = "orion-beta"
category = "Internet/Communication"

# Themes
[[themes]]
name = "sunset"
source = "https://github.com/someone/omarchy-sunset-theme.git"
category = "Themes/Look"

[[themes]]
name = "handmade"
manual = true
category = "Themes/Look"

# Plugins
[[plugins]]
id = "ninepointlabs.omasync"
name = "OmaSyncthing"
source = "https://github.com/ninepointlabs/omasync.git"
enabled = true
category = "Internet/Communication"
```

`category` is new in v0.2 and optional: a v0.2 second laptop reads a v0.1
list and works the categories out itself, and a v0.1 second laptop ignores
them.

Set the label with `understudy config label "tuf"`.

## Command line

The overlay calls a helper that works on its own too:

```
understudy                         toggle the overlay
understudy role [main|secondary]   show or set this machine's role
understudy status [--json]         role, shared folder, list file
understudy config KEY VALUE        folder PATH | label NAME | auto-export on|off
understudy scan [--json] [--offline]
understudy export [PATH] [--offline] [--force]
understudy import [PATH]
understudy diff [--json] [--list PATH]
understudy plan [--json] [--list PATH] [--only KEY...]
understudy apply [--list PATH] [--only KEY...]
understudy terminal [--list PATH] [--only KEY...]
understudy ignore KEY... | unignore KEY...
understudy category [KEY CATEGORY | KEY --clear]
understudy skip [CATEGORY] | unskip CATEGORY
understudy removed [--json] [--list PATH]
understudy dismiss KEY... | undismiss KEY...
understudy setup omarchy | remove omarchy
```

It lives at `~/.config/omarchy/plugins/ninepointlabs.understudy/bin/understudy`
once the plugin is installed. Item keys look like `package:rclone`,
`theme:sunset`, `installer:omarchy-install-browser=brave`.

`export` checks each theme and plugin URL with an anonymous `git ls-remote`
to mark private repos; `--offline` skips that. The overlay's scan is always
offline.

## How it works

- `Understudy.qml` is the overlay, `UnderstudyModel.js` its pure model code
  (grouping, ticks, navigation), and `bin/understudy` does all the work. The
  overlay only ever runs the helper with an argument array.
- **What counts as added.** Omarchy's defaults are every package in
  `$OMARCHY_PATH/install/omarchy-base.packages` and `omarchy-other.packages`,
  everything the `omarchy` and `omarchy-settings` packages depend on, and
  the base set from the first pacstrap line in `/var/log/pacman.log`.
  Packages are `pacman -Qqe` minus those, minus foreign packages, minus what
  an installer covers; AUR packages are `pacman -Qqm` minus the defaults.
  The date of the first install is the date of
  `~/.local/state/omarchy/done/first-run-user`.
- **Themes** are the folders in `~/.config/omarchy/themes` that are not
  built in; **plugins** are the non-`omarchy.*` ones from
  `omarchy plugin list --json`, each with the `origin` of its folder.
  **Web apps** and **TUI launchers** are the `.desktop` files in
  `~/.local/share/applications` that Omarchy created and did not ship.
- Settings are in `~/.config/understudy/config.toml` (role, folder, label,
  auto-export, skipped categories, dismissed reminders, category overrides),
  not in the shell's `shell.json`, so the helper works the same from a
  terminal.

## Dependencies

All present on a stock Omarchy install: `python3` (standard library only),
`pacman`, `git`, `omarchy-shell`, and the stock `omarchy-*` commands.
`yay` for AUR packages and `flatpak` for Flatpaks, only if the list has any.

Why Python and not bash: the second laptop has to parse an untrusted TOML
file, and Python's `tomllib` does that properly.

## Tests

```bash
tests/main_test.sh        # scan and export, against a fake main laptop
tests/secondary_test.sh   # diff, dry run, apply, hostile lists, against a fake second laptop
tests/model_test.sh       # the overlay's model, in node
tests/menu_test.sh        # setup omarchy / remove omarchy, on copies of a menu file
```

Every external command (pacman, yay, git, flatpak, sudo, the omarchy commands,
the terminal) is a stub; nothing touches the network or your real config.

## License

MIT. See [LICENSE](LICENSE).
