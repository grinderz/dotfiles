#!/usr/bin/env bash
# battery icon by level, plug icon on AC, red under 15% (waybar's critical)

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

case "${SENDER:-}" in
    mouse.entered)
        hover_mark "$NAME" entered
        # "3:12 remaining" / "1:05 remaining present: true" -> the popup
        # (waybar's format-alt {time})
        eta=$(pmset -g batt | grep -Eo '[0-9]+:[0-9]+ remaining|charged|calculating' | head -n1 || true)
        popup_lines "$NAME" "${eta:-no estimate}"
        popup_show "$NAME"
        exit 0 ;;
    mouse.exited.global) hover_mark "$NAME" exited; sketchybar --set "$NAME" popup.drawing=off; exit 0 ;;
esac

batt="$(pmset -g batt)"
pct="$(grep -Eo '[0-9]+%' <<<"$batt" | head -n1 | tr -d %)"
# no battery (desktop): hide the item
if [ -z "$pct" ]; then
    sketchybar --set "$NAME" drawing=off
    exit 0
fi

case "$pct" in
    9[0-9]|100) icon="" ;;
    [6-8][0-9]) icon="" ;;
    [3-5][0-9]) icon="" ;;
    [1-2][0-9]) icon="" ;;
    *) icon="" ;;
esac

color=0xffffffff
if grep -q 'AC Power' <<<"$batt"; then
    icon=""
elif [ "$pct" -le 15 ]; then
    color="$CRITICAL_COLOR"
fi

sketchybar --set "$NAME" drawing=on icon="$icon" label="${pct}%" \
    icon.color="$color" label.color="$color"
