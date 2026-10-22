# Liquid-Glass Hyprland Rice — Design

Date: 2026-10-09
Status: implemented 2026-10-09

## Goal

Restyle the whole Hyprland desktop into one cohesive "liquid glass" look —
translucent, heavily blurred surfaces with colors generated from the wallpaper —
and add the hypr.land plugins Hyprbars, Borders++, Hyprfocus,
hypr-dynamic-cursors, hyprspace and Hyprglass.

> Revision 2026-10-09: Hyprtrails was dropped. It was removed from `hyprwm/hyprland-plugins`
> in May 2026 ("drop unmaintained plugins") and has no fork that builds on 0.56.
>
> Revision 2026-10-09 (post-implementation): Borders++ removed at user request. It draws its
> extra border without the workspace-switch fade, so the outline lingered ~200 ms on the new
> (empty) workspace. No option controls this.

Success criteria:

- Hyprland starts cleanly with all plugins loaded (`hyprctl plugin list`) and no config errors (`hyprctl configerrors` empty).
- Changing the wallpaper (SUPER+W / SUPER+SHIFT+W) re-colors Hyprland borders, waybar, rofi, mako, hyprlock and kitty without a relogin.
- Every existing keybind and autostart still works (except the intended wofi → rofi and swaybg → awww swaps).
- Any single plugin can be disabled with `hyprpm disable <name>` without breaking the rest of the config.

## Constraints and context

- Hyprland 0.56.2 (Arch `extra`), NVIDIA GPU, laptop eDP-1 1920x1080 + optional HDMI-A-1.
- Stay on `hyprland.conf` (hyprlang). Migrating to the new Lua config is out of scope.
- Performance budget: max eye-candy (user is fine with GPU/battery cost).
- `monitors.conf` is owned by nwg-displays — do not edit.
- Not touched: env vars, existing keybind logic, display scripts, screenshot script. Duplicate `exec-once` lines (cliphist, gnome-keyring) are noted but left as-is.

## Architecture

One wallpaper script drives the palette:

```
wallpaper.sh <image|--random|--pick>
  ├─ awww img <image> --transition-type grow
  ├─ matugen image <image>   → writes generated color files from templates
  └─ reload: hyprctl reload, pkill -SIGUSR2 waybar, makoctl reload, kitty (SIGUSR1)
```

Hand-written configs import generated color files; generated files are never edited by hand.

### Files

```
~/.config/hypr/
  hyprland.conf          edited: source colors.conf, glass.conf, plugins.conf; new binds; swaps
  glass.conf             NEW   general/decoration/blur/shadow/animations/opacity rules/layerrules
  plugins.conf           NEW   hyprpm reload + per-plugin config
  colors.conf            GENERATED (gitignored)
  hyprlock.conf          restyled, sources colors.conf
  scripts/wallpaper.sh   NEW
  scripts/rofi-toggle.sh NEW   replaces wofi-toggle.sh (old file kept until verified, then removed)
~/.config/matugen/
  config.toml            NEW
  templates/             NEW   hypr-colors.conf, waybar-colors.css, rofi-colors.rasi, mako-config, kitty-colors.conf
~/.config/waybar/        config.jsonc + style.css restyled; imports generated colors.css
~/.config/rofi/          NEW   config.rasi + glass.rasi (+ wallpaper-grid.rasi)
~/.config/mako/config    GENERATED from template (mako has no include); existing rules carried into template
~/.config/kitty/kitty.conf  + background_opacity 0.75, include generated colors
~/Pictures/Wallpapers/   NEW   seeded with existing ~/Pictures/wallpaper.png
```

Before any edit, all touched configs are snapshotted to `~/.config/hypr/backup-2026-10-09/` (gitignored), in addition to git history for the hypr dir.

## Visual spec

Color roles below are matugen Material You roles (`primary`, `tertiary`, `surface`, `outline`, `error`, `primary_container`, ...).

### Windows (`glass.conf`)

- `rounding 14`, `gaps_in 6`, `gaps_out 12`, `border_size 2`.
- Opacity: active 0.90, inactive 0.80, fullscreen 1.0.
- Forced opaque (windowrule): browsers, mpv / video players, Steam and games, image viewers.
- Kitty: compositor opacity 1.0; transparency via `background_opacity 0.75` in kitty.conf so text stays crisp.
- Blur: size 8, passes 3, vibrancy 0.2, noise 0.02, brightness 0.9, popups on.
- Shadow: range 25, render_power 3, color from matugen `shadow` with alpha.
- Active border: gradient `primary` → `tertiary`, rotating via `borderangle` loop animation. Inactive: `outline` at ~40% alpha.

### Animations

- Springy overshoot bezier.
- Windows: popin 80%. Workspaces: horizontal slidefade (matches 3-finger swipe). Layers: fade + slide.
- `borderangle` looping (constant redraw accepted under max eye-candy).

### Layer rules

Blur + `ignore_alpha 0.3` on namespaces: waybar, rofi, notifications (mako), hyprspace panel.

