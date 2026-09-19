#!/usr/bin/env bash
# close every popup when the front app or the displays change: a popup
# left up over a window one just switched to is in the way

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

popups_close
