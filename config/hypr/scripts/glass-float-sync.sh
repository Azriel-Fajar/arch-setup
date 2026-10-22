#!/usr/bin/env bash
# Hyprglass on floating windows only. Rule-applied tags don't follow float changes
# (Hyprland 0.56), so tag windows from the event socket instead. Hyprglass is
# globally disabled in plugins.conf; the hyprglass_enabled tag turns it on per window.
SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

sync_window() {  # $1 = window address (with 0x)
    case $(hyprctl clients -j | jq -r --arg a "$1" '.[] | select(.address == $a) | .floating') in
        true)  hyprctl dispatch tagwindow +hyprglass_enabled "address:$1" >/dev/null ;;
        false) hyprctl dispatch tagwindow -- -hyprglass_enabled "address:$1" >/dev/null ;;
    esac
}

for addr in $(hyprctl clients -j | jq -r '.[].address'); do
    sync_window "$addr"
done

socat -U - UNIX-CONNECT:"$SOCK" | while IFS= read -r line; do
    case $line in
        openwindow\>\>* | changefloatingmode\>\>*)
            addr=${line#*>>}
            sync_window "0x${addr%%,*}" ;;
    esac
done
