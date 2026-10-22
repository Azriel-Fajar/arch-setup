#!/bin/bash
# Hyprland has no native minimize: park windows on a hidden special workspace.
#   minimize.sh         -> hide active window
#   minimize.sh restore -> rofi picker with app icons, bring chosen window back to current workspace
ws="special:minimized"

if [ "$1" != "restore" ]; then
    hyprctl dispatch movetoworkspacesilent "$ws" > /dev/null
    exit
fi

pgrep -x rofi > /dev/null && { pkill -x rofi; exit; }

clients=$(hyprctl clients -j | jq -c --arg ws "$ws" '[.[] | select(.workspace.name == $ws)]')
[ "$(jq length <<< "$clients")" = "0" ] && exit

# Window class -> icon name, via the app's .desktop file (StartupWMClass or filename)
icon_for() {
    local c=$1 f
    f=$(grep -lis "^StartupWMClass=$c$" /usr/share/applications/*.desktop ~/.local/share/applications/*.desktop 2>/dev/null | head -1)
    [ -z "$f" ] && f=$(find /usr/share/applications ~/.local/share/applications -iname "$c.desktop" 2>/dev/null | head -1)
    [ -n "$f" ] && sed -n 's/^Icon=//p' "$f" | head -1 || echo "${c,,}"
}

idx=$(jq -r '.[] | "\(.class)\t\(.title)"' <<< "$clients" | while IFS=$'\t' read -r class title; do
    printf '%s: %s\0icon\x1f%s\n' "$class" "$title" "$(icon_for "$class")"
done | rofi -dmenu -i -show-icons -p "Restore" -format i)
[ -z "$idx" ] && exit

addr=$(jq -r ".[$idx].address" <<< "$clients")
cur=$(hyprctl activeworkspace -j | jq .id)
hyprctl --batch "dispatch movetoworkspace $cur,address:$addr; dispatch focuswindow address:$addr" > /dev/null
