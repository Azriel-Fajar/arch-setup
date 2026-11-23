# arch-setup

My Arch Linux + Hyprland setup: MacShell (quickshell) bar and dock, liquid glass
via a HyprGlass fork, matugen colors from the wallpaper, macOS-style SDDM theme.
One script turns a fresh Arch install into this desktop.

## Install

Start from a fresh [archinstall](https://wiki.archlinux.org/title/Archinstall)
system (user, network and bootloader set up), then:

```sh
sudo pacman -S --needed git
git clone https://github.com/Azriel-Fajar/arch-setup.git ~/arch-setup
cd ~/arch-setup
./install.sh
```

Pick modules (enter = all), confirm once, and it runs unattended. Configs are
**symlinked** into the clone, so keep it at `~/arch-setup`.

After it finishes, reboot, log into Hyprland, open a terminal and run:

```sh
~/arch-setup/install.sh plugins
```

## Modules

Run any of them on their own: `./install.sh rice dev`. All are safe to re-run.

| Module     | What it does |
| ---------- | ------------ |
| `packages` | Enables multilib, installs `packages/pacman.txt`, CPU microcode and GPU drivers (auto-detected Intel / AMD / NVIDIA), `yay`, `packages/aur.txt` and flatpaks |
| `rice`     | Links `hypr`, `macbar`, `macdock`, `matugen`, `rofi`, `kitty`, `wlogout`, `gtk-3.0`, `mako`, `environment.d`; clones the [MacShell fork](https://github.com/Azriel-Fajar/MacShell/tree/azriel); installs the Bibata hyprcursor and builds the [MacOS-Like](https://github.com/Scrimas/MacOS-Like) icon theme; makes a default wallpaper and generates colors |
| `system`   | User groups, zram, SDDM `macos` theme, enables NetworkManager, bluetooth, power-profiles-daemon, avahi, timesyncd, fstrim, sddm |
| `dev`      | Links `.bashrc`, `.bash_profile`, `.zshrc`, `.blerc`, starship, atuin, Thunar, `mimeapps.list`; npm globals into `~/.npm-global` (Claude Code etc.); sets git name/email |
| `plugins`  | From inside Hyprland only: hyprpm plugins (hyprbars, hyprfocus, Hyprspace, dynamic-cursors) and builds the [HyprGlass fork](https://github.com/Azriel-Fajar/hyprglass/tree/macshell), or [upstream HyprGlass](https://github.com/hyprnux/hyprglass) when the fork has no pin for your Hyprland. `plugins.lua` loads them all |

Existing configs are moved to `~/.config-backup-<date>/` before linking.

## Not included

- Wallpapers: put your own in `~/Pictures/Wallpapers` (a plain gradient is generated on first install)
- Monitor layout: a generic `monitor = , preferred, auto, 1` is written; set yours with `nwg-displays`
- Logins and app data (gh, Claude, browsers): run `gh auth login` etc. yourself
- Personal apps: the package lists hold only the desktop and a few essentials
  (Chrome, VS Code, kitty, Thunar, Claude Code). Install anything else yourself

## Caveats

- Hyprland is configured in Lua (`config/hypr/hyprland.lua`, `look.lua`, `plugins.lua`):
  0.57 dropped `hyprland.conf`, and 0.55/0.56 pick `hyprland.lua` over it. The old
  `hyprland.conf`, `glass.conf` and `plugins.conf` are no longer loaded. Scripts and MacShell
  drive Hyprland with Lua dispatchers (`hyprctl dispatch 'hl.dsp.…'`).
- Some configs assume user `azriel` with uid 1000 (`/home/azriel` in `hyprlock.conf`,
  `macbar`/`macdock` `settings.json`). The script warns if yours differ.
- The HyprGlass fork targets Hyprland 0.56.2. On a newer Hyprland, `./install.sh plugins`
  builds upstream HyprGlass instead (same glass, but no rim refraction). To get the fork
  back, rebase branch `macshell` onto upstream and add the pin to its `hyprpm.toml`.
- `hyprlock.conf` uses a video background at `~/Videos/wallpaper_1080p.mp4`.

## Updating the repo from this machine

```sh
./sync.sh        # copies current configs in, flags stale package entries, scans for secrets
git diff         # review
git commit -am "Sync" && git push
```

`packages/*.txt` are curated by hand. When the desktop starts depending on a new
package, add it there yourself; `sync.sh` does not copy every installed app.
