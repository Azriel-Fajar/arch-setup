#!/usr/bin/env bash
# Live wallpaper via mpvpaper, tuned to stay cheap. Sits on top of awww, so
# "static" mode just stops mpvpaper and the awww wallpaper shows again.
# Usage: livewall.sh <video> | --random | --pick | --restore | --static | --toggle
set -uo pipefail

LIVE_DIR="$HOME/Videos/LiveWallpapers"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE="$CACHE/current-livewall"   # last live video
MODE="$CACHE/wallpaper-mode"      # live | static
THUMBS="$CACHE/livewall-thumbs"
OPT="$CACHE/livewall-opt"         # 1920x1200 30fps copy: what mpvpaper plays
SMALL="$CACHE/livewall-small"     # 480x300 12fps copy: what MacShell's glass refracts
GLASS="$CACHE/livewall-glass"     # holds the small copy's path while live, empty when static

list_vids() {
    find "$LIVE_DIR" -maxdepth 1 -type f \( -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.gif' \) | sort
}

thumb() {  # video -> cached jpg path
    local v=$1 t="$THUMBS/$(basename "${1%.*}").jpg"
    mkdir -p "$THUMBS"
    [ -s "$t" ] || ffmpeg -loglevel error -y -ss 1 -i "$v" -frames:v 1 -vf scale=480:-1 "$t" </dev/null
    printf '%s' "$t"
}

pick_vid() {
    list_vids | while IFS= read -r f; do
        printf '%s\0icon\x1f%s\n' "$(basename "$f")" "$(thumb "$f")"
    done | rofi -dmenu -i -show-icons -p "Live wallpaper" -theme ~/.config/rofi/wallpaper-grid.rasi
}

# Build the optimized + small copies once, in the background; then point the glass at the small one
glass_sync() {  # video, or "" for static
    local v=$1 base
    if [ -z "$v" ]; then : > "$GLASS"; return; fi
    base=$(basename "${v%.*}").mp4
    (
        mkdir -p "$OPT" "$SMALL"
        [ -s "$OPT/$base" ] || ffmpeg -loglevel error -y -i "$v" -an -r 30 \
            -vf "scale=1920:1200:force_original_aspect_ratio=increase,crop=1920:1200" \
            -c:v libx264 -preset medium -crf 26 -pix_fmt yuv420p "$OPT/$base"
        [ -s "$SMALL/$base" ] || ffmpeg -loglevel error -y -i "$v" -an -r 12 \
            -vf "scale=480:300:force_original_aspect_ratio=increase,crop=480:300" \
            -c:v libx264 -preset fast -crf 30 -pix_fmt yuv420p "$SMALL/$base"
        [ "$(cat "$MODE" 2>/dev/null)" = live ] && printf '%s' "$SMALL/$base" > "$GLASS"
    ) </dev/null >/dev/null 2>&1 &
}

play() {
    local video=$1 base
    base=$(basename "${video%.*}").mp4
    [ -s "$OPT/$base" ] && video="$OPT/$base"
    command -v mpvpaper >/dev/null || { echo "livewall: install mpvpaper (yay -S mpvpaper)" >&2; exit 1; }
    glass_sync "$1"
    pkill -x mpvpaper 2>/dev/null
    # -p: pause while fully covered by windows; hwdec + small buffers keep CPU/RAM low
    # panscan=1.0: cover the 16:10 screen (crop instead of letterbox)
    mpvpaper -p -f \
        -o "no-audio loop panscan=1.0 hwdec=auto-safe vo=gpu gpu-context=wayland framedrop=vo cache=no demuxer-max-bytes=8MiB demuxer-max-back-bytes=0 osc=no input-default-bindings=no" \
        '*' "$video"
}

# Lock (hyprlock) and login (SDDM) can't play video, so they show a still of the
# active wallpaper. The file is user-owned; the dir is not, so cp instead of mv.
LOGIN_BG=/usr/share/sddm/themes/macos/background.jpg
login_bg_video() {
    local tmp="$CACHE/login-bg.jpg"
    ffmpeg -loglevel error -y -ss 1 -i "$1" -frames:v 1 -q:v 2 \
        -vf "scale=1920:1200:force_original_aspect_ratio=increase,crop=1920:1200" "$tmp" </dev/null \
        && cp -- "$tmp" "$LOGIN_BG" 2>/dev/null
    return 0
}
login_bg_static() {
    local img; img=$(cat "$CACHE/current-wallpaper" 2>/dev/null)
    [ -f "$img" ] && cp -- "$img" "$LOGIN_BG" 2>/dev/null
    return 0
}
set_live() {
    [ -f "$1" ] || { echo "livewall: no such video: $1" >&2; exit 1; }
    printf '%s\n' "$(realpath -- "$1")" > "$STATE"
    echo live > "$MODE"
    login_bg_video "$1"
    play "$(cat "$STATE")"
}

set_static() { echo static > "$MODE"; pkill -x mpvpaper 2>/dev/null; : > "$GLASS"; login_bg_static; return 0; }

current=$(cat "$STATE" 2>/dev/null || true)

case "${1:-}" in
    --random)
        v=$(list_vids | grep -vxF -- "$current" | shuf -n1)
        [ -n "$v" ] || v=$current
        set_live "$v" ;;
    --pick)
        name=$(pick_vid) || exit 0   # Esc / cancel: change nothing
        [ -n "$name" ] || exit 0
        set_live "$LIVE_DIR/$name" ;;
    --restore)
        [ "$(cat "$MODE" 2>/dev/null)" = live ] || exit 0
        for _ in $(seq 50); do awww query >/dev/null 2>&1 && break; sleep 0.1; done
        v=${current:-$(list_vids | head -n1)}
        [ -n "$v" ] && play "$v" ;;
    --static) set_static ;;
    --toggle)
        if [ "$(cat "$MODE" 2>/dev/null)" = live ]; then set_static
        else set_live "${current:-$(list_vids | head -n1)}"; fi ;;
    "" | -h | --help)
        echo "Usage: $(basename "$0") <video> | --random | --pick | --restore | --static | --toggle" >&2
        exit 2 ;;
    *) set_live "$1" ;;
esac
