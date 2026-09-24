#!/usr/bin/env bash
# output volume: the volume_change event carries the percentage in INFO;
# the first run (no event) reads it from the system

set -euo pipefail

# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

if [ "${SENDER:-}" = "volume_change" ]; then
    vol="$INFO"
else
    vol="$(osascript -e 'output volume of (get volume settings)')"
    if [ "$(osascript -e 'output muted of (get volume settings)')" = "true" ]; then
        vol=0
    fi
fi

case "$vol" in
    [6-9][0-9]|100) icon="" ;;
    [1-5][0-9]|[1-9]) icon="" ;;
    *) icon="" ;;
esac

# the microphone level rides along like waybar's {format_source}; there
# is no input mute on macOS, 0% is as muted as it gets
mic=$(osascript -e 'input volume of (get volume settings)' 2>/dev/null || echo "")
src=""
[ -n "$mic" ] && [ "$mic" != 0 ] && src="   ${mic}%"

if [ "$vol" = "0" ]; then
    # muted: dim like waybar's #pulseaudio.muted
    sketchybar --set "$NAME" icon="$icon" label="$src" icon.color="$MUTED_COLOR"
else
    sketchybar --set "$NAME" icon="$icon" label="${vol}%$src" icon.color="$FG_COLOR"
fi
