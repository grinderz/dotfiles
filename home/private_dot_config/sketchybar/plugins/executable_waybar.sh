#!/usr/bin/env bash
# Adapter for the bar scripts shared with waybar: runs the command given
# as arguments, reads its waybar JSON ({text, tooltip, class}) and paints
# the item. Empty text hides the item like waybar does, the class picks
# the color from style.css, the tooltip becomes a popup shown while the
# mouse is over the item (one popup line per tooltip line, pango markup
# stripped).
#
# usage (as an item script):  waybar.sh <command> [args...]
# the item also subscribes to mouse.entered / mouse.exited.global for the popup

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

case "${SENDER:-}" in
    mouse.entered) hover_mark "$NAME" entered; popup_show "$NAME"; exit 0 ;;
    mouse.exited.global) hover_mark "$NAME" exited; sketchybar --set "$NAME" popup.drawing=off; exit 0 ;;
esac

out=$("$@" 2>/dev/null) || out=""
if [ -z "$out" ]; then
    sketchybar --set "$NAME" drawing=off
    exit 0
fi

strip='def strip: gsub("<[^>]*>"; "")
    | gsub("&amp;"; "&") | gsub("&lt;"; "<") | gsub("&gt;"; ">")
    | gsub("&quot;"; "\"") | gsub("&#39;"; "'"'"'");'
text=$(jq -r "$strip"' .text // "" | strip' <<<"$out")
class=$(jq -r '.class // [] | if type == "array" then join(" ") else . end' <<<"$out")
mapfile -t tip < <(jq -r "$strip"' .tooltip // "" | strip' <<<"$out")
# an empty tooltip is one empty line to mapfile, which would be one blank
# popup row: an empty box
[ "${#tip[@]}" -eq 1 ] && [ -z "${tip[0]}" ] && tip=()

if [ -z "$text" ]; then
    sketchybar --set "$NAME" drawing=off
    exit 0
fi

# the loudest class wins, as the later rules do in style.css
color="$FG_COLOR"
case " $class " in
    *" critical "*|*" battery-critical "*|*" red "*|*" recording "*) color=$CRITICAL_COLOR ;;
    *" warning "*|*" battery-low "*|*" yellow "*|*" dnd "*) color=$WARNING_COLOR ;;
    *" running "*|*" plugged "*) color=$DIM_COLOR ;;
    *" paused "*) color=$MUTED_COLOR ;;
esac

sketchybar --set "$NAME" drawing=on label="$text" label.color="$color"
# the tooltip lines as popup rows (40 at most, the screen is height-bound
# like sway's tooltips); an empty tooltip leaves no popup
popup_lines "$NAME" "${tip[@]}"
