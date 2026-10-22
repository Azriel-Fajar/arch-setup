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

# Pick a random transition each change; login restore just fades in
if [ "${1:-}" = --restore ]; then
    trans=(--transition-type fade --transition-duration 0.8)
else
    # Cursor position for grow/outer, flipped to awww's bottom-left origin
    pos=$(hyprctl cursorpos 2>/dev/null | tr -d ' ')
    h=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .height' 2>/dev/null)
    if [[ $pos =~ ^[0-9]+,[0-9]+$ && $h =~ ^[0-9]+$ ]]; then
        pos="${pos%,*},$(( h - ${pos#*,} ))"
    else
        pos=center
    fi
    angle=$(shuf -i 0-359 -n1)
    case $(shuf -i 1-4 -n1) in
        1) trans=(--transition-type grow  --transition-pos "$pos" --transition-duration 1.4) ;;
        2) trans=(--transition-type outer --transition-pos "$pos" --transition-duration 1.4) ;;
        3) trans=(--transition-type wave  --transition-angle "$angle" --transition-wave 30,20 --transition-duration 1.6) ;;
        4) trans=(--transition-type wipe  --transition-angle "$angle" --transition-duration 1.2) ;;
    esac
fi

if ! awww img "$img" "${trans[@]}" --transition-fps 60 --transition-bezier .65,0,.35,1; then
    echo "wallpaper.sh: awww could not set '$img'" >&2
    exit 1
fi
printf '%s\n' "$img" > "$STATE"
# Login screen (SDDM macos theme) shows the same wallpaper; file is user-owned
cp -- "$img" /usr/share/sddm/themes/macos/background.jpg 2>/dev/null || true

# On failure the previously generated color files stay in place
if ! timeout 30 matugen image "$img" -m dark </dev/null >/dev/null; then
    notify-send -u critical "wallpaper.sh" "matugen failed, keeping previous colors"
    exit 1
fi

hyprctl reload >/dev/null
pkill -SIGUSR2 -x waybar || true
dunstctl reload || true
pkill -SIGUSR1 -x kitty || true
