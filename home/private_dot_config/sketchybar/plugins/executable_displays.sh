#!/usr/bin/env bash
# per-display placement: the now-playing line and the centered window
# title go to the widest display (the external monitor when one is
# connected), the left-aligned title copy to the others; runs at startup
# and on display_change

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

displays=$(sketchybar --query displays)
big=$(jq -r 'max_by(.frame.w) | .["arrangement-id"]' <<<"$displays")
# no displays yet (mid display_change): try again on the next event
[ -n "$big" ] && [ "$big" != null ] || exit 0
small=$(jq -r --argjson big "$big" '[.[] | .["arrangement-id"] | select(. != $big)] | map(tostring) | join(",")' <<<"$displays")
# The centered title hangs at the middle of the bar, which on the builtin
# screen is already inside the right cluster: it draws straight over the
# status items, whatever label.max_chars says. Narrow displays take the
# left copy instead, where the workspaces leave room.
width=$(jq -r 'max_by(.frame.w) | .frame.w | floor' <<<"$displays")
# The builtin screen leaves ~400pt between the workspaces and the status
# items, about 40 characters at 14pt Hack, and the now-playing line and
# the title share it: 20 each, or one long track title pushes the window
# title under the status cluster.
if [ "${width:-0}" -lt 1700 ]; then
    args=(--set front_app drawing=off
          --set front_app.small "display=${big:-0}" drawing=on label.max_chars=20
          --set media "display=${big:-0}" label.max_chars=20)
else
    args=(--set front_app "display=${big:-0}" drawing=on
          --set media "display=${big:-0}" label.max_chars=30
          --set front_app.small "display=${small:-0}" label.max_chars=40 "drawing=$([ -n "$small" ] && echo on || echo off)")
fi
[ ${#args[@]} -gt 0 ] && sketchybar "${args[@]}" 2>/dev/null || true
