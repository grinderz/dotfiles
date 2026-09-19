#!/usr/bin/env bash
# sway/window: title of the focused window (the app name is in most
# titles anyway, and the centered label has little room on the builtin
# screen)

set -euo pipefail

label="$(aerospace list-windows --focused \
    --format '%{window-title}' 2>/dev/null || true)"
# no focused window (empty workspace): fall back to the app sketchybar saw
if [ -z "$label" ] && [ "${SENDER:-}" = "front_app_switched" ]; then
    label="${INFO:-}"
fi

sketchybar --set front_app label="$label" --set front_app.small label="$label"
