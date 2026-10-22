#!/bin/bash
# Toggle floating; when a window becomes floating, shrink it and center it.
hyprctl dispatch togglefloating > /dev/null
win=$(hyprctl activewindow -j)
if [ "$(jq .floating <<< "$win")" = "true" ]; then
    # Maximized/fullscreen windows refuse resize, so drop that state first.
    [ "$(jq .fullscreen <<< "$win")" != "0" ] && hyprctl dispatch fullscreenstate 0 0 > /dev/null
    hyprctl --batch "dispatch resizeactive exact 50% 55%; dispatch centerwindow" > /dev/null
fi
