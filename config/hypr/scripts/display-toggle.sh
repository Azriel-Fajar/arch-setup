#!/usr/bin/env bash
# Toggle external display between mirror and extend, or reset to monitors.conf.
# Usage: display-toggle.sh mirror|extend|reset
set -euo pipefail

INTERNAL=eDP-1
# Sourced by hyprland.conf so mirror/extend survive `hyprctl reload` (e.g. wallpaper.sh)
OVERRIDE=/run/user/1000/hypr-display-override.conf

apply() { echo "monitor = $1" > "$OVERRIDE"; hyprctl keyword monitor "$1"; }

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
    apply "$EXT,preferred,0x0,1,mirror,$INTERNAL"
    notify "Mirroring $INTERNAL to $EXT"
    ;;
extend)
    EXT=$(external)
    [ -z "$EXT" ] && { notify "No external display connected"; exit 0; }
    # Place external to the right of the internal panel.
    WIDTH=$(hyprctl -j monitors all | jq -r --arg int "$INTERNAL" \
        '.[] | select(.name == $int) | .width')
    apply "$EXT,3840x2160@30,${WIDTH}x0,2"
    notify "Extending to $EXT (right of $INTERNAL)"
    ;;
reset)
    rm -f "$OVERRIDE"
    hyprctl reload
    notify "Reloaded monitors.conf"
    ;;
*)
    echo "usage: $(basename "$0") mirror|extend|reset" >&2
    exit 1
    ;;
esac
