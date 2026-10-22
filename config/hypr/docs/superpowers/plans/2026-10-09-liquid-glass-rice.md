# Liquid-Glass Hyprland Rice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing Hyprland desktop into a cohesive liquid-glass theme whose colors come from the wallpaper, plus the hypr.land plugins Hyprbars, Borders++, Hyprfocus, hypr-dynamic-cursors, hyprspace and Hyprglass.

**Architecture:** `scripts/wallpaper.sh` sets the wallpaper with `awww`, then runs `matugen`, which renders color files from templates in `~/.config/matugen/templates/`. Then it reloads Hyprland, waybar, mako and kitty. Hand-written configs (`glass.conf`, `plugins.conf`, waybar `style.css`, rofi `glass.rasi`, `hyprlock.conf`) only import the generated color files. Plugins are built and loaded by `hyprpm`.

**Tech Stack:** Hyprland 0.56.2 (legacy hyprlang `hyprland.conf`), hyprpm 0.56.2, matugen 4.2.0, awww 0.12.1, waybar 0.15.0, rofi 2.0.0, mako 1.11.0, hyprlock 0.9.6, kitty 0.49.2.

**Spec:** `~/.config/hypr/docs/2026-10-09-liquid-glass-rice-design.md`

## Global Constraints

- Hyprland 0.56.2 loads `~/.config/hypr/hyprland.conf` as **legacy hyprlang** config. Do not create `hyprland.lua`. The current wiki (wiki.hypr.land) documents Lua only. For hyprlang syntax use the **0.54.0** wiki: `https://wiki.hypr.land/0.54.0/Configuring/...`.
- Window/layer rule syntax (0.53+ hyprlang): `windowrule = match:<prop> <value>, <effect> <value>` and `layerrule = match:namespace <regex>, <effect> <value>`. Booleans use `on`.
- Do not edit `monitors.conf` (owned by nwg-displays), env vars, display scripts, or `screenshot.sh`.
- Leave the duplicate `exec-once` lines (cliphist, gnome-keyring) as they are.
- Hyprtrails is **not** installed (removed upstream, see spec revision note).
- Performance budget: max eye-candy. The `borderangle` loop and Hyprglass GPU cost are accepted.
- Only `~/.config/hypr` is a git repo. Files outside it (waybar, rofi, mako, kitty, matugen) are protected only by the snapshot in `~/.config/hypr/backup-2026-10-09/`.
- `sudo` needs a password. The executor cannot run sudo steps. Steps marked **[USER]** are typed by Azriel at the Claude Code prompt as `! <command>`.
- Every Hyprland-side change ends with `hyprctl reload && hyprctl configerrors`. The expected output is empty.

## Review Focus

1. **Plugins not loaded at parse time.** This covers the first parse at login before `hyprpm reload`, and a Hyprland upgrade that breaks the hyprpm build. Expected: the desktop still starts with no error banner, and only plugin effects are missing. Test: Task 4 Step 6 disables all plugins and checks that `configerrors` is empty.
2. **Typos hidden by `# hyprlang noerror`.** The guard that fixes #1 also silences real typos in plugin options. Expected: every configured plugin option actually takes effect. Test: `hyprctl getoption` checks per plugin in Task 4 and Task 5.
3. **Wallpaper paths with spaces, parentheses or unicode.** Expected: the wallpaper is applied and the state file holds the exact path. Test: Task 2 Step 8.
4. **Wallpaper script called while `awww-daemon` is still starting (login race), or with nothing to pick.** This includes the picker cancelled with Esc, a missing file, and `--random` with only one image. Expected: wait for the daemon. Cancelling changes nothing. A missing file fails with a message and leaves colors untouched. Test: Task 2 Steps 8–9 and Task 7 Step 7.
5. **Video/browser/game windows made translucent or glassed.** Expected: they stay fully opaque, with no blur or glass behind them. Test: Task 3 Step 6.

---

### Task 1: Snapshot, packages, hyprpm headers

**Files:**
- Create: `~/.config/hypr/backup-2026-10-09/` (gitignored)

**Interfaces:**
- Consumes: nothing
- Produces: `matugen`, `hyprpm` on PATH; hyprpm headers built for 0.56.2

- [ ] **Step 1: Snapshot every config this plan touches**

```bash
B=~/.config/hypr/backup-2026-10-09
mkdir -p "$B"
cp -a ~/.config/hypr/hyprland.conf ~/.config/hypr/hyprlock.conf ~/.config/hypr/scripts "$B/"
cp -a ~/.config/waybar "$B/waybar"
cp -a ~/.config/mako "$B/mako"
cp -a ~/.config/kitty "$B/kitty"
ls "$B"
```

Expected: `hyprland.conf hyprlock.conf kitty mako scripts waybar`

- [ ] **Step 2: Verify the tools are missing (failing check)**

Run: `command -v matugen hyprpm`
Expected: no output, exit code 1.

- [ ] **Step 3: [USER] Install packages**

Ask Azriel to type:
```
! sudo pacman -S --needed hyprpm matugen
```

- [ ] **Step 4: Verify the install**

Run: `matugen --version; hyprpm -h | head -1; pacman -Q hyprpm matugen`
Expected: `matugen 4.2.0`, hyprpm usage line, `hyprpm 0.56.2-4`, `matugen 4.2.0-1`.

- [ ] **Step 5: [USER] Build hyprpm headers for the running Hyprland**

`hyprpm update` may ask for sudo, so Azriel runs it:
```
! hyprpm update
```
Expected: ends with headers installed/up to date for `0.56.2` and no error.

- [ ] **Step 6: Verify the headers**

Run: `hyprpm list`
Expected: exits 0 (an empty plugin list is fine). It must not print "headers outdated" or "headers missing".

No commit (nothing tracked changed).

---

### Task 2: Wallpaper pipeline: matugen templates, `wallpaper.sh`, swaybg → awww

**Files:**
- Create: `~/.config/matugen/config.toml`
- Create: `~/.config/matugen/templates/hypr-colors.conf`
- Create: `~/.config/matugen/templates/waybar-colors.css`
- Create: `~/.config/matugen/templates/rofi-colors.rasi`
- Create: `~/.config/matugen/templates/mako-config`
- Create: `~/.config/matugen/templates/kitty-colors.conf`
- Create: `~/.config/hypr/scripts/wallpaper.sh`
- Create: `~/Pictures/Wallpapers/wallpaper.png` (copy)
- Modify: `~/.config/hypr/hyprland.conf` (the `swaybg` exec-once line)

