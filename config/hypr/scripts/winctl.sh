#!/usr/bin/env bash
# Windows-style stacking: every window floats, so the clicked window always comes
# to the front. "Maximized" is a floating window sized to the work area (a real
# Hyprland maximize would stay above the other floats).
#   winctl.sh daemon          event loop: place new windows (remembered state or
#                             cascaded default), remember state per app on close
#   winctl.sh max             maximize <-> restore active window
#   winctl.sh up              maximize active window
#   winctl.sh down            restore if maximized/snapped, else minimize
#   winctl.sh snap l|r        snap active window to the left/right half
#   winctl.sh desk up|down|toggle   overview / show desktop (4-finger swipes, Super+Tab)
RUN="$XDG_RUNTIME_DIR/hypr-winctl"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/winstate.json"
RESTORE="$RUN/restore.json"   # address -> geometry before maximize/snap
CACHE="$RUN/clients.json"     # address -> last seen window (closed windows are gone from hyprctl)
# Dialogs/prompts keep their own size and are never remembered
SKIP='^(xdg-desktop-portal.*|polkit-gnome.*|.*polkit.*|pinentry.*|gcr-prompter|hyprland-share-picker)$'
MIN_W=500 MIN_H=350
STEP=32   # cascade offset

mkdir -p "$RUN" "${STATE%/*}"
[ -s "$STATE" ] || echo '{}' > "$STATE"
[ -s "$RESTORE" ] || echo '{}' > "$RESTORE"
[ -s "$CACHE" ] || echo '{}' > "$CACHE"

# Content box of a maximized window on monitor $1 as "x y w h": the monitor minus
# reserved space (menu bar), outer gaps, border and the hyprbars title bar.
workarea() {
    local gap bs bar
    gap=$(hyprctl getoption general:gaps_out -j | jq -r '.custom // (.int|tostring)' | awk '{print $1}')
    bs=$(hyprctl getoption general:border_size -j | jq '.int // 2')
    bar=$(hyprctl getoption plugin:hyprbars:bar_height -j 2>/dev/null | jq '.int // 28' 2>/dev/null || echo 28)
    hyprctl monitors -j | jq -r --argjson id "$1" --argjson g "$gap" --argjson b "$bs" --argjson t "$bar" '
        .[] | select(.id == $id) | .scale as $s | .reserved as $r |
        (if .transform % 2 == 1 then [.height, .width] else [.width, .height] end | map(. / $s | floor)) as [$w, $h] |
        "\(.x + $r[0] + $g + $b) \(.y + $r[1] + $g + $b + $t) \($w - $r[0] - $r[2] - 2*$g - 2*$b) \($h - $r[1] - $r[3] - 2*$g - 2*$b - $t)"'
}

client() { hyprctl clients -j | jq -c --arg a "$1" '.[] | select(.address == $a)'; }

setgeom() {  # addr x y w h
    hyprctl --batch "dispatch resizewindowpixel exact $4 $5,address:$1; dispatch movewindowpixel exact $2 $3,address:$1" > /dev/null
    snapshot  # a close right after this must see the new geometry
}

near() { local d=$(($1 - $2)); [ "${d#-}" -le "${3:-6}" ]; }

is_max() {  # x y w h  wx wy ww wh
    near "$1" "$5" && near "$2" "$6" && near "$3" "$7" && near "$4" "$8"
}

restore_get() { jq -r --arg a "$1" '.[$a] // empty | "\(.[0]) \(.[1]) \(.[2]) \(.[3])"' "$RESTORE"; }
restore_set() {  # addr x y w h
    jq --arg a "$1" --argjson g "[$2,$3,$4,$5]" '.[$a] = $g' "$RESTORE" > "$RESTORE.tmp" && mv "$RESTORE.tmp" "$RESTORE"
}
restore_del() { jq --arg a "$1" 'del(.[$a])' "$RESTORE" > "$RESTORE.tmp" && mv "$RESTORE.tmp" "$RESTORE"; }

# Active window as shell vars: A X Y W H MON FS FLOAT; plus work area WX WY WW WH
load_active() {
    local j
    j=$(hyprctl activewindow -j)
    [ "$(jq -r '.address // empty' <<< "$j")" ] || exit 0
    read -r A X Y W H MON FS FLOAT < <(jq -r '"\(.address) \(.at[0]) \(.at[1]) \(.size[0]) \(.size[1]) \(.monitor) \(.fullscreen) \(.floating)"' <<< "$j")
    if [ "$FS" != 0 ]; then hyprctl dispatch fullscreenstate 0 0 > /dev/null; fi
    if [ "$FLOAT" != true ]; then hyprctl dispatch setfloating "address:$A" > /dev/null; fi
    read -r WX WY WW WH < <(workarea "$MON")
}