### Plugins (`plugins.conf`)

Installed with `hyprpm` (package `hyprpm` from `extra`):

- Official repo `hyprwm/hyprland-plugins`: **hyprbars**, **borders-plus-plus**, **hyprfocus**.
- Community: **hyprspace**, **hypr-dynamic-cursors**, **Hyprglass**.

Autostart: `exec-once = hyprpm reload -n`. Add permission rule so hyprpm can load plugins without a prompt.

| Plugin | Config |
|---|---|
| hyprbars | Floating windows only; 28px glass bar, centered title, close + maximize buttons, colors from matugen |
| borders-plus-plus | One extra 1px outer border, `primary` at ~30% alpha (glow edge) |
| hyprfocus | Subtle shrink/flash on keyboard focus change only |
| hypr-dynamic-cursors | `tilt` mode + shake-to-enlarge |
| hyprspace | SUPER+Tab and 4-finger swipe up; glass workspace strip |
| Hyprglass | Refraction on floating windows + layers; tiled windows keep standard blur |

Exact option names for hyprbars' floating-only rule and Hyprglass settings must be taken from each plugin's README at the commit hyprpm builds — not guessed.

### Waybar — floating islands

Three detached pills, same modules as today:

- Left: `hyprland/workspaces`, `wlr/taskbar`
- Center: `clock` (click → calendar tooltip)
- Right: `cpu memory temperature disk │ pulseaudio network battery │ tray custom/power`

Style: pill background `surface` at ~0.45 alpha, radius 14, 1px `outline` border, margins aligned to `gaps_out 12`. Active workspace = wider `primary` pill with width transition; empty workspaces dimmed. Critical states (existing thresholds: battery critical 15%, temperature 80°C) use `error` and pulse. `custom/power` keeps its current action.

### Rofi (replaces wofi)

One shared glass theme: centered panel, radius 16, search bar with `primary` underline, selected row `primary_container`. Modes:

- drun with icons — SUPER tap (via `rofi-toggle.sh`, same toggle behavior as today)
- run — SUPER+R
- clipboard — SUPER+V (clipboard-toggle.sh switched to rofi)
- wallpaper picker — SUPER+SHIFT+W, thumbnail grid

### Mako

Glass: `surface` background at `cc` alpha, radius 14, 2px border. Border by urgency: low `tertiary`, normal `primary`, critical `error`. Keeps width/height/margins, top-right anchor, timeouts and the `[app-name=XAMPP]` rule.

### Hyprlock

Keeps the video background (`~/Videos/wallpaper_1080p.mp4`). Adds a centered glass card with large clock, date, and rounded input field with `primary` outline; fail color `error`. Colors from `colors.conf` (palette of the current still wallpaper).

## Keybinds (new / changed)

| Bind | Action |
|---|---|
| SUPER+Tab | hyprspace overview |
| 4-finger swipe up | hyprspace overview |
| SUPER+W | `wallpaper.sh --random` |
| SUPER+SHIFT+W | `wallpaper.sh --pick` (rofi grid) |
| SUPER tap | rofi drun (was wofi) |
| SUPER+R | `rofi -show run` (was wofi) |

All other binds unchanged.

## Packages

- `hyprpm` (extra)
- `matugen` (extra, 4.2.0)
- Already present: awww, rofi, waybar, mako, hyprlock, kitty, cmake, meson, cpio, gcc, git.

## Rollout order and verification

Each step is verified before the next. After each Hyprland-side change: `hyprctl reload` then `hyprctl configerrors` must be empty.

1. Snapshot configs → `backup-2026-10-09/`. Install packages.
2. matugen config + templates; `wallpaper.sh`; seed wallpaper; swap swaybg → awww. Verify: all generated files exist and colors.conf parses.
3. `glass.conf` (decoration, blur, opacity rules, animations, layerrules) + kitty opacity. Verify visually; check video/browser windows are opaque.
4. Plugins one at a time — hyprbars, borders-plus-plus, hyprfocus, then hyprspace, hypr-dynamic-cursors, Hyprglass. After each: `hyprctl plugin list` shows it, no crash, no config errors. A plugin that fails to build or crashes on 0.56.2 is disabled and reported, not forced.
5. Waybar islands. Verify all modules render, critical classes trigger.
6. Rofi theme + mode swaps. Verify each bind.
7. Mako template. Verify with `notify-send` at low/normal/critical.
8. Hyprlock. Verify by locking and unlocking (including a wrong password).
9. End-to-end: SUPER+W twice → every surface re-colors.

## Error handling / rollback

- Plugin crash on load: `hyprpm disable <name>` from a TTY, `hyprpm reload`.
- Broken config: `git checkout -- <file>` in `~/.config/hypr`, or restore from `backup-2026-10-09/` for files outside it.
- matugen failure in `wallpaper.sh`: wallpaper still changes; previous generated colors stay in place (script does not delete them first).

## Out of scope

- Lua config migration.
- Cleaning duplicate `exec-once` lines.
- Monitor layout, HyprPanel, GTK/Qt theme changes.
