#!/usr/bin/env bash
# waybar's power-profiles-daemon toggle, macOS style: Low Power Mode.
# Reading is free (pmset -g), switching needs root: a click runs
# `sudo -n pmset -a lowpowermode`, which works once sudoers allows it
# without a password (see the README), and opens the Battery settings
# otherwise. Bright while on, dim while off.

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

state() { pmset -g 2>/dev/null | awk '/lowpowermode/ { print $2 }'; }

case "${SENDER:-}" in
    mouse.entered)
        hover_mark "$NAME" entered
        if [ "$(state)" = 1 ]; then popup_lines "$NAME" "Low Power Mode: on (click to turn off)"
        else popup_lines "$NAME" "Low Power Mode: off (click to turn on)"; fi
        popup_show "$NAME"
        exit 0 ;;
    mouse.exited.global) hover_mark "$NAME" exited; sketchybar --set "$NAME" popup.drawing=off; exit 0 ;;
esac

if [ "${SENDER:-}" = mouse.clicked ]; then
    if [ "$(state)" = 1 ]; then want=0; else want=1; fi
    if ! sudo -n pmset -a lowpowermode "$want" >/dev/null 2>&1; then
        open 'x-apple.systempreferences:com.apple.Battery-Settings.extension'
    fi
fi

if [ "$(state)" = 1 ]; then
    sketchybar --set "$NAME" icon.color="$FG_COLOR"
else
    sketchybar --set "$NAME" icon.color=$MUTED_COLOR
fi
