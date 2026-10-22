#!/bin/bash
# Guards hyprshot against Print-key spam: second press while one is running is ignored.
# flock doesn't work here: hyprshot spawns wl-copy to serve the Wayland clipboard, wl-copy
# inherits the lock fd and stays alive indefinitely, permanently wedging the lock. Track
# hyprshot's own PID instead so a long-lived wl-copy can't block later screenshots.
lockfile=/tmp/hyprshot.pid
if [ -f "$lockfile" ] && kill -0 "$(cat "$lockfile")" 2>/dev/null; then
    notify-send "Screenshot skipped" "Already running"
    exit 1
fi
echo $$ > "$lockfile"

# hyprshot's window mode crops to the client area, cutting off the border and the
# hyprbars title bar (floating windows). Grow each window box to include them.
if [[ " $* " == *" -m window "* ]]; then
    while [ $# -gt 0 ]; do
        case $1 in -o) dir=$2; shift ;; -f) name=$2; shift ;; esac
        shift
    done
    border=$(hyprctl getoption general:border_size -j | jq .int)
    bar=$(hyprctl getoption plugin:hyprbars:bar_height -j 2>/dev/null | jq '.int // 0' 2>/dev/null)
    workspaces=$(hyprctl monitors -j | jq -c 'map(.activeWorkspace.id)')
    boxes=$(hyprctl clients -j | jq -r --argjson ws "$workspaces" --argjson b "$border" --argjson bar "${bar:-0}" '
        .[] | select(.mapped and (.hidden | not) and (.workspace.id as $w | $ws | index($w))) |
        (if .fullscreen != 0 then 0 else $b end) as $e |
        (if .floating and .fullscreen == 0 then $bar else 0 end) as $t |
        "\(.at[0] - $e),\(.at[1] - $e - $t) \(.size[0] + 2 * $e)x\(.size[1] + 2 * $e + $t)"')
    # Freeze the screen like hyprshot -z, when hyprpicker is installed
    if command -v hyprpicker > /dev/null; then
        hyprpicker -r -z & picker=$!
        sleep 0.2
    fi
    geometry=$(slurp -r <<< "$boxes")
    if [ -n "$geometry" ]; then
        mkdir -p "$dir"
        grim -g "$geometry" "$dir/$name"
        wl-copy --type image/png < "$dir/$name"
        notify-send "Screenshot saved" "Image saved in <i>$dir/$name</i> and copied to the clipboard." -i "$dir/$name"
    fi
    [ -n "$picker" ] && kill "$picker"
else
    hyprshot -z "$@"
fi
rm -f "$lockfile"
