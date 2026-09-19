#!/usr/bin/env bash
# SSID of the wireless link, hidden while disconnected (waybar's
# network#wifi). `networksetup -getairportnetwork` stopped reporting the
# SSID on Sonoma+, ipconfig still does.

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

case "${SENDER:-}" in
    mouse.entered)
        hover_mark "$NAME" entered
        # address, signal/noise and channel (waybar's tooltip), fetched on
        # hover only: system_profiler takes a moment
        iface=$(networksetup -listallhardwareports \
            | awk '/Hardware Port: Wi-Fi/ { getline; print $2; exit }')
        ip=$(ipconfig getifaddr "${iface:-en0}" 2>/dev/null || true)
        info=$(system_profiler SPAirPortDataType -json 2>/dev/null \
            | jq -r '.SPAirPortDataType[0].spairport_airport_interfaces[0].spairport_current_network_information
                | select(. != null)
                | "\(.spairport_signal_noise // "?")  ch \(.spairport_network_channel // "?")"' 2>/dev/null || true)
        popup_lines "$NAME" "${iface:-?} ${ip:-no address}  ${info:-}"
        popup_show "$NAME"
        exit 0 ;;
    mouse.exited.global) hover_mark "$NAME" exited; sketchybar --set "$NAME" popup.drawing=off; exit 0 ;;
esac

iface="$(networksetup -listallhardwareports \
    | awk '/Hardware Port: Wi-Fi/ { getline; print $2; exit }')"
ssid="$(ipconfig getsummary "${iface:-en0}" 2>/dev/null \
    | awk -F ' SSID : ' '/ SSID : / { print $2; exit }')"

if [ -z "$ssid" ]; then
    sketchybar --set "$NAME" drawing=off
else
    sketchybar --set "$NAME" drawing=on icon="" label="$ssid"
fi