maximize() {
    is_max "$X" "$Y" "$W" "$H" "$WX" "$WY" "$WW" "$WH" && return
    [ -n "$(restore_get "$A")" ] || restore_set "$A" "$X" "$Y" "$W" "$H"
    setgeom "$A" "$WX" "$WY" "$WW" "$WH"
}

restore() {
    local g
    g=$(restore_get "$A")
    if [ -z "$g" ]; then  # never had a normal size: default box, centered
        local w=$((WW * 60 / 100)) h=$((WH * 65 / 100))
        g="$((WX + (WW - w) / 2)) $((WY + (WH - h) / 2)) $w $h"
    fi
    restore_del "$A"
    setgeom "$A" $g
}

snap() {
    local bs gap half
    bs=$(hyprctl getoption general:border_size -j | jq '.int // 2')
    gap=$(hyprctl getoption general:gaps_out -j | jq -r '.custom // (.int|tostring)' | awk '{print $1}')
    is_max "$X" "$Y" "$W" "$H" "$WX" "$WY" "$WW" "$WH" || [ -n "$(restore_get "$A")" ] || restore_set "$A" "$X" "$Y" "$W" "$H"
    half=$(((WW - 2 * bs - gap) / 2))
    case $1 in
        l) setgeom "$A" "$WX" "$WY" "$half" "$WH" ;;
        r) setgeom "$A" "$((WX + WW - half))" "$WY" "$half" "$WH" ;;
    esac
}

# ---- daemon -----------------------------------------------------------------

snapshot() {
    hyprctl clients -j | jq -c --slurpfile old "$CACHE" '
        $old[0] + (map({key: .address, value: {c: .initialClass, at, size, floating, fullscreen, monitor}}) | from_entries)' \
        > "$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
}

placeable() {  # class floating fullscreen w h
    [ -n "$1" ] && [ "$2" = true ] && [ "$3" = 0 ] && [ "$4" -ge $MIN_W ] && [ "$5" -ge $MIN_H ] && ! [[ $1 =~ $SKIP ]]
}

on_open() {
    local a=$1 j c x y w h mon fs fl ws wx wy ww wh saved i=0
    restore_del "$a"  # Hyprland reuses addresses
    j=$(client "$a")
    [ -z "$j" ] && return
    read -r c x y w h mon fs fl ws < <(jq -r '"\(.initialClass) \(.at[0]) \(.at[1]) \(.size[0]) \(.size[1]) \(.monitor) \(.fullscreen) \(.floating) \(.workspace.id)"' <<< "$j")
    placeable "$c" "$fl" "$fs" "$w" "$h" || return
    read -r wx wy ww wh < <(workarea "$mon")

    saved=$(jq -c --arg c "$c" '.[$c] // empty' "$STATE")
    if [ -n "$saved" ]; then
        read -r x y w h < <(jq -r '.g | "\(.[0]) \(.[1]) \(.[2]) \(.[3])"' <<< "$saved")
        x=$((x + wx)) y=$((y + wy))
        if [ "$(jq -r '.max' <<< "$saved")" = true ]; then
            local r
            r=$(jq -r '.g as $g | (.r // $g) | "\(.[0]) \(.[1]) \(.[2]) \(.[3])"' <<< "$saved")
            read -r x y w h <<< "$r"
            restore_set "$a" $((x + wx)) $((y + wy)) "$w" "$h"
            setgeom "$a" "$wx" "$wy" "$ww" "$wh"
            return
        fi
    elif [ $((w * 100 / ww)) -gt 95 ] || [ $((h * 100 / wh)) -gt 95 ] || [ $((w * 100 / ww)) -lt 30 ]; then
        w=$((ww * 60 / 100)) h=$((wh * 65 / 100))
        x=$((wx + (ww - w) / 2)) y=$((wy + (wh - h) / 2))
    else
        x=$((wx + (ww - w) / 2)) y=$((wy + (wh - h) / 2))
    fi

    # clamp into the work area
    [ "$w" -gt "$ww" ] && w=$ww
    [ "$h" -gt "$wh" ] && h=$wh
    [ "$x" -gt $((wx + ww - w)) ] && x=$((wx + ww - w))
    [ "$y" -gt $((wy + wh - h)) ] && y=$((wy + wh - h))
    [ "$x" -lt "$wx" ] && x=$wx
    [ "$y" -lt "$wy" ] && y=$wy

    # cascade: step down-right while another window on this workspace sits at the same spot
    local others
    others=$(hyprctl clients -j | jq -r --arg a "$a" --argjson ws "$ws" \
        '.[] | select(.address != $a and .workspace.id == $ws and .floating) | "\(.at[0]) \(.at[1])"')
    while [ $i -lt 20 ]; do
        local hit=0 ox oy
        while read -r ox oy; do
            [ -z "$ox" ] && continue
            if near "$ox" "$x" 10 && near "$oy" "$y" 10; then hit=1; break; fi
        done <<< "$others"
        [ $hit = 0 ] && break
        x=$((x + STEP)) y=$((y + STEP))
        if [ $((x + w)) -gt $((wx + ww)) ] || [ $((y + h)) -gt $((wy + wh)) ]; then
            x=$((wx + STEP * (i % 4))) y=$wy
        fi
        i=$((i + 1))
    done
    setgeom "$a" "$x" "$y" "$w" "$h"
}