**Interfaces:**
- Consumes: `matugen`, `awww`, `awww-daemon`
- Produces:
  - `wallpaper.sh <image> | --random | --pick | --restore`. Exit 0 on success **and** on a cancelled pick. Exit 1 for a missing/invalid image, an awww failure or a matugen failure. Exit 2 for a usage error. State file: `~/.cache/current-wallpaper` (absolute path, one line).
  - `~/.config/hypr/colors.conf` hyprlang variables: `$primary $on_primary $primary_container $on_primary_container $tertiary $error $surface $on_surface $on_surface_variant $outline $primary_a $tertiary_a $outline_dim $primary_glow $shadow_a $bar_bg $glass_card $glass_tint`
  - `~/.config/waybar/colors.css` GTK colors: `@primary @on_primary @tertiary @error @surface @surface_container_high @on_surface @outline`
  - `~/.config/rofi/colors.rasi` vars: `primary primary-container on-primary-container on-surface on-surface-variant surface-glass surface-container-glass outline-glass`
  - `~/.config/mako/config` (complete mako config)
  - `~/.config/kitty/colors.conf` (kitty color settings)

- [ ] **Step 1: Write a failing check**

Run:
```bash
test -s ~/.config/hypr/colors.conf && grep -q '^\$primary = rgb([0-9a-f]\{6\})$' ~/.config/hypr/colors.conf && echo PASS || echo FAIL
```
Expected: `FAIL`

- [ ] **Step 2: Create matugen config**

`~/.config/matugen/config.toml`:
```toml
[config]
# Pick the most dominant color without the interactive chooser (script runs non-interactively)
source_color_index = 0

[config.wallpaper]
# wallpaper.sh sets the wallpaper itself with awww
set = false

[templates.hypr]
input_path = "./templates/hypr-colors.conf"
output_path = "~/.config/hypr/colors.conf"

[templates.waybar]
input_path = "./templates/waybar-colors.css"
output_path = "~/.config/waybar/colors.css"

[templates.rofi]
input_path = "./templates/rofi-colors.rasi"
output_path = "~/.config/rofi/colors.rasi"

[templates.mako]
input_path = "./templates/mako-config"
output_path = "~/.config/mako/config"

[templates.kitty]
input_path = "./templates/kitty-colors.conf"
output_path = "~/.config/kitty/colors.conf"
```

- [ ] **Step 3: Create the five templates**

`~/.config/matugen/templates/hypr-colors.conf`:
```
# Generated by matugen (template: ~/.config/matugen/templates/hypr-colors.conf). Do not edit.
$primary = rgb({{colors.primary.default.hex_stripped}})
$on_primary = rgb({{colors.on_primary.default.hex_stripped}})
$primary_container = rgb({{colors.primary_container.default.hex_stripped}})
$on_primary_container = rgb({{colors.on_primary_container.default.hex_stripped}})
$tertiary = rgb({{colors.tertiary.default.hex_stripped}})
$error = rgb({{colors.error.default.hex_stripped}})
$surface = rgb({{colors.surface.default.hex_stripped}})
$on_surface = rgb({{colors.on_surface.default.hex_stripped}})
$on_surface_variant = rgb({{colors.on_surface_variant.default.hex_stripped}})
$outline = rgb({{colors.outline.default.hex_stripped}})

# Alpha variants
$primary_a = rgba({{colors.primary.default.hex_stripped}}ee)
$tertiary_a = rgba({{colors.tertiary.default.hex_stripped}}ee)
$outline_dim = rgba({{colors.outline.default.hex_stripped}}66)
$primary_glow = rgba({{colors.primary.default.hex_stripped}}4d)
$shadow_a = rgba({{colors.shadow.default.hex_stripped}}99)
$bar_bg = rgba({{colors.surface.default.hex_stripped}}73)
$glass_card = rgba({{colors.surface.default.hex_stripped}}8c)
$glass_tint = 0x{{colors.primary.default.hex_stripped}}1a
```

`~/.config/matugen/templates/waybar-colors.css`:
```css
/* Generated by matugen (template: ~/.config/matugen/templates/waybar-colors.css). Do not edit. */
@define-color primary {{colors.primary.default.hex}};
@define-color on_primary {{colors.on_primary.default.hex}};
@define-color tertiary {{colors.tertiary.default.hex}};
@define-color error {{colors.error.default.hex}};
@define-color surface {{colors.surface.default.hex}};
@define-color surface_container_high {{colors.surface_container_high.default.hex}};
@define-color on_surface {{colors.on_surface.default.hex}};
@define-color outline {{colors.outline.default.hex}};
```

`~/.config/matugen/templates/rofi-colors.rasi`:
```
/* Generated by matugen (template: ~/.config/matugen/templates/rofi-colors.rasi). Do not edit. */
* {
    primary:                 {{colors.primary.default.hex}};
    primary-container:       {{colors.primary_container.default.hex}};
    on-primary-container:    {{colors.on_primary_container.default.hex}};
    on-surface:              {{colors.on_surface.default.hex}};
    on-surface-variant:      {{colors.on_surface_variant.default.hex}};
    surface-glass:           {{colors.surface.default.hex}}b3;
    surface-container-glass: {{colors.surface_container_high.default.hex}}99;
    outline-glass:           {{colors.outline.default.hex}}66;
}
```

`~/.config/matugen/templates/mako-config` (carries over every existing setting and rule from the current `~/.config/mako/config`):
```
# Generated by matugen (template: ~/.config/matugen/templates/mako-config). Edit the template, not this file.
width=320
height=100
margin=12
padding=16
border-size=2
border-radius=14
anchor=top-right
default-timeout=3000
font=JetBrains Mono 11
background-color={{colors.surface.default.hex}}cc
border-color={{colors.primary.default.hex}}
text-color={{colors.on_surface.default.hex}}
progress-color=over {{colors.primary_container.default.hex}}

[urgency=low]
border-color={{colors.tertiary.default.hex}}
default-timeout=2000

[urgency=normal]
border-color={{colors.primary.default.hex}}
default-timeout=3000

[urgency=critical]
border-color={{colors.error.default.hex}}
text-color={{colors.error.default.hex}}
default-timeout=0

[app-name=XAMPP]
border-color={{colors.tertiary.default.hex}}
border-size=2
default-timeout=3000
```

`~/.config/matugen/templates/kitty-colors.conf`:
```
# Generated by matugen (template: ~/.config/matugen/templates/kitty-colors.conf). Do not edit.
foreground {{colors.on_surface.default.hex}}
background {{colors.surface.default.hex}}
cursor {{colors.primary.default.hex}}
selection_foreground {{colors.on_primary_container.default.hex}}
selection_background {{colors.primary_container.default.hex}}
url_color {{colors.tertiary.default.hex}}
active_border_color {{colors.primary.default.hex}}
inactive_border_color {{colors.outline.default.hex}}
```

Create the output dirs that may not exist: `mkdir -p ~/.config/rofi ~/.config/kitty`

- [ ] **Step 4: Seed the wallpaper folder**

```bash
mkdir -p ~/Pictures/Wallpapers
cp -n ~/Pictures/wallpaper.png ~/Pictures/Wallpapers/wallpaper.png
```

