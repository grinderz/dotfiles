#!/usr/bin/env bash
# mouse wheel over the workspace row cycles the used workspaces of that
# monitor with wrap-around, like waybar's sway/workspaces (scroll down =
# next)

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

[ "${SENDER:-}" = mouse.scrolled ] || exit 0
delta="${SCROLL_DELTA:-0}"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar"
mkdir -p "$cache"
now=$(date +%s%3N)

# a trackpad swipe over the bar (aerospace-swipe's workspace gesture)
# arrives as a flood of horizontal events (delta 0) with a stray
# vertical one now and then: remember the horizontal ones and let no
# vertical delta through within 500 ms of them, or the swipe switches
# twice
if [ "$delta" -eq 0 ]; then
    printf '%s\n' "$now" >"$cache/scroll-h.ms"
    exit 0
fi
lasth=$(cat "$cache/scroll-h.ms" 2>/dev/null || echo 0)
[ $((now - lasth)) -ge 500 ] || exit 0

# one wheel notch arrives as a burst of events: one switch per 300 ms
last=$(cat "$cache/scroll.ms" 2>/dev/null || echo 0)
[ $((now - last)) -ge 300 ] || exit 0
printf '%s\n' "$now" >"$cache/scroll.ms"
if [ "$delta" -lt 0 ]; then
    aerospace-workspace-cycle next
elif [ "$delta" -gt 0 ]; then
    aerospace-workspace-cycle prev
fi
