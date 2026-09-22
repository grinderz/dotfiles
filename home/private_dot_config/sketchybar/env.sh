# shellcheck shell=bash disable=SC2034
# shared by sketchybarrc and the plugins: sketchybar runs item scripts in
# its own (launchd) environment, so nothing exported from sketchybarrc
# reaches them, they source this instead ($CONFIG_DIR is set by sketchybar)

# launchd's PATH has no brew, no ~/.local/bin and no GNU coreutils
# (timeout, date) that the bar scripts shared with waybar expect
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"

# waybar's colors: the #285577 bar, #64727D focused button, #eb4d4b urgent,
# #f1c40f warning, #a5c5dd dimmed (running pipeline, plugged usb),
# #90b1b1 muted/paused
BAR_COLOR=0xff285577
FOCUSED_COLOR=0xff64727d
CRITICAL_COLOR=0xffeb4d4b
WARNING_COLOR=0xfff1c40f
DIM_COLOR=0xffa5c5dd
MUTED_COLOR=0xff90b1b1

# workspace labels as in the sway config; the number stays first so it
# reads as the key that gets there
WORKSPACES="1:cli 2:dev 3:web 4:ide 5:wrk 6:eml 7:doc 8 9:msg 10"

# popup_lines ITEM LINE...: fill ITEM's popup with one label per line
# without tearing it down: existing rows are relabeled in place, rows are
# added or removed only when the count changes (a rebuild on every hover
# or refresh made the popups blink). The row count is remembered per
# item in the cache dir.
popup_lines() {
    local item=$1 n=0 old=0 i stamp
    shift
    stamp="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar/popup-${item//[^[:alnum:]]/_}.rows"
    mkdir -p "$(dirname "$stamp")"
    [ -f "$stamp" ] && old=$(cat "$stamp")
    local args=()
    for line in "$@"; do
        [ "$n" -lt 40 ] || break
        if [ "$n" -ge "$old" ]; then
            args+=(--add item "$item.tip.$n" "popup.$item"
                   --set "$item.tip.$n" icon.drawing=off
                       label.font="Hack Nerd Font Mono:Regular:12.0"
                       padding_left=0 padding_right=0
                       label.padding_left=8 label.padding_right=8)
        fi
        args+=(--set "$item.tip.$n" label="${line:- }")
        n=$((n + 1))
    done
    for ((i = n; i < old; i++)); do
        args+=(--remove "$item.tip.$i")
    done
    printf '%s\n' "$n" >"$stamp"
    [ ${#args[@]} -gt 0 ] && sketchybar "${args[@]}" 2>/dev/null || true
}

# the items with a hover popup (popup_show closes the others explicitly:
# a regex over every item, aliases and brackets included, crashed
# sketchybar with a double free on the next real click)
POPUP_ITEMS="clock battery wifi eth bluetooth stats focus nosuspend lowpower weather gitlab jira recording toggles.handle"

# popup_show ITEM: open ITEM's popup, closing every other one first; the
# cursor sliding from one item straight onto its neighbour raises no
# mouse.exited.global for the first, so its popup would stay up
# hover_mark ITEM entered|exited: what the cursor last did on ITEM (a
# file per item, the handlers run as separate processes)
hover_mark() {
    local f="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar/hover-${1//[^[:alnum:]]/_}"
    mkdir -p "$(dirname "$f")"
    printf '%s\n' "$2" >"$f"
}

popup_show() {
    local args=() i f="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar/hover-${1//[^[:alnum:]]/_}"
    # the cursor left while the content was being gathered: opening the
    # popup now would leave it up with nothing to close it
    [ "$(cat "$f" 2>/dev/null)" = entered ] || return 0
    for i in $POPUP_ITEMS; do
        [ "$i" = "$1" ] || args+=(--set "$i" popup.drawing=off)
    done
    sketchybar "${args[@]}" --set "$1" popup.drawing=on 2>/dev/null || true
}

# popups_close: every popup off (front app or displays changed)
popups_close() {
    local args=() i
    for i in $POPUP_ITEMS; do
        hover_mark "$i" exited
        args+=(--set "$i" popup.drawing=off)
    done
    sketchybar "${args[@]}" 2>/dev/null || true
}

# the toggles drawer (waybar's #toggles group with the gear handle):
# these items hide behind the gear and a click on it shows them
TOGGLES_DRAWER=(nosuspend lowpower focus "Control Center,FocusModes")

# drawer_apply HANDLE: draw the drawer's items as the state file says
# (closed unless it says open); drawer_toggle HANDLE flips it
drawer_state() {
    cat "${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar/drawer-${1//[^[:alnum:]]/_}" 2>/dev/null || echo closed
}
drawer_apply() {
    local state args=() i
    state=$(drawer_state "$1")
    for i in "${TOGGLES_DRAWER[@]}"; do
        args+=(--set "$i" "drawing=$([ "$state" = open ] && echo on || echo off)")
    done
    sketchybar "${args[@]}" 2>/dev/null || true
}
drawer_toggle() {
    local f="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar/drawer-${1//[^[:alnum:]]/_}"
    mkdir -p "$(dirname "$f")"
    if [ "$(drawer_state "$1")" = open ]; then echo closed >"$f"; else echo open >"$f"; fi
    drawer_apply "$1"
}