- [ ] **Step 5: Render templates once by hand and check the output**

Run:
```bash
timeout 30 matugen image ~/Pictures/Wallpapers/wallpaper.png -m dark </dev/null; echo "exit=$?"
grep -l '{{' ~/.config/hypr/colors.conf ~/.config/waybar/colors.css ~/.config/rofi/colors.rasi ~/.config/mako/config ~/.config/kitty/colors.conf; echo "unrendered=$?"
grep -c 'rgb(\|rgba(' ~/.config/hypr/colors.conf
```
Expected: `exit=0`, `unrendered=1` (grep found no leftover `{{`), and `17`.
If `exit=124`: matugen is waiting on its interactive color chooser. Check that `source_color_index` is under `[config]` and retry.
If a field such as `hex_stripped` is reported unknown: run `matugen image <img> -m dark --show-colors` and the matugen docs (`https://iniox.github.io/#matugen`) to find the 4.2 field name. Fix all templates the same way.

Then run the Step 1 check again. Expected: `PASS`

- [ ] **Step 6: Write `wallpaper.sh`**

`~/.config/hypr/scripts/wallpaper.sh`:
```bash
#!/usr/bin/env bash
# Set the wallpaper with awww, regenerate matugen colors, reload themed apps.
# Usage: wallpaper.sh <image> | --random | --pick | --restore
set -uo pipefail

WALL_DIR="$HOME/Pictures/Wallpapers"
STATE="${XDG_CACHE_HOME:-$HOME/.cache}/current-wallpaper"

list_walls() {
    find "$WALL_DIR" -maxdepth 1 -type f \
        \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) | sort
}

pick_wall() {
    list_walls | while IFS= read -r f; do
        printf '%s\0icon\x1f%s\n' "$(basename "$f")" "$f"
    done | rofi -dmenu -i -show-icons -p "Wallpaper" -theme ~/.config/rofi/wallpaper-grid.rasi
}

current=$(cat "$STATE" 2>/dev/null || true)

case "${1:-}" in
    --random)
        img=$(list_walls | grep -vxF -- "$current" | shuf -n1)
        [ -n "$img" ] || img=$current ;;
    --pick)
        name=$(pick_wall) || exit 0   # Esc / cancel: change nothing
        [ -n "$name" ] || exit 0
        img="$WALL_DIR/$name" ;;
    --restore)
        img=${current:-$WALL_DIR/wallpaper.png} ;;
    "" | -h | --help)
        echo "Usage: $(basename "$0") <image> | --random | --pick | --restore" >&2
        exit 2 ;;
    *)
        img=$1 ;;
esac

if [ -z "$img" ] || [ ! -f "$img" ]; then
    echo "wallpaper.sh: no such image: '$img'" >&2
    exit 1
fi
img=$(realpath -- "$img")

# awww-daemon may still be starting (login)
for _ in $(seq 50); do
    awww query >/dev/null 2>&1 && break
    sleep 0.1
done

if ! awww img "$img" --transition-type grow --transition-duration 1.2 --transition-fps 60; then
    echo "wallpaper.sh: awww could not set '$img'" >&2
    exit 1
fi
printf '%s\n' "$img" > "$STATE"

# On failure the previously generated color files stay in place
if ! timeout 30 matugen image "$img" -m dark </dev/null >/dev/null; then
    notify-send -u critical "wallpaper.sh" "matugen failed, keeping previous colors"
    exit 1
fi

hyprctl reload >/dev/null
pkill -SIGUSR2 -x waybar || true
makoctl reload || true
pkill -SIGUSR1 -x kitty || true
```

Run: `chmod +x ~/.config/hypr/scripts/wallpaper.sh`

- [ ] **Step 7: Swap swaybg for awww in `hyprland.conf`**

Replace:
```
exec-once = swaybg -i /home/azriel/Pictures/wallpaper.png -m fill
```
with:
```
exec-once = awww-daemon
exec-once = ~/.config/hypr/scripts/wallpaper.sh --restore
```
Apply now without relogging:
```bash
pkill -x swaybg; hyprctl dispatch exec awww-daemon
```

- [ ] **Step 8: Test the main paths and edge cases**

```bash
W=~/.config/hypr/scripts/wallpaper.sh
S=/tmp/claude-1000/-home-azriel--config-hypr/d1cb5fe5-5a6a-4662-b9e9-2485388f1bde/scratchpad
# usage
$W; echo "usage exit=$?"                                   # expect 2
# missing file: exit 1, colors untouched
sum1=$(md5sum < ~/.config/hypr/colors.conf)
$W /nonexistent.png; echo "missing exit=$?"                # expect 1
[ "$(md5sum < ~/.config/hypr/colors.conf)" = "$sum1" ] && echo "colors untouched OK"
# non-image file: awww fails, exit 1, colors untouched
$W ~/.config/hypr/hyprland.conf; echo "nonimage exit=$?"   # expect 1
[ "$(md5sum < ~/.config/hypr/colors.conf)" = "$sum1" ] && echo "colors untouched OK"
# path with spaces/parens
cp ~/Pictures/Wallpapers/wallpaper.png "$S/my wall (1).png"
$W "$S/my wall (1).png"; echo "spaces exit=$?"             # expect 0
cat ~/.cache/current-wallpaper                              # expect .../scratchpad/my wall (1).png
# --random with one wallpaper falls back to current
$W ~/Pictures/Wallpapers/wallpaper.png
$W --random; echo "random exit=$?"                          # expect 0
cat ~/.cache/current-wallpaper                              # expect /home/azriel/Pictures/Wallpapers/wallpaper.png
```
Expected: as commented. Also confirm by eye that the wallpaper changed with a grow transition.

- [ ] **Step 9: Test the login race (daemon not yet up)**

```bash
pkill -x awww-daemon
hyprctl dispatch exec awww-daemon; ~/.config/hypr/scripts/wallpaper.sh --restore; echo "restore exit=$?"
```
Expected: `restore exit=0` and the wallpaper is visible.

- [ ] **Step 10: Reload Hyprland and check for errors**

Run: `hyprctl reload && hyprctl configerrors`
Expected: empty output.

- [ ] **Step 11: Commit**

```bash
cd ~/.config/hypr && git add hyprland.conf scripts/wallpaper.sh && git commit -m "Add matugen wallpaper pipeline, swap swaybg for awww

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Glass look: `glass.conf`, opacity rules, kitty

**Files:**
- Create: `~/.config/hypr/glass.conf`
- Create: `~/.config/kitty/kitty.conf`
- Modify: `~/.config/hypr/hyprland.conf` (add `source` lines; remove the `animations`, `general` and `decoration` blocks, which move to glass.conf)

**Interfaces:**
- Consumes: `colors.conf` variables `$primary_a $tertiary_a $outline_dim $shadow_a` (Task 2)
- Produces: bezier names `glass`, `overshot`, `linear` (used by Task 4's hyprfocus animations)

- [ ] **Step 1: Failing check**

Run: `hyprctl getoption decoration:rounding | head -1; hyprctl getoption decoration:blur:passes | head -1`
Expected (current): `int: 8` and `int: 1`. The target is 14 and 3.

- [ ] **Step 2: Create `glass.conf`**

`~/.config/hypr/glass.conf`:
```
# Liquid-glass look. Colors come from colors.conf (generated by matugen via scripts/wallpaper.sh).

