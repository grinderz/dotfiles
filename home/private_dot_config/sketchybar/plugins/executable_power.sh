#!/usr/bin/env bash
# waybar's power menu: a click on the button offers sleep, restart, shut
# down, log out and lock through menu-pick (the AppleScript list dialog
# here); restart/shut down go through System Events so the apps get the
# usual chance to save.

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

[ "${SENDER:-}" = mouse.clicked ] || exit 0

choice=$(printf '%s\n' lock sleep restart "shut down" "log out" \
    | menu-pick --prompt=power) || exit 0

case "$choice" in
    lock) osascript -e 'tell application "System Events" to keystroke "q" using {command down, control down}' ;;
    sleep) pmset sleepnow ;;
    restart) osascript -e 'tell application "System Events" to restart' ;;
    "shut down") osascript -e 'tell application "System Events" to shut down' ;;
    "log out") osascript -e 'tell application "System Events" to log out' ;;
esac
