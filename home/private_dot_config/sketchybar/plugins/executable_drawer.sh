#!/usr/bin/env bash
# the gear handle of the toggles drawer (waybar's custom/toggles-handle):
# a click shows or hides the toggles next to it, the state survives
# reloads (cache file); hover explains

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

case "${SENDER:-}" in
    mouse.clicked) drawer_toggle "$NAME" ;;
    mouse.entered)
        hover_mark "$NAME" entered
        popup_lines "$NAME" "toggles: keep awake, Low Power Mode, Focus (click to $([ "$(drawer_state "$NAME")" = open ] && echo hide || echo show))"
        popup_show "$NAME"
        exit 0 ;;
    mouse.exited.global) hover_mark "$NAME" exited; sketchybar --set "$NAME" popup.drawing=off; exit 0 ;;
    *) drawer_apply "$NAME" ;;
esac