general {
    gaps_in = 6
    gaps_out = 12
    border_size = 2
    col.active_border = $primary_a $tertiary_a 45deg
    col.inactive_border = $outline_dim
    layout = dwindle
}

decoration {
    rounding = 14
    active_opacity = 0.90
    inactive_opacity = 0.80
    fullscreen_opacity = 1.0

    blur {
        enabled = true
        size = 8
        passes = 3
        noise = 0.02
        brightness = 0.9
        vibrancy = 0.2
        popups = true
    }

    shadow {
        enabled = true
        range = 25
        render_power = 3
        color = $shadow_a
    }
}

animations {
    enabled = true
    bezier = glass, 0.22, 1, 0.36, 1
    bezier = overshot, 0.05, 0.9, 0.1, 1.1
    bezier = linear, 0, 0, 1, 1
    animation = windows, 1, 5, overshot, popin 80%
    animation = windowsOut, 1, 4, glass, popin 80%
    animation = border, 1, 8, glass
    animation = borderangle, 1, 100, linear, loop
    animation = fade, 1, 4, glass
    animation = layers, 1, 4, glass, slide
    animation = workspaces, 1, 5, glass, slidefade 15%
}

# Stay fully opaque: browsers, media, games, image viewers
windowrule = match:class ^(firefox|google-chrome|chromium|brave-browser|mpv|vlc|imv|org.gnome.Loupe|steam)$, opaque on
windowrule = match:class ^(steam_app_.*)$, opaque on
windowrule = match:content 2, opaque on
windowrule = match:content 3, opaque on
# Kitty handles its own transparency (background_opacity in kitty.conf) so text stays crisp
windowrule = match:class ^(kitty)$, opaque on

# Blur behind bar, launcher and notifications
layerrule = match:namespace ^(waybar|rofi|notifications)$, blur on
layerrule = match:namespace ^(waybar|rofi|notifications)$, ignore_alpha 0.3
```

- [ ] **Step 3: Edit `hyprland.conf`**

After the line `source = ~/.config/hypr/monitors.conf`, add:
```
source = ~/.config/hypr/colors.conf
source = ~/.config/hypr/glass.conf
```

Delete these three blocks entirely (glass.conf now owns them):
```
animations {
    enabled = true
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = fade, 1, 3, myBezier
    animation = fadeIn, 1, 3, myBezier
    animation = workspaces, 1, 3, myBezier, slidefade 8%
    animation = layers, 1, 2, myBezier, fade
    animation = windows, 1, 3, myBezier, popin 90%
}
```
```
# General
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(33ccffee)
    col.inactive_border = rgba(595959aa)
    layout = dwindle
}
```
```
# Decoration
decoration {
    rounding = 8
    blur {
        enabled = true
        size = 3
        passes = 1
    }
}
```

- [ ] **Step 4: Create `kitty.conf`**

`~/.config/kitty/kitty.conf`:
```
include colors.conf
background_opacity 0.75
```

Run: `kitty --debug-config 2>&1 | grep -E '^(background_opacity|background) '`
Expected: `background_opacity 0.75` and a `background #xxxxxx` line matching `~/.config/kitty/colors.conf`.

- [ ] **Step 5: Reload and verify**

Run:
```bash
hyprctl reload && hyprctl configerrors
hyprctl getoption decoration:rounding | head -1
hyprctl getoption decoration:blur:passes | head -1
hyprctl getoption decoration:active_opacity | head -1
```
Expected: no config errors, `int: 14`, `int: 3`, `float: 0.900000`.

