#!/usr/bin/env bash
# per-display placement: the tray aliases, the now-playing line and the
# centered window title go to the widest display (the external monitor
# when one is connected), the left-aligned title copy to the others; runs
# at startup and on display_change

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

displays=$(sketchybar --query displays)
big=$(jq -r 'max_by(.frame.w) | .["arrangement-id"]' <<<"$displays")
# no displays yet (mid display_change): try again on the next event
[ -n "$big" ] && [ "$big" != null ] || exit 0
small=$(jq -r --argjson big "$big" '[.[] | .["arrangement-id"] | select(. != $big)] | map(tostring) | join(",")' <<<"$displays")
# a lone display: the centered title everywhere, no left copy
args=(--set front_app "display=${big:-0}" --set media "display=${big:-0}"
      --set front_app.small "display=${small:-0}" "drawing=$([ -n "$small" ] && echo on || echo off)")
for alias in "${TRAY_ALIASES[@]}"; do
    args+=(--set "$alias" "display=${big:-0}")
done
[ ${#args[@]} -gt 0 ] && sketchybar "${args[@]}" 2>/dev/null || true
