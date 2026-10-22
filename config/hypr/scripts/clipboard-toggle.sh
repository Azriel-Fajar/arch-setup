#!/bin/bash
if pgrep -x "rofi" > /dev/null; then
    pkill -x "rofi"
else
    cliphist list | rofi -dmenu -p "Clipboard" | cliphist decode | wl-copy
fi