- [ ] **Step 6: Verify opaque exceptions (Review Focus #5)**

Open firefox (or any listed browser) and a kitty window. Run:
```bash
hyprctl clients -j | python3 -c 'import json,sys; [print(c["class"], c.get("tags")) for c in json.load(sys.stdin)]'
```
Then look: the browser must be fully opaque when focused and unfocused. Kitty's background is translucent but its text is solid. Play a video in mpv if installed. It must be opaque.

- [ ] **Step 7: Commit**

```bash
cd ~/.config/hypr && git add glass.conf hyprland.conf && git commit -m "Add liquid-glass decoration, animations and opacity rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Official plugins: hyprbars, borders-plus-plus, hyprfocus

**Files:**
- Create: `~/.config/hypr/plugins.conf`
- Modify: `~/.config/hypr/hyprland.conf` (append `source = ~/.config/hypr/plugins.conf` as the last line)

**Interfaces:**
- Consumes: `$mod` (hyprland.conf), colors vars (Task 2), bezier `overshot` (Task 3)
- Produces: `plugins.conf` with a `# hyprlang noerror true` … `# hyprlang noerror false` guarded region. Task 5 adds its sections **inside** that region.

- [ ] **Step 1: Failing check**

Run: `hyprctl plugin list`
Expected: no plugins loaded.

- [ ] **Step 2: Add the official repo and enable the plugins one at a time**

```bash
hyprpm add https://github.com/hyprwm/hyprland-plugins
hyprpm enable hyprbars && hyprpm reload -n && hyprctl plugin list
```
Expected: hyprbars listed, a green "Initialized successfully" notification, and no crash. If the build fails or Hyprland crashes: from a TTY run `hyprpm disable hyprbars`, record the error, and continue with the next plugin.

```bash
hyprpm enable borders-plus-plus && hyprpm reload -n && hyprctl plugin list
hyprpm enable hyprfocus && hyprpm reload -n && hyprctl plugin list
```
Expected: each plugin appears and nothing crashes.

- [ ] **Step 3: Create `plugins.conf`**

`~/.config/hypr/plugins.conf`:
```
# Plugins are built and enabled with hyprpm (see docs/). This loads the enabled ones,
# then reloads so the guarded options below are applied with the plugins present.
permission = /usr/(bin|local/bin)/hyprpm, plugin, allow
exec-once = hyprpm reload -n && hyprctl reload

# Plugin options/rules/dispatchers are unknown until hyprpm has loaded the plugins
# (first parse at login, or a plugin that failed to build). Don't raise errors for them.
# hyprlang noerror true

plugin {
    hyprbars {
        enabled = true
        bar_height = 28
        bar_color = $bar_bg
        col.text = $on_surface
        bar_blur = true
        bar_text_font = JetBrainsMono Nerd Font
        bar_text_size = 10
        bar_text_align = center
        bar_part_of_window = true
        bar_precedence_over_border = true
        bar_padding = 10
        bar_button_padding = 8
        icon_on_hover = true
        inactive_button_color = $outline_dim
        on_double_click = hyprctl dispatch fullscreen 1
        # buttons are listed right to left: bgcolor, size, icon, on-click, fgcolor
        hyprbars-button = $error, 13, 󰖭, hyprctl dispatch killactive, $surface
        hyprbars-button = $tertiary, 13, 󰖯, hyprctl dispatch fullscreen 1, $surface
    }

    borders-plus-plus {
        add_borders = 1
        col.border_1 = $primary_glow
        border_size_1 = 1
        natural_rounding = yes
    }

    hyprfocus {
        enable = true
        keyboard_focus_animation = shrink
        mouse_focus_animation = none
        shrink_percentage = 0.97
    }
}

# Title bars on floating windows only
windowrule {
    name = hyprbars-floating-only
    match:float = false
    hyprbars:no_bar = on
}

animation = hyprfocusIn, 1, 1.7, overshot
animation = hyprfocusOut, 1, 1.7, overshot

# hyprlang noerror false
```

Append to the end of `hyprland.conf`:
```
source = ~/.config/hypr/plugins.conf
```

- [ ] **Step 4: Reload and verify each option took effect (Review Focus #2)**

```bash
hyprctl reload && hyprctl configerrors
hyprctl getoption plugin:hyprbars:bar_height | head -1          # int: 28
hyprctl getoption plugin:borders-plus-plus:add_borders | head -1 # int: 1
hyprctl getoption plugin:hyprfocus:keyboard_focus_animation | head -1  # str: shrink
```
Expected: no config errors and the values in the comments. A default value means a typo hidden by `noerror`. Fix it.

- [ ] **Step 5: Visual check**

- Open kitty (tiled): **no** title bar, and a faint 1px primary glow outside the border.
- `SUPER+T` to float it: a 28px glass title bar appears with close/max buttons (icons on hover). Click max, then close.
- Move focus with `SUPER+arrows`: a subtle shrink pulse. Moving the mouse gives no pulse.

- [ ] **Step 6: Plugins-absent check (Review Focus #1)**

```bash
hyprpm disable hyprbars; hyprpm disable borders-plus-plus; hyprpm disable hyprfocus
hyprpm reload -n; hyprctl reload; hyprctl configerrors; echo "---"
hyprpm enable hyprbars; hyprpm enable borders-plus-plus; hyprpm enable hyprfocus
hyprpm reload -n; hyprctl reload; hyprctl plugin list
```
Expected: empty output before `---` (no error banner without the plugins), then all three listed again.

- [ ] **Step 7: Commit**

```bash
cd ~/.config/hypr && git add plugins.conf hyprland.conf && git commit -m "Add hyprbars, borders-plus-plus and hyprfocus via hyprpm

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Community plugins: hyprspace, dynamic-cursors, Hyprglass

**Files:**
- Modify: `~/.config/hypr/plugins.conf` (add sections inside the `noerror` region, plus binds)

**Interfaces:**
- Consumes: `plugins.conf` guarded region (Task 4), colors vars (Task 2)
- Produces: `SUPER+Tab` → `overview:toggle`; 4-finger swipe up → `overview:toggle`

Install **one plugin per step**. If a plugin fails to build or crashes Hyprland, `hyprpm disable <name>` from a TTY, record the error, apply that step's fallback, and move on.

- [ ] **Step 1: hyprspace: install**

```bash
hyprpm add https://github.com/KZDKM/Hyprspace
hyprpm enable Hyprspace && hyprpm reload -n && hyprctl plugin list
```
Expected: Hyprspace listed. Hyprspace has no hyprpm pin for 0.56.2, so this builds its latest `main`.
**Fallback if the build fails or it crashes:** `hyprpm remove https://github.com/KZDKM/Hyprspace`, then `hyprpm add https://github.com/sandwichfarm/hyprexpo && hyprpm enable hyprexpo`. Use `hyprexpo:expo toggle` instead of `overview:toggle` in Step 2, and tell Azriel about the swap.

- [ ] **Step 2: hyprspace: config and binds**

Inside the `plugin { }` block of `plugins.conf`, after `hyprfocus { ... }`, add:
```
    overview {
        panelColor = $bar_bg
        panelBorderColor = $outline_dim
        panelBorderWidth = 1
        panelHeight = 180
        workspaceActiveBorder = $primary
        workspaceInactiveBorder = $outline_dim
        workspaceBorderSize = 2
        centerAligned = true
        onBottom = false
        showNewWorkspace = true
        showEmptyWorkspace = true
        exitOnClick = true
        switchOnDrop = true
        # gesture is bound explicitly below (4 fingers); keep 3-finger workspace swipe untouched
        disableGestures = true
    }
```
Directly above the `# hyprlang noerror false` line, add:
```
bind = $mod, Tab, overview:toggle
gesture = 4, up, dispatcher, overview:toggle
```

Verify:
```bash
hyprctl reload && hyprctl configerrors
hyprctl getoption plugin:overview:panelHeight | head -1   # int: 180
```
Then press `SUPER+Tab`: a glass workspace strip appears on top. Click a workspace to switch. Esc closes it. 4-finger swipe up toggles it. 3-finger horizontal swipe still switches workspaces.

- [ ] **Step 3: dynamic-cursors: install, config, verify**

```bash
hyprpm add https://github.com/virtcode/hypr-dynamic-cursors
hyprpm enable dynamic-cursors && hyprpm reload -n && hyprctl plugin list
```
Inside `plugin { }` add:
```
    dynamic-cursors {
        enabled = true
        mode = tilt
        tilt {
            limit = 5000
            activation = negative_quadratic
        }
        shake {
            enabled = true
        }
    }
```
Verify:
```bash
hyprctl reload && hyprctl configerrors
hyprctl getoption plugin:dynamic-cursors:mode | head -1   # str: tilt
```
Fast horizontal mouse moves tilt the cursor, and shaking enlarges it. (`cursor:no_hardware_cursors = true` is already set, which this plugin needs on NVIDIA.)
**Fallback:** `hyprpm disable dynamic-cursors` and delete the section.

- [ ] **Step 4: Hyprglass: install**

```bash
hyprpm add https://github.com/hyprnux/hyprglass
hyprpm enable hyprglass && hyprpm reload -n && hyprctl plugin list
```
Expected: hyprglass `0.9.1` listed (its pin for 0.56.2).
**If the build fails ("not recognized as a release"):**
```bash
hyprpm remove https://github.com/hyprnux/hyprglass
hyprpm add https://github.com/hyprnux/hyprglass origin/hyprland-0.56
hyprpm enable hyprglass && hyprpm reload -n
```

- [ ] **Step 5: Hyprglass: config**

Inside `plugin { }` add:
```
    hyprglass {
        default_theme = dark
        default_preset = pomme
        tint_color = $glass_tint
        layers {
            enabled = 1
            namespaces = waybar, rofi, notifications
        }
    }
```
After the `hyprbars-floating-only` windowrule add:
```
# Liquid glass on floating windows and layers only; tiled windows keep Hyprland's blur (readability)
windowrule = match:float false, tag +hyprglass_disabled
```

- [ ] **Step 6: Hyprglass: verify**

```bash
hyprctl reload && hyprctl configerrors
hyprctl getoption plugin:hyprglass:default_preset | head -1   # str: pomme
hyprctl hyprglass stats | head -5
```
Expected: `windows: on` and `layers: on`. `layers: hook missing` is acceptable but must be reported to Azriel.
Visual: tiled kitty has normal blur and no refraction. Float it (`SUPER+T`): refraction/specular edges appear. Then check the tag follows the float state:
```bash
hyprctl activewindow -j | python3 -c 'import json,sys; w=json.load(sys.stdin); print(w["floating"], w["tags"])'
```
Expected: `False ['hyprglass_disabled*']` when tiled and `True []` when floating. The `*` suffix marks a rule-applied tag. If the tag stays after floating, report it. Rule-applied tags might not be removed dynamically in this version.
Also check that the browser/mpv opaque windows from Task 3 show no glass.

- [ ] **Step 7: Commit**

```bash
cd ~/.config/hypr && git add plugins.conf && git commit -m "Add hyprspace, dynamic-cursors and hyprglass

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Waybar floating islands

**Files:**
- Modify: `~/.config/waybar/config.jsonc` (top-level `height`, `margin-top`, `margin-left`, `margin-right` only)
- Modify (rewrite): `~/.config/waybar/style.css`

**Interfaces:**
- Consumes: `~/.config/waybar/colors.css` (`@primary @on_primary @tertiary @error @surface @surface_container_high @on_surface @outline`)
- Produces: nothing new

- [ ] **Step 1: Failing check**

Run: `grep -c 'colors.css' ~/.config/waybar/style.css`
Expected: `0`

- [ ] **Step 2: Edit `config.jsonc` geometry**

Replace:
```
      "height": 35,
      "margin-top": 8,
      "margin-left": 10,
      "margin-right": 10,
```
with:
```
      "height": 34,
      "margin-top": 12,
      "margin-left": 12,
      "margin-right": 12,
```
Leave every module and setting as it is.

- [ ] **Step 3: Rewrite `style.css`**

`~/.config/waybar/style.css`:
```css
@import "colors.css";

* {
  font-family: "JetBrainsMono Nerd Font";
  font-size: 13px;
  border: none;
  border-radius: 0;
  min-height: 0;
  margin: 0;
}

window#waybar {
  background: transparent;
}

/* Three floating glass islands; Hyprland blurs behind them (layerrule + hyprglass) */
.modules-left,
.modules-center,
.modules-right {
  background: alpha(@surface, 0.45);
  border: 1px solid alpha(@outline, 0.5);
  border-radius: 14px;
  padding: 3px 8px;
}

#workspaces button {
  padding: 0 8px;
  margin: 2px;
  color: alpha(@on_surface, 0.6);
  background: transparent;
  border-radius: 10px;
  transition: all 0.25s cubic-bezier(0.22, 1, 0.36, 1);
}

#workspaces button.empty {
  color: alpha(@on_surface, 0.3);
}

