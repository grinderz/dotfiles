#!/usr/bin/env bash
# click_script helper: left button runs the first command, right button
# the second (waybar's on-click / on-click-right); both are shell strings

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

case "${BUTTON:-left}" in
    right) bash -c "${2:-true}" ;;
    *) bash -c "$1" ;;
esac
