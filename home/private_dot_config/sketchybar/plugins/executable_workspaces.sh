#!/usr/bin/env bash
# repaint the workspace row like waybar's sway/workspaces: each workspace
# shows on the display of its monitor only, the focused one gets the
# button background, the visible one on the other monitor a lighter one,
# empty ones are hidden. Runs on aerospace_workspace_change
# (FOCUSED_WORKSPACE comes with the trigger), on focus changes and on a
# slow poll (windows moved between workspaces change no focus).

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

focused="${FOCUSED_WORKSPACE:-}"
if [ -z "$focused" ]; then
    focused="$(aerospace list-workspaces --focused 2>/dev/null || true)"
fi
# AeroSpace not up yet (login race): keep whatever is drawn
[ -n "$focused" ] || exit 0

# workspace -> display: AeroSpace's NSScreen index is what sketchybar
# calls the display (arrangement) id
declare -A display
while IFS='|' read -r ws id; do
    [ -n "$ws" ] && display[$ws]=$id
done < <(aerospace list-workspaces --monitor all \
    --format '%{workspace}|%{monitor-appkit-nsscreen-screens-id}' 2>/dev/null)

nonempty="$(aerospace list-workspaces --monitor all --empty no 2>/dev/null || true)"
visible="$(aerospace list-workspaces --monitor all --visible 2>/dev/null || true)"

args=()
for entry in $WORKSPACES; do
    ws="${entry%%:*}"
    item="space.$ws"
    args+=(--set "$item" "display=${display[$ws]:-0}")
    if [ "$ws" = "$focused" ]; then
        args+=(drawing=on background.drawing=on "background.color=$FOCUSED_COLOR")
    elif grep -qx "$ws" <<<"$visible"; then
        args+=(drawing=on background.drawing=on background.color=0x40ffffff)
    elif grep -qx "$ws" <<<"$nonempty"; then
        args+=(drawing=on background.drawing=off)
    else
        args+=(drawing=off)
    fi
done

# items may be mid-rebuild during a reload; a missing one is no reason to stop
sketchybar "${args[@]}" 2>/dev/null || true