#workspaces button.active {
  padding: 0 18px;
  color: @on_primary;
  background: @primary;
}

#workspaces button:hover {
  color: @on_surface;
  background: alpha(@primary, 0.18);
}

#workspaces button.urgent {
  color: @surface;
  background: @error;
}

#taskbar {
  margin-left: 6px;
  padding-left: 6px;
  border-left: 1px solid alpha(@outline, 0.4);
}

#taskbar button {
  padding: 0 6px;
  margin: 2px;
  border-radius: 10px;
  background: transparent;
  transition: background 0.2s;
}

#taskbar button:hover {
  background: alpha(@on_surface, 0.1);
}

#taskbar button.active {
  background: alpha(@primary, 0.25);
}

#taskbar button.minimized {
  opacity: 0.45;
}

#clock {
  color: @on_surface;
  font-weight: bold;
  padding: 0 8px;
}

#cpu,
#memory,
#temperature,
#disk,
#pulseaudio,
#network,
#battery,
#tray,
#custom-power {
  padding: 0 7px;
  color: @on_surface;
  border-radius: 10px;
  transition: background 0.2s, color 0.2s;
}

#cpu:hover,
#memory:hover,
#temperature:hover,
#disk:hover,
#pulseaudio:hover,
#network:hover,
#battery:hover {
  background: alpha(@primary, 0.15);
}

/* Group separators: system | audio, network, battery | tray, power */
#pulseaudio,
#tray {
  margin-left: 6px;
  padding-left: 10px;
  border-left: 1px solid alpha(@outline, 0.4);
  border-radius: 0 10px 10px 0;
}

#network,
#battery.charging,
#battery.warning:not(.charging) {
  color: @tertiary;
}

#temperature.critical,
#pulseaudio.muted,
#network.disconnected,
#battery.critical:not(.charging) {
  color: @error;
}

#temperature.critical,
#battery.critical:not(.charging) {
  animation: pulse 1.2s ease-in-out infinite alternate;
}

@keyframes pulse {
  to {
    background: alpha(@error, 0.25);
  }
}

#custom-power {
  color: @error;
  font-size: 15px;
  padding: 0 9px;
}

#custom-power:hover {
  background: alpha(@error, 0.2);
}

tooltip {
  background: alpha(@surface_container_high, 0.92);
  border: 1px solid alpha(@outline, 0.5);
  border-radius: 12px;
}

