#!/usr/bin/env bash
# current input source as a flag like waybar's sway/language ({flag}), a
# short tag for anything unmapped. The source id comes with the
# input_source_change event (input-source-watch, no polling); the first
# run and the slow fallback poll read the HIToolbox preferences instead.

set -euo pipefail

if [ "${SENDER:-}" = "input_source_change" ] && [ -n "${INPUT_SOURCE:-}" ]; then
    # com.apple.keylayout.Russian -> Russian
    src="${INPUT_SOURCE##*.}"
else
    src="$(defaults read ~/Library/Preferences/com.apple.HIToolbox.plist \
        AppleSelectedInputSources 2>/dev/null \
        | awk -F'"' '/KeyboardLayout Name/ { print $4; exit }')"
    src="${src:-$(defaults read ~/Library/Preferences/com.apple.HIToolbox.plist \
        AppleSelectedInputSources 2>/dev/null \
        | awk -F'= ' '/KeyboardLayout Name/ { gsub(/[";]/, "", $2); print $2; exit }')}"
fi

case "$src" in
    ABC|U.S.*|US*) tag="🇺🇸" ;;
    Russian*) tag="🇷🇺" ;;
    "") tag="" ;;
    *) tag="$(printf '%s' "$src" | tr '[:upper:]' '[:lower:]' | cut -c1-3)" ;;
esac

sketchybar --set "$NAME" label="$tag"
