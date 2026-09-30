#!/bin/bash
# Compare the mac against export/mac/: mac-export.sh is run into a temporary
# directory and every file diffed against the committed one, so a missing
# formula shows as `<` and an extra one as `>`, the same way validate.sh
# reads on linux. Zero output per section = match; non-zero exit = at least
# one section differed.
set -u
[ "$(uname -s)" = Darwin ] || { echo "error: this runs on the mac" >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bash "$here/mac-export.sh" "$tmp" > /dev/null
fail=0
for f in Brewfile brew-services.txt launch-agents.txt applications.txt macos-version.txt; do
    echo "== $f (missing < / extra >) =="
    diff "$here/export/mac/$f" "$tmp/$f" || fail=1
done
echo "== verdict =="
[ $fail -eq 0 ] && echo OK || echo "DIFFS FOUND"
exit $fail