tooltip label {
  color: @on_surface;
}
```

- [ ] **Step 4: Restart waybar and check for CSS/config errors**

```bash
pkill -x waybar
timeout 4 waybar 2>&1 | grep -iE 'error|warning|unknown' ; echo "grep-exit=$?"
hyprctl dispatch exec waybar
```
Expected: `grep-exit=1` (no errors/warnings), then waybar comes back.

- [ ] **Step 5: Visual check**

Three separate glass pills, 12px from the top/left/right edges. The active workspace is a wide primary pill that animates when switching. Empty workspaces are dim. Separators sit before audio and before the tray. Hovering the calendar shows a glass tooltip. The power button still opens wlogout.
Critical styling: `notify-send` doesn't apply. Instead, temporarily set `"critical": 101` under `battery.states` in config.jsonc, run `pkill -SIGUSR2 waybar`, confirm the battery turns `error`-colored and pulses, then revert to `15` and run `pkill -SIGUSR2 waybar` again.

- [ ] **Step 6: Re-color check**

Run: `~/.config/hypr/scripts/wallpaper.sh ~/Pictures/Wallpapers/wallpaper.png`
Expected: the bar keeps its styling and has no unstyled flash.

No git commit (outside repo). Backup: `~/.config/hypr/backup-2026-10-09/waybar/`.

---

### Task 7: Rofi glass theme, replacing wofi

**Files:**
- Create: `~/.config/rofi/config.rasi`
- Create: `~/.config/rofi/glass.rasi`
- Create: `~/.config/rofi/wallpaper-grid.rasi`
- Create: `~/.config/hypr/scripts/rofi-toggle.sh`
- Modify: `~/.config/hypr/scripts/clipboard-toggle.sh`
- Modify: `~/.config/hypr/hyprland.conf` (`$menu`, SUPER tap bind, SUPER+R bind, new SUPER+W / SUPER+SHIFT+W binds)

**Interfaces:**
- Consumes: `~/.config/rofi/colors.rasi` (Task 2), `wallpaper.sh --random|--pick` (Task 2, which already references `~/.config/rofi/wallpaper-grid.rasi`)
- Produces: `rofi-toggle.sh` (no args; toggles `rofi -show drun`)

- [ ] **Step 1: Failing check**

Run: `rofi -theme ~/.config/rofi/wallpaper-grid.rasi -dump-theme >/dev/null 2>&1; echo "exit=$?"`
Expected: non-zero (the theme doesn't exist yet).

- [ ] **Step 2: Create the theme files**

`~/.config/rofi/config.rasi`:
```
configuration {
    modi: "drun,run";
    show-icons: true;
    icon-theme: "Papirus-Dark";
    drun-display-format: "{name}";
    font: "JetBrainsMono Nerd Font 12";
}

@theme "~/.config/rofi/glass.rasi"
```

`~/.config/rofi/glass.rasi`:
```
@import "~/.config/rofi/colors.rasi"

* {
    background-color: transparent;
    text-color: @on-surface;
    font: "JetBrainsMono Nerd Font 12";
}

window {
    location: center;
    anchor: center;
    width: 640px;
    padding: 16px;
    border: 1px;
    border-color: @outline-glass;
    border-radius: 16px;
    background-color: @surface-glass;
}

mainbox {
    spacing: 12px;
    children: [ inputbar, listview ];
}

inputbar {
    children: [ prompt, entry ];
    spacing: 10px;
    padding: 10px 14px;
    border: 0 0 2px 0;
    border-color: @primary;
    border-radius: 10px;
    background-color: @surface-container-glass;
}

prompt {
    text-color: @primary;
}

entry {
    placeholder: "Search…";
    placeholder-color: @on-surface-variant;
    cursor: text;
}

listview {
    lines: 8;
    columns: 1;
    spacing: 4px;
    fixed-height: true;
    scrollbar: false;
}

element {
    padding: 8px 12px;
    spacing: 12px;
    border-radius: 10px;
}

element selected.normal {
    background-color: @primary-container;
    text-color: @on-primary-container;
}

element-icon {
    size: 24px;
}

element-text {
    text-color: inherit;
    vertical-align: 0.5;
}
```

`~/.config/rofi/wallpaper-grid.rasi`:
```
@import "~/.config/rofi/glass.rasi"

window {
    width: 960px;
}

listview {
    columns: 4;
    lines: 2;
    spacing: 10px;
}

element {
    orientation: vertical;
    padding: 8px;
    spacing: 6px;
}

element-icon {
    size: 180px;
}

element-text {
    horizontal-align: 0.5;
}
```

- [ ] **Step 3: Validate the themes parse**

```bash
for t in glass wallpaper-grid; do rofi -theme ~/.config/rofi/$t.rasi -dump-theme >/dev/null 2>&1; echo "$t exit=$?"; done
```
Expected: `glass exit=0`, `wallpaper-grid exit=0`.

- [ ] **Step 4: Create `rofi-toggle.sh` and switch clipboard to rofi**

`~/.config/hypr/scripts/rofi-toggle.sh`:
```bash
#!/bin/bash
if pgrep -x "rofi" > /dev/null; then
    pkill -x "rofi"
else
    rofi -show drun
fi
```
Run: `chmod +x ~/.config/hypr/scripts/rofi-toggle.sh`

In `~/.config/hypr/scripts/clipboard-toggle.sh`, replace:
```bash
if pgrep -x "wofi" > /dev/null; then
    pkill -x "wofi"
else
    cliphist list | wofi --dmenu | cliphist decode | wl-copy
fi
```
with:
```bash
if pgrep -x "rofi" > /dev/null; then
    pkill -x "rofi"
else
    cliphist list | rofi -dmenu -p "Clipboard" | cliphist decode | wl-copy