on_close() {
    local a=$1 j c x y w h mon fs fl wx wy ww wh max=false r
    j=$(jq -c --arg a "$a" '.[$a] // empty' "$CACHE")
    [ -z "$j" ] && return
    read -r c x y w h mon fs fl < <(jq -r '"\(.c) \(.at[0]) \(.at[1]) \(.size[0]) \(.size[1]) \(.monitor) \(.fullscreen) \(.floating)"' <<< "$j")
    placeable "$c" "$fl" "$fs" "$w" "$h" || { restore_del "$a"; return; }
    read -r wx wy ww wh < <(workarea "$mon")
    [ -z "$wx" ] && return
    is_max "$x" "$y" "$w" "$h" "$wx" "$wy" "$ww" "$wh" && max=true
    r=$(jq -c --arg a "$a" --argjson wx "$wx" --argjson wy "$wy" '.[$a] // null | if . then [.[0]-$wx, .[1]-$wy, .[2], .[3]] else null end' "$RESTORE")
    jq --arg c "$c" --argjson g "[$((x - wx)),$((y - wy)),$w,$h]" --argjson m $max --argjson r "$r" \
        '.[$c] = {g: $g, max: $m, r: $r}' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    restore_del "$a"
}

daemon() {
    exec 9> "$RUN/daemon.lock"
    flock -n 9 || exit 0
    local sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" a mon wx wy ww wh

    # windows that were tiled before this ran: make them maximized floats
    hyprctl clients -j | jq -r '.[] | select(.floating == false and .fullscreen == 0 and (.workspace.name | startswith("special") | not)) | "\(.address) \(.monitor) \(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"' |
    while read -r a mon _ _ _ _; do
        hyprctl dispatch setfloating "address:$a" > /dev/null
        read -r wx wy ww wh < <(workarea "$mon")
        setgeom "$a" "$wx" "$wy" "$ww" "$wh"
    done

    snapshot
    (while sleep 1; do snapshot; done) &
    trap 'kill $!' EXIT

    socat -U - UNIX-CONNECT:"$sock" | while IFS= read -r line; do
        case $line in
            openwindow\>\>*)  a=${line#*>>}; on_open "0x${a%%,*}"; snapshot ;;
            closewindow\>\>*) a=${line#*>>}; on_close "0x$a" ;;
        esac
    done
}

# ---- show desktop / overview -----------------------------------------------

desk() {
    local ws flag a
    ws=$(hyprctl activeworkspace -j | jq .id)
    flag="$RUN/desk-$ws"
    case $1 in
        toggle)
            if [ -f "$RUN/overview" ]; then rm -f "$RUN/overview"; hyprctl dispatch overview:close > /dev/null
            else touch "$RUN/overview"; hyprctl dispatch overview:open > /dev/null; fi ;;
        up)
            if [ -f "$flag" ]; then  # desktop shown: bring the windows back
                rm -f "$flag"
                for a in $(hyprctl clients -j | jq -r --arg w "special:desk$ws" '.[] | select(.workspace.name == $w) | .address'); do
                    hyprctl dispatch movetoworkspacesilent "$ws,address:$a" > /dev/null
                done
            else
                touch "$RUN/overview"; hyprctl dispatch overview:open > /dev/null
            fi ;;
        down)
            if [ -f "$RUN/overview" ]; then
                rm -f "$RUN/overview"; hyprctl dispatch overview:close > /dev/null
            elif [ ! -f "$flag" ]; then  # show desktop: park this workspace's windows
                local addrs
                addrs=$(hyprctl clients -j | jq -r --argjson w "$ws" '.[] | select(.workspace.id == $w) | .address')
                [ -z "$addrs" ] && return
                touch "$flag"
                for a in $addrs; do
                    hyprctl dispatch movetoworkspacesilent "special:desk$ws,address:$a" > /dev/null
                done
            fi ;;
    esac
}

case $1 in
    daemon) daemon ;;
    max)    load_active; if is_max "$X" "$Y" "$W" "$H" "$WX" "$WY" "$WW" "$WH"; then restore; else maximize; fi ;;
    up)     load_active; maximize ;;
    down)   load_active
            if is_max "$X" "$Y" "$W" "$H" "$WX" "$WY" "$WW" "$WH" || [ -n "$(restore_get "$A")" ]; then restore
            else ~/.config/hypr/scripts/minimize.sh; fi ;;
    snap)   load_active; snap "$2" ;;
    desk)   desk "$2" ;;
    *)      sed -n '2,12p' "$0"; exit 1 ;;
esac
