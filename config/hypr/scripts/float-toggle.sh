#!/bin/bash
# Toggle floating; when a window becomes floating, shrink it and center it.
hyprctl dispatch "hl.dsp.window.float({ action = 'toggle' })" > /dev/null
win=$(hyprctl activewindow -j)
if [ "$(jq .floating <<< "$win")" = "true" ]; then
    # Maximized/fullscreen windows refuse resize, so drop that state first.
    [ "$(jq .fullscreen <<< "$win")" != "0" ] &&
        hyprctl dispatch "hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = 'set' })" > /dev/null
    # 50% x 55% of the monitor (logical size), then center
    hyprctl eval "local m = hl.get_active_monitor()
        hl.dispatch(hl.dsp.window.resize({ x = math.floor(m.width / m.scale * 0.5), y = math.floor(m.height / m.scale * 0.55) }))
        hl.dispatch(hl.dsp.window.center())" > /dev/null
fi