fi
```

- [ ] **Step 5: Update binds in `hyprland.conf`**

Replace `$menu = wofi --show drun` with `$menu = rofi -show drun`.
Replace `bindr = SUPER, SUPER_L, exec, ~/.config/hypr/scripts/wofi-toggle.sh` with `bindr = SUPER, SUPER_L, exec, ~/.config/hypr/scripts/rofi-toggle.sh`.
Replace `bind = $mod, R, exec, wofi --show run` with `bind = $mod, R, exec, rofi -show run`.
After `bind = $mod, L, exec, hyprlock`, add:
```
bind = $mod, W, exec, ~/.config/hypr/scripts/wallpaper.sh --random
bind = $mod SHIFT, W, exec, ~/.config/hypr/scripts/wallpaper.sh --pick
```

Run: `hyprctl reload && hyprctl configerrors; grep -n wofi ~/.config/hypr/hyprland.conf ~/.config/hypr/scripts/*.sh`
Expected: no config errors. The only `wofi` hits are inside `scripts/wofi-toggle.sh` (removed in Task 10).

- [ ] **Step 6: Exercise every bind**

- Tap SUPER: the glass launcher shows with icons. Tap again: it closes.
- `SUPER+R`: run mode.
- `SUPER+V`: clipboard list. Picking an entry copies it (`wl-paste` shows it).
- `SUPER+SHIFT+V`: delete picker (already rofi). It looks the same.
- `SUPER+SHIFT+W`: a thumbnail grid of `~/Pictures/Wallpapers`. Picking one re-colors everything.
- `SUPER+W`: random wallpaper.

- [ ] **Step 7: Picker cancel (Review Focus #4)**

```bash
before=$(cat ~/.cache/current-wallpaper); sum=$(md5sum < ~/.config/hypr/colors.conf)
~/.config/hypr/scripts/wallpaper.sh --pick; echo "exit=$?"   # press Esc in the grid
[ "$(cat ~/.cache/current-wallpaper)" = "$before" ] && [ "$(md5sum < ~/.config/hypr/colors.conf)" = "$sum" ] && echo "unchanged OK"
```
Expected: `exit=0` and `unchanged OK`.

- [ ] **Step 8: Commit**

```bash
cd ~/.config/hypr && git add hyprland.conf scripts/rofi-toggle.sh scripts/clipboard-toggle.sh && git commit -m "Replace wofi with glass rofi theme; add wallpaper binds

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Mako glass notifications

**Files:**
- Already created: `~/.config/matugen/templates/mako-config` (Task 2), which generates `~/.config/mako/config`

**Interfaces:**
- Consumes: Task 2 output
- Produces: nothing new

- [ ] **Step 1: Check that the generated config keeps every original rule**

```bash
for k in 'width=320' 'height=100' 'margin=12' 'padding=16' 'anchor=top-right' 'default-timeout=3000' '[urgency=low]' '[urgency=normal]' '[urgency=critical]' 'default-timeout=0' '[app-name=XAMPP]'; do grep -qF -- "$k" ~/.config/mako/config && echo "ok $k" || echo "MISSING $k"; done
```
Expected: every line `ok`.

- [ ] **Step 2: Reload and send each urgency**

```bash
makoctl reload; echo "reload exit=$?"
notify-send -u low "Low" "tertiary border, 2s"
notify-send -u normal "Normal" "primary border, 3s"
notify-send -u critical "Critical" "error border, stays until clicked"
```
Expected: `reload exit=0`. Three translucent blurred cards top-right with the border colors as named. The critical one stays until clicked.

- [ ] **Step 3: Re-color check**

Run `SUPER+W`, then `notify-send "After" "new palette"`.
Expected: the border color matches the new palette.

No git commit (outside repo). Backup: `~/.config/hypr/backup-2026-10-09/mako/`.

---

### Task 9: Hyprlock glass card

**Files:**
- Modify (rewrite): `~/.config/hypr/hyprlock.conf`

**Interfaces:**
- Consumes: `colors.conf` vars `$primary $tertiary $error $on_surface $glass_card` (Task 2)
- Produces: nothing new

- [ ] **Step 1: Rewrite `hyprlock.conf`**

Keeps the video background, sizes, fonts and positions from the current file. Adds the glass card and palette colors.
```
source = ~/.config/hypr/colors.conf

background {
    monitor =
    path = /home/azriel/Videos/wallpaper_1080p.mp4
    blur_passes = 0
}

# Glass card behind clock, date and input
shape {
    monitor =
    size = 460, 420
    color = $glass_card
    rounding = 24
    border_size = 1
    border_color = $outline_dim
    position = 0, 40
    halign = center
    valign = center
}

input-field {
    monitor =
    size = 250, 50
    rounding = -1
    outline_thickness = 2
    dots_size = 0.16
    dots_spacing = 0.5
    dots_center = true
    outer_color = $primary
    inner_color = $glass_card
    font_color = $on_surface
    fade_on_empty = true
    placeholder_text = <i>Password...</i>
    hide_input = false
    check_color = $tertiary
    fail_color = $error
    fail_text = <i>$FAIL <b>($ATTEMPTS)</b></i>
    position = 0, -120
    halign = center
    valign = center
}

label {
    monitor =
    text = cmd[update:1000] echo "$(date +"%H:%M")"
    color = $primary
    font_size = 90
    font_family = JetBrains Mono Nerd Font Bold
    position = 0, 200
    halign = center
    valign = center
}

label {
    monitor =
    text = cmd[update:1000] echo "$(date +"%A, %B %d")"
    color = $on_surface
    font_size = 20
    font_family = JetBrains Mono Nerd Font
    position = 0, 100
    halign = center
    valign = center
}
```

- [ ] **Step 2: [USER] Lock and unlock**

Ask Azriel to press `SUPER+L` and check:
- The video plays behind a translucent rounded card, the clock is in the palette's primary color, and the input field is a pill.
- A **wrong** password first shows the error color and `$FAIL (1)`. Then the right password unlocks.
- There's no hyprlock error text on screen (hyprlock shows config errors at the top-left).

Expected: all three confirmed by Azriel.
If the lock screen is broken: switch to a TTY (`Ctrl+Alt+F3`), log in, and run `pkill -USR1 hyprlock` to unlock. Then `git -C ~/.config/hypr checkout -- hyprlock.conf`.

- [ ] **Step 3: Commit**

```bash
cd ~/.config/hypr && git add hyprlock.conf && git commit -m "Restyle hyprlock with glass card and matugen palette

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: End-to-end verification and cleanup

**Files:**
- Delete: `~/.config/hypr/scripts/wofi-toggle.sh`
- Modify: `~/.config/hypr/docs/2026-10-09-liquid-glass-rice-design.md` (Status line)

**Interfaces:**
- Consumes: everything above
- Produces: nothing new

- [ ] **Step 1: Full re-color pass (spec success criterion 2)**

Run `SUPER+W` twice with at least two wallpapers in `~/Pictures/Wallpapers` (Azriel can copy any from `~/Pictures`). After each run, check that all of these changed color: the window border gradient, the bar pills, the launcher (open it), a `notify-send`, kitty's background, and the hyprbars title bar on a floating window. Hyprlock picks up the colors at the next lock.

- [ ] **Step 2: [USER] Relogin test (spec success criteria 1 and 3)**

Ask Azriel to log out (`SUPER+M`) and log back in. Then run:
```bash
hyprctl configerrors; hyprctl plugin list | grep -E '^Plugin'; pgrep -x awww-daemon >/dev/null && echo awww-ok; pgrep -x waybar >/dev/null && echo waybar-ok
```
Expected: no config errors, every enabled plugin listed, `awww-ok`, `waybar-ok`, the last wallpaper restored, and no red error banner at login. Spot-check the old binds: `SUPER+Return`, `SUPER+E`, `Print`, `SUPER+V`, the volume keys, `SUPER+P`.

- [ ] **Step 3: Plugin isolation (spec success criterion 4)**

```bash
hyprpm disable hyprglass && hyprpm reload -n && hyprctl reload && hyprctl configerrors; echo "---"
hyprpm enable hyprglass && hyprpm reload -n && hyprctl reload && hyprctl plugin list | grep -c '^Plugin'
```
Expected: empty before `---`, then the count of enabled plugins.

- [ ] **Step 4: Remove the old wofi script and mark the spec implemented**

```bash
cd ~/.config/hypr
grep -rn 'wofi-toggle' hyprland.conf scripts/ ; echo "refs=$?"   # expect refs=1 (no references)
git rm scripts/wofi-toggle.sh
sed -i 's/^Status: approved in chat, pending spec review$/Status: implemented 2026-10-09/' docs/2026-10-09-liquid-glass-rice-design.md
git add docs/2026-10-09-liquid-glass-rice-design.md
git commit -m "Remove wofi toggle script; mark rice spec implemented

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Report**

Tell Azriel: which plugins are loaded and which fell back (with errors), the Hyprglass `layers` status from `hyprctl hyprglass stats`, whether the Hyprglass tag followed the float state, and where the backups are (`~/.config/hypr/backup-2026-10-09/`).
