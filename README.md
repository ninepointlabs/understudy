# Understudy

Make a second Omarchy laptop match the main one.

On the **main** laptop, Understudy lists what you added after the first
Omarchy install: packages, AUR packages, Omarchy installers, themes, plugins,
web apps and TUI launchers (and Flatpaks and AppImages, if you have any). It
writes that list to one plain, readable file in a shared folder.

On the **second** laptop, Understudy reads the file, shows only what is
missing there, lets you tick what you want, shows exactly what will run, and
then installs it in a terminal. It never removes anything.

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
```

Do this on both laptops.

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

To put it in the Omarchy menu under **Install**, add one entry to
`~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"install.understudy": {"icon": "󰑓", "label": "Understudy", "description": "Make this laptop match the main one", "action": "omarchy-shell shell toggle ninepointlabs.understudy"},
```

## Remove

```bash
omarchy plugin remove ninepointlabs.understudy
```

Then delete Understudy's own files if you want them gone too:

```bash
rm -rf ~/.config/understudy ~/.local/state/understudy
```

and the list in the shared folder (`~/Sync/understudy/understudy.toml`), and
the key binding or menu entry if you added one. Nothing Understudy installed
is removed; those are ordinary packages, themes and plugins.

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
| F | change the shared folder |
| Tab | switch this laptop to Secondary |
| Esc | close |

Scan and export change nothing on the main laptop except the list file.

### On the second laptop

| Key | Does |
|-----|------|
| ↑ / ↓, PgUp / PgDn, Home / End | move |
| Space | tick or untick |
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

# Repo packages
[[packages]]
name = "rclone"
repo = "extra"

[[packages]]
name = "asusctl"
repo = "g14"
hardware = true

# AUR packages
[[aur]]
name = "orion-beta"

# Themes
[[themes]]
name = "sunset"
source = "https://github.com/someone/omarchy-sunset-theme.git"

[[themes]]
name = "handmade"
manual = true

# Plugins
[[plugins]]
id = "ninepointlabs.omasync"
name = "OmaSyncthing"
source = "https://github.com/ninepointlabs/omasync.git"
enabled = true
```

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
  auto-export), not in the shell's `shell.json`, so the helper works the same
  from a terminal.

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
```

Every external command (pacman, yay, git, flatpak, sudo, the omarchy commands,
the terminal) is a stub; nothing touches the network or your real config.

## License

MIT. See [LICENSE](LICENSE).
