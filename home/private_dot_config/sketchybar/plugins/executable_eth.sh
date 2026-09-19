#!/usr/bin/env bash
# waybar's network#eth: the wired link carrying the default route, with
# its address; hidden while the default route is wireless or absent. The
# gateway and interface go to the popup.

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

case "${SENDER:-}" in
    mouse.entered) hover_mark "$NAME" entered; popup_show "$NAME"; exit 0 ;;
    mouse.exited.global) hover_mark "$NAME" exited; sketchybar --set "$NAME" popup.drawing=off; exit 0 ;;
esac

route=$(route -n get default 2>/dev/null || true)
iface=$(awk '/interface:/ { print $2 }' <<<"$route")
gw=$(awk '/gateway:/ { print $2 }' <<<"$route")
wifi=$(networksetup -listallhardwareports \
    | awk '/Hardware Port: Wi-Fi/ { getline; print $2; exit }')

if [ -z "$iface" ] || [ "$iface" = "$wifi" ]; then
    sketchybar --set "$NAME" drawing=off
    exit 0
fi

ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
mask=$(ifconfig "$iface" 2>/dev/null | awk '/netmask/ { print $4; exit }')
cidr=""
if [ -n "$mask" ]; then
    # 0xffffff00 -> 24
    bits=$(printf '%d' "$mask")
    cidr=0
    while [ "$bits" -ne 0 ]; do
        cidr=$((cidr + (bits & 1)))
        bits=$((bits >> 1))
    done
    cidr="/$cidr"
fi

sketchybar --set "$NAME" drawing=on icon="󰈀" label="${ip:-$iface}$cidr"
popup_lines "$NAME" "$iface via ${gw:-?}"
