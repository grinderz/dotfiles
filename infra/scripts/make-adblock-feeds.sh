#!/bin/sh
# Builds the adblock custom feed file the openwrt-adblock deploy ships
# (infra/files/openwrt/etc/adblock/adblock.custom.feeds). The adblock
# package (OpenWrt, net/adblock) reads /etc/adblock/adblock.custom.feeds
# *instead of* its default adblock.feeds when the file exists, so a custom
# file has to carry the whole default list plus the extra feeds. This script
# downloads the default list of a packages branch from git.openwrt.org,
# merges the extra feeds from a small overlay (adblock.extra.feeds) on top
# and writes the result. Both inputs are validated against the 4.5.x rule
# grammar ("feed <prefix> <column> [separator]"): adblock silently drops
# feeds with an unknown rule format, which is exactly the failure this
# script exists to prevent after a package upgrade.
#
# Usage:   ./make-adblock-feeds.sh [-v] [-b branch] [-u file] [-o file] [overlay]
# Example: ./make-adblock-feeds.sh
#          ./make-adblock-feeds.sh -b master -o /tmp/adblock.custom.feeds
#
#   -b branch  packages feed branch to take the default list from
#              (default: openwrt-25.12 — match the release on the device)
#   -u file    use this local copy of the default adblock.feeds instead of
#              downloading one (offline use, tests)
#   -o file    output file (default:
#              ../files/openwrt/etc/adblock/adblock.custom.feeds relative to
#              this script)
#   -v         verbose output to stderr
#   overlay    JSON object of extra feeds in the same format as adblock.feeds
#              (default: adblock.extra.feeds next to this script). Entries
#              with a key that exists upstream replace the upstream entry.
#
# Needs curl and jq on the workstation. Nothing talks to a device: the
# pyinfra deploy openwrt-adblock ships the result (make infra.openwrt.<router>
# deploy=openwrt-adblock). Wrapped as `make openwrt.adblock-feeds`.

set -eu

SCRIPT_DIR=$(dirname "$0")

vlog() {
    if [ "${VERBOSE:-0}" = 1 ]; then
        echo "# $*" >&2
    fi
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

usage() {
    echo "Usage: $0 [-v] [-b branch] [-u file] [-o file] [overlay]" >&2
    exit 1
}

UPSTREAM_BASE="https://git.openwrt.org/feed/packages/plain/net/adblock"

VERBOSE=0
BRANCH=openwrt-25.12
UPSTREAM_FILE=
OUT="$SCRIPT_DIR/../files/openwrt/etc/adblock/adblock.custom.feeds"
while getopts "vb:u:o:" opt; do
    case $opt in
        v) VERBOSE=1 ;;
        b) BRANCH=$OPTARG ;;
        u) UPSTREAM_FILE=$OPTARG ;;
        o) OUT=$OPTARG ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -le 1 ] || usage
OVERLAY=${1:-"$SCRIPT_DIR/adblock.extra.feeds"}

command -v jq >/dev/null 2>&1 || die "jq is required"
[ -f "$OVERLAY" ] || die "overlay '$OVERLAY' not found"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Fail on anything adblock 4.5.x would not load: not a JSON object, a feed
# without url/rule/size/descr, a non-https url, or a rule that is not in
# the "feed ..." grammar (the pre-4.5 awk rules, for instance).
# $1 = label for the error, $2 = file
validate_feeds() {
    jq -e 'type == "object" and length > 0' "$2" >/dev/null 2>&1 \
        || die "$1: not a JSON object with feeds"
    bad=$(jq -r 'to_entries[]
        | select((.value | type) != "object"
            or (.value.url | type) != "string" or (.value.url | startswith("https://") | not)
            or (.value.rule | type) != "string" or (.value.rule | startswith("feed ") | not)
            or (.value.size | type) != "string"
            or (.value.descr | type) != "string")
        | .key' "$2")
    [ -z "$bad" ] || die "$1: invalid feed entries (need https url, 'feed ...' rule, size, descr):
$bad"
}

if [ -n "$UPSTREAM_FILE" ]; then
    [ -f "$UPSTREAM_FILE" ] || die "upstream file '$UPSTREAM_FILE' not found"
    vlog "default feeds from $UPSTREAM_FILE"
    cp "$UPSTREAM_FILE" "$TMP/upstream.feeds"
    version=local
else
    command -v curl >/dev/null 2>&1 || die "curl is required (or pass -u file)"
    vlog "default feeds from $UPSTREAM_BASE (branch $BRANCH)"
    curl -fsSL -o "$TMP/upstream.feeds" "$UPSTREAM_BASE/files/adblock.feeds?h=$BRANCH" \
        || die "download of adblock.feeds (branch $BRANCH) failed"
    curl -fsSL -o "$TMP/Makefile" "$UPSTREAM_BASE/Makefile?h=$BRANCH" \
        || die "download of the adblock Makefile (branch $BRANCH) failed"
    version=$(sed -n 's/^PKG_VERSION:=//p' "$TMP/Makefile")-r$(sed -n 's/^PKG_RELEASE:=//p' "$TMP/Makefile")
fi

validate_feeds "upstream adblock.feeds" "$TMP/upstream.feeds"
validate_feeds "overlay $OVERLAY" "$OVERLAY"

# extra feeds that replace an upstream entry of the same name: legitimate
# (a changed url, say) but worth knowing about
overridden=$(jq -rs '.[0] as $up | .[1] | keys[] | select($up[.] != null)' "$TMP/upstream.feeds" "$OVERLAY")
[ -z "$overridden" ] || echo "WARNING: overlay replaces upstream feeds: $(echo "$overridden" | tr '\n' ' ')" >&2

jq --tab -s '.[0] + .[1]' "$TMP/upstream.feeds" "$OVERLAY" > "$TMP/custom.feeds"

n_up=$(jq length "$TMP/upstream.feeds")
n_extra=$(jq length "$OVERLAY")
n_out=$(jq length "$TMP/custom.feeds")

mkdir -p "$(dirname "$OUT")"
if [ -f "$OUT" ] && cmp -s "$TMP/custom.feeds" "$OUT"; then
    echo "unchanged: $OUT ($n_out feeds; upstream adblock $version, $n_up feeds + $n_extra extra)"
else
    cp "$TMP/custom.feeds" "$OUT.part"
    mv "$OUT.part" "$OUT"
    echo "written: $OUT ($n_out feeds; upstream adblock $version, $n_up feeds + $n_extra extra)"
fi
