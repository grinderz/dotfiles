#!/usr/bin/env bash
# waybar's nosuspend toggle: keep the machine and display awake with
# caffeinate; the icon is bright while it runs, dim otherwise. A click
# toggles; the pid file keeps this bar's caffeinate apart from others.

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

pidfile="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar/caffeinate.pid"
mkdir -p "$(dirname "$pidfile")"

running() {
    [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null
}

case "${SENDER:-}" in
    mouse.entered)
        hover_mark "$NAME" entered
        if running; then popup_lines "$NAME" "keep awake: on (caffeinate, click to stop)"
        else popup_lines "$NAME" "keep awake: off (click to keep the Mac and display awake)"; fi
        popup_show "$NAME"
        exit 0 ;;
    mouse.exited.global) hover_mark "$NAME" exited; sketchybar --set "$NAME" popup.drawing=off; exit 0 ;;
esac

if [ "${SENDER:-}" = mouse.clicked ]; then
    if running; then
        kill "$(cat "$pidfile")" 2>/dev/null || true
        rm -f "$pidfile"
    else
        # -d: display too, -i: system idle sleep; ends with the bar
        (caffeinate -di & echo $! >"$pidfile") >/dev/null 2>&1
    fi
fi

if running; then
    sketchybar --set "$NAME" icon.color="$FG_COLOR"
else
    sketchybar --set "$NAME" icon.color=$MUTED_COLOR
fi
