#!/usr/bin/env bash
# waybar's sway/scratchpad: how many windows are parked on the hidden S
# workspace (scratch-term-mac), hidden when none

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

n=$(scratch-term-mac count)
if [ "${n:-0}" -gt 0 ]; then
    sketchybar --set "$NAME" drawing=on icon="" label="$n"
else
    sketchybar --set "$NAME" drawing=off
fi
