#!/usr/bin/env bash
# The wireless link (waybar's network#wifi), hidden while disconnected.
#
# macOS 14.4+ hands the SSID only to processes with Location Services
# access, which a launchd-started bar does not have and cannot ask for:
# `ipconfig getsummary`, `networksetup -getairportnetwork` and
# system_profiler all answer "<redacted>". Signal and channel still come
# through, so the label carries the signal strength and the SSID only
# joins it on the machines where it is readable.
#
# system_profiler takes ~2.5 s, far too slow for a 30 s tick, so its
# answer is cached and refreshed only when the link may have changed
# (wifi_change, system_woke, hover) or when the cache goes stale.

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

cache="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar/wifi.json"
ttl=300

iface=$(networksetup -listallhardwareports \
    | awk '/Hardware Port: Wi-Fi/ { getline; print $2; exit }')
iface=${iface:-en0}

# env.sh puts GNU coreutils first in PATH, so `stat` may be either one:
# -c is GNU, -f is BSD, and the wrong flag prints nonsense instead of a
# timestamp
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# the current network as system_profiler sees it, from cache unless the
# caller wants it fresh
snapshot() {
    local force=${1:-0} age=$ttl
    mkdir -p "${cache%/*}"
    [ -f "$cache" ] && age=$(( $(date +%s) - $(mtime "$cache") ))
    if [ "$force" = 1 ] || [ ! -s "$cache" ] || [ "$age" -ge "$ttl" ]; then
        system_profiler SPAirPortDataType -json 2>/dev/null \
            | jq -c '.SPAirPortDataType[0].spairport_airport_interfaces[0]
                     .spairport_current_network_information // {}' >"$cache.tmp" 2>/dev/null \
            && mv "$cache.tmp" "$cache"
    fi
    cat "$cache" 2>/dev/null || echo '{}'
}

# "-63 dBm / -89 dBm" -> 74 (the usual 2*(rssi+100), clamped)
signal_pct() {
    local rssi=${1%% *}
    rssi=${rssi#-}
    [ -n "$rssi" ] || return 1
    local pct=$(( 2 * (100 - rssi) ))
    [ "$pct" -gt 100 ] && pct=100
    [ "$pct" -lt 0 ] && pct=0
    echo "$pct"
}

case "${SENDER:-}" in
    mouse.entered)
        hover_mark "$NAME" entered
        net=$(snapshot 1)
        ssid=$(jq -r '._name // ""' <<<"$net")
        noise=$(jq -r '.spairport_signal_noise // ""' <<<"$net")
        channel=$(jq -r '.spairport_network_channel // ""' <<<"$net")
        mode=$(jq -r '.spairport_network_phymode // ""' <<<"$net")
        ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
        rows=("$iface  ${ip:-no address}")
        case "$ssid" in
            "" | "<redacted>") rows+=("ssid hidden by macOS (no Location Services)") ;;
            *) rows+=("$ssid") ;;
        esac
        [ -n "$noise" ] && rows+=("$noise")
        [ -n "$channel" ] && rows+=("ch $channel${mode:+  $mode}")
        popup_lines "$NAME" "${rows[@]}"
        popup_show "$NAME"
        exit 0 ;;
    mouse.exited.global)
        hover_mark "$NAME" exited
        sketchybar --set "$NAME" popup.drawing=off
        exit 0 ;;
esac

# a link change is exactly when the cached snapshot is worth redoing
force=0
case "${SENDER:-}" in wifi_change | system_woke | forced) force=1 ;; esac
net=$(snapshot "$force")

ssid=$(jq -r '._name // ""' <<<"$net")
noise=$(jq -r '.spairport_signal_noise // ""' <<<"$net")

if [ -z "$noise" ] && [ -z "$ssid" ]; then
    sketchybar --set "$NAME" drawing=off
    exit 0
fi

label=""
case "$ssid" in
    "" | "<redacted>") ;;
    *) label="$ssid" ;;
esac
if pct=$(signal_pct "$noise"); then
    # with the name hidden the percentage is the label, not a footnote
    if [ -n "$label" ]; then label="$label ($pct%)"; else label="$pct%"; fi
fi

sketchybar --set "$NAME" drawing=on icon="" label="${label:-on}"
