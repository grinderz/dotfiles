#!/usr/bin/env bash
# waybar's mpris: artist and title of what is playing, hidden when
# nothing is. sketchybar's own media_change event is dead on macOS 15.4+
# (Apple locked MediaRemote down), media-control (brew, the
# mediaremote-adapter) still reads it; polled, a click toggles
# play/pause like waybar's mpris.

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

if [ "${SENDER:-}" = mouse.clicked ]; then
    media-control toggle-play-pause >/dev/null 2>&1 || true
    sleep 0.5
fi

info=$(media-control get 2>/dev/null || echo null)
if [ "$info" = null ] || [ -z "$info" ]; then
    sketchybar --set "$NAME" drawing=off
    exit 0
fi

read -r playing < <(jq -r '.playing // false' <<<"$info")
text=$(jq -r '[.artist, .title] | map(select(. != null and . != "")) | join(" - ")' <<<"$info")

if [ "$playing" = true ]; then
    sketchybar --set "$NAME" drawing=on icon="▶" label="$text" \
        icon.color=0xffffffff label.color=0xffffffff
else
    sketchybar --set "$NAME" drawing=on icon="⏸" label="$text" \
        icon.color=$MUTED_COLOR label.color=$MUTED_COLOR
fi
