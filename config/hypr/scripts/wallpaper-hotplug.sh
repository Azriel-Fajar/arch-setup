#!/usr/bin/env bash
# Paint the current wallpaper on monitors plugged in after login.
STATE="${XDG_CACHE_HOME:-$HOME/.cache}/current-wallpaper"
sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

socat -U - UNIX-CONNECT:"$sock" | while IFS= read -r line; do
    case $line in
        monitoradded\>\>*)
            out=${line#monitoradded>>}
            sleep 0.5   # let awww see the new output
            img=$(cat "$STATE" 2>/dev/null) && [ -f "$img" ] &&
                awww img -o "$out" "$img" --transition-type fade --transition-duration 0.8
            ;;
    esac
done
