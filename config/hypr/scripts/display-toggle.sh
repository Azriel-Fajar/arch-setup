#!/usr/bin/env bash
# Toggle external display between mirror and extend, or reset to monitors.lua.
# Usage: display-toggle.sh mirror|extend|reset
set -euo pipefail

INTERNAL=eDP-1
# Loaded by hyprland.lua so mirror/extend survive `hyprctl reload` (e.g. wallpaper.sh)
OVERRIDE=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr-display-override.lua

# apply '<hl.monitor spec fields>'
apply() { echo "hl.monitor({ $1 })" > "$OVERRIDE"; hyprctl eval "$(cat "$OVERRIDE")" > /dev/null; }

notify() { command -v notify-send >/dev/null && notify-send -t 2500 "Display" "$1" || echo "$1"; }

external() {
    hyprctl -j monitors all \
        | jq -r --arg int "$INTERNAL" '.[] | select(.name != $int) | .name' \
        | head -1
}

case "${1:-}" in
mirror)
    EXT=$(external)
    [ -z "$EXT" ] && { notify "No external display connected"; exit 0; }
    apply "output = '$EXT', mode = 'preferred', position = '0x0', scale = 1, mirror = '$INTERNAL'"
    notify "Mirroring $INTERNAL to $EXT"
    ;;
extend)
    EXT=$(external)
    [ -z "$EXT" ] && { notify "No external display connected"; exit 0; }
    # Place external to the right of the internal panel.
    WIDTH=$(hyprctl -j monitors all | jq -r --arg int "$INTERNAL" \
        '.[] | select(.name == $int) | .width')
    apply "output = '$EXT', mode = '3840x2160@30', position = '${WIDTH}x0', scale = 2"
    notify "Extending to $EXT (right of $INTERNAL)"
    ;;
reset)
    rm -f "$OVERRIDE"
    hyprctl reload
    notify "Reloaded monitors.lua"
    ;;
*)
    echo "usage: $(basename "$0") mirror|extend|reset" >&2
    exit 1
    ;;
esac
