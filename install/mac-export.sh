#!/bin/bash
# What the mac has installed, dumped into export/mac/ as the reference for a
# fresh one: the counterpart of `make install.export` on linux. Runs on the
# mac; the files are plain text, so linux commits them after a pull or a copy.
#
#   Brewfile           brew bundle dump: taps, formulae, casks, go and uv tools
#   brew-services.txt  the brew services meant to be running
#   launch-agents.txt  ~/Library/LaunchAgents, to notice what third parties add
#   applications.txt   /Applications by origin: a cask, the App Store (a
#                      receipt inside the bundle) or by hand
#   macos-version.txt  release and architecture
#
# mac-validate.sh runs this into a temporary directory and diffs the two.
set -euo pipefail
[ "$(uname -s)" = Darwin ] || { echo "error: this runs on the mac" >&2; exit 1; }
out=${1:-$(cd "$(dirname "$0")" && pwd)/export/mac}
mkdir -p "$out"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" HOMEBREW_NO_AUTO_UPDATE=1

brew bundle dump --file="$out/Brewfile" --force --no-describe --no-vscode

brew services list | awk 'NR > 1 && $2 == "started" { print $1 }' | sort > "$out/brew-services.txt"

(cd ~/Library/LaunchAgents && find . -mindepth 1 -maxdepth 1 | sed 's|^\./||' | sort) > "$out/launch-agents.txt"

# app bundle -> cask token, from the app artifacts of the installed casks
# (a plain name, or an object naming the target it is installed as)
casks=$(brew info --json=v2 --installed --cask | jq -r '
    .casks[] | .token as $t | .artifacts[]? | .app[]?
    | (if type == "string" then . else (.target // empty) end)
    | "\(. | split("/") | last)\t\($t)"')
tokens=$(brew list --cask)
for app in /Applications/*.app; do
    name=$(basename "$app")
    token=$(printf '%s\n' "$casks" | awk -F'\t' -v n="$name" '$1 == n { print $2; exit }')
    # a cask that installs a pkg lists no app artifact (karabiner-elements,
    # sf-symbols): its token is the app name in cask spelling
    if [ -z "$token" ]; then
        guess=$(printf '%s' "${name%.app}" | tr '[:upper:] ' '[:lower:]-')
        printf '%s\n' "$tokens" | grep -qx -- "$guess" && token=$guess
    fi
    if [ -n "$token" ]; then
        origin="cask $token"
    elif [ -d "$app/Contents/_MASReceipt" ]; then
        origin="appstore"
    else
        origin="manual"
    fi
    printf '%s\t%s\n' "$origin" "$name"
done | sort -t$'\t' -k1,1 -k2,2 > "$out/applications.txt"

{ sw_vers -productVersion; uname -m; } | paste -sd' ' - > "$out/macos-version.txt"

echo "exported to $out"
wc -l "$out"/* | sed "s|$out/||"
