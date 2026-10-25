#!/bin/sh
# Test of make-adblock-feeds.sh against a fake upstream list: no network,
# no device. The merge, the override warning, the unchanged re-run, the
# refusals (awk rules, http urls, broken JSON, usage errors) and the
# consistency of the shipped feed file with the overlay.
#
# Usage: infra/scripts/tests/make-adblock-feeds.sh    (from any cwd; make test)
set -eu

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
GEN="$SCRIPTS/make-adblock-feeds.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# $1 = file, $2 = expected count, $3 = grep pattern
expect_count() {
    n=$(grep -c -- "$3" "$1" || :)
    [ "$n" = "$2" ] || fail "expected $2 lines matching '$3', got $n:
$(cat "$1")"
}

echo "== merge"
cat > "$TMP/upstream.feeds" <<'JSON'
{ "adguard": { "url": "https://example.org/a.txt", "rule": "feed || 3 [|^]", "size": "L", "descr": "general" },
  "yoyo":    { "url": "https://example.org/y.txt", "rule": "feed 1", "size": "S", "descr": "general" } }
JSON
cat > "$TMP/extra.feeds" <<'JSON'
{ "yoyo":  { "url": "https://example.org/y2.txt", "rule": "feed 1", "size": "S", "descr": "replaced" },
  "hosts": { "url": "https://example.org/h.txt", "rule": "feed 0.0.0.0 2", "size": "M", "descr": "extra" } }
JSON
"$GEN" -u "$TMP/upstream.feeds" -o "$TMP/out/custom.feeds" "$TMP/extra.feeds" > "$TMP/out.txt" 2> "$TMP/err.txt" \
    || fail "generator exited $?: $(cat "$TMP/err.txt")"
expect_count "$TMP/out.txt" 1 '^written: .*/out/custom.feeds (3 feeds; upstream adblock local, 2 feeds + 2 extra)$'
expect_count "$TMP/err.txt" 1 '^WARNING: overlay replaces upstream feeds: yoyo $'
[ "$(jq -r '[.adguard.rule, .yoyo.url, .hosts.rule] | join("|")' "$TMP/out/custom.feeds")" = "feed || 3 [|^]|https://example.org/y2.txt|feed 0.0.0.0 2" ] \
    || fail "merged feeds are wrong: $(cat "$TMP/out/custom.feeds")"

echo "== unchanged re-run"
"$GEN" -u "$TMP/upstream.feeds" -o "$TMP/out/custom.feeds" "$TMP/extra.feeds" > "$TMP/out.txt" 2>/dev/null || fail "re-run exited $?"
expect_count "$TMP/out.txt" 1 '^unchanged: '

echo "== refusals"
# pre-4.5 awk rules and plain http urls: adblock would drop such feeds silently
cat > "$TMP/old.feeds" <<'JSON'
{ "old": { "url": "https://example.org/o.txt", "rule": "/^0\\.0\\.0\\.0[[:space:]]+/{print tolower($2)}", "size": "M", "descr": "awk rule" } }
JSON
"$GEN" -u "$TMP/upstream.feeds" -o "$TMP/out/bad.feeds" "$TMP/old.feeds" >/dev/null 2>&1 && fail "accepted an awk rule"
echo '{ "plain": { "url": "http://example.org/p.txt", "rule": "feed 1", "size": "S", "descr": "http" } }' > "$TMP/http.feeds"
"$GEN" -u "$TMP/upstream.feeds" -o "$TMP/out/bad.feeds" "$TMP/http.feeds" >/dev/null 2>&1 && fail "accepted an http url"
"$GEN" -u "$TMP/old.feeds" -o "$TMP/out/bad.feeds" "$TMP/extra.feeds" >/dev/null 2>&1 && fail "accepted an upstream file with awk rules"
echo 'not json' > "$TMP/broken.feeds"
"$GEN" -u "$TMP/upstream.feeds" -o "$TMP/out/bad.feeds" "$TMP/broken.feeds" >/dev/null 2>&1 && fail "accepted a non-JSON overlay"
[ ! -e "$TMP/out/bad.feeds" ] || fail "a refused run wrote an output file"
"$GEN" -u "$TMP/upstream.feeds" a b >/dev/null 2>&1 && fail "accepted two overlays"
"$GEN" -u "$TMP/upstream.feeds" "$TMP/missing.feeds" >/dev/null 2>&1 && fail "ran with a missing overlay"

echo "== shipped feed file carries the overlay"
# a forgotten regeneration after editing adblock.extra.feeds would otherwise go unnoticed
SHIPPED="$SCRIPTS/../files/openwrt/etc/adblock/adblock.custom.feeds"
[ "$(jq -S . "$SCRIPTS/adblock.extra.feeds")" = "$(jq -S --slurpfile x "$SCRIPTS/adblock.extra.feeds" 'with_entries(select(.key as $k | $x[0] | has($k)))' "$SHIPPED")" ] \
    || fail "$SHIPPED is out of date, run make openwrt.adblock-feeds"

echo "OK"
