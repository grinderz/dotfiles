#!/usr/bin/env bash
# waybar's bluetooth module: hidden while the radio is off, the plain icon
# when on, the connected icon with the device count when devices are
# attached; their names go to the popup. Needs blueutil (brew).

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

if ! command -v blueutil >/dev/null 2>&1 || [ "$(blueutil -p)" != 1 ]; then
    sketchybar --set "$NAME" drawing=off
    exit 0
fi

mapfile -t names < <(blueutil --connected --format json | jq -r '.[].name')

case "${SENDER:-}" in
    mouse.entered)
        hover_mark "$NAME" entered
        # connected devices with their battery: BLE devices straight from
        # their Battery Service (bt-battery, built by sketchybarrc; macOS
        # shows those levels but publishes them nowhere), Apple gear from
        # system_profiler; read on hover only, both take a moment
        declare -A level
        while IFS=$'\t' read -r dev pct; do
            [ -n "$dev" ] && level[$dev]="$pct%"
        done < <("${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar/bt-battery" 2>/dev/null || true)
        while IFS=$'\t' read -r dev pct; do
            [ -n "$dev" ] && [ -n "$pct" ] && [ -z "${level[$dev]:-}" ] && level[$dev]="${pct%\%}%"
        done < <(system_profiler SPBluetoothDataType -json 2>/dev/null \
            | jq -r '.SPBluetoothDataType[0].device_connected[]? | to_entries[]
                | [.key, (.value.device_batteryLevelMain // .value.device_batteryLevel
                          // .value.device_batteryLevelLeft // "" | tostring)] | @tsv')
        rows=()
        for n in "${names[@]}"; do
            rows+=("$n  ${level[$n]:-(no battery info)}")
        done
        [ ${#rows[@]} -gt 0 ] || rows=("no devices")
        popup_lines "$NAME" "${rows[@]}"
        popup_show "$NAME"
        exit 0 ;;
    mouse.exited.global) hover_mark "$NAME" exited; sketchybar --set "$NAME" popup.drawing=off; exit 0 ;;
esac


if [ ${#names[@]} -gt 0 ]; then
    sketchybar --set "$NAME" drawing=on icon="󰂱" label="${#names[@]}"
    popup_lines "$NAME" "${names[@]}"
else
    sketchybar --set "$NAME" drawing=on icon="" label=""
    popup_lines "$NAME"
fi
