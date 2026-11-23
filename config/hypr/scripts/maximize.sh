#!/bin/bash
# Green title-bar button: a tiled (auto full size) window goes windowed;
# a floating window toggles maximize.
if [ "$(hyprctl activewindow -j | jq .floating)" = "true" ]; then
    hyprctl dispatch "hl.dsp.window.fullscreen({ mode = 'maximized' })" > /dev/null
else
    ~/.config/hypr/scripts/float-toggle.sh
fi
