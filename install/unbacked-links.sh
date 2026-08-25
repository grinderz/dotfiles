#!/bin/bash
# Recreate the ~/.unbacked symlink layout from export/unbacked-links.map.
#
# /home lives on the @home subvolume, which btrbk snapshots; ~/.unbacked is
# its own subvolume (@home_unbacked in export/subvolumes.map) and is never
# snapshotted. Caches, browser profiles, toolchain stores and the maildir
# live there and are symlinked back into $HOME, so a snapshot never pins
# their churned state.
#
# export/unbacked-links.map is a dump of the reference machine, like every
# other file in export/: two tab-separated columns, both relative, so it
# carries no user name.
#
#   .config/BraveSoftware<TAB>config/BraveSoftware
#
# Refresh it with `make install.export` (which calls --scan here), and add a
# path to the layout with --add, never by editing the map by hand: --add is
# what moves the existing data out safely.
#
# On a fresh machine the mapped paths do not exist yet, so applying the map
# only creates targets under ~/.unbacked and symlinks them into place.
#
# This is not chezmoi on purpose. chezmoi applies a declaration: aiming a
# symlink_ entry at a path that still holds data makes `chezmoi apply` delete
# that data. Moving data out with a verified copy is imperative work.
#
# Deliberately not in the layout:
#
#   * ~/src — Claude Code, direnv and IDEs key their state on the physical
#     path (pwd -P), which a symlink changes; moving checkouts out needs a
#     bind mount, not a symlink
#   * ~/.local/share/calendars and ~/.local/state/vdirsyncer — kept backed on
#     purpose (top-level README): the vdirsyncer state directory holds the
#     per-account OAuth tokens, which need a browser to recreate
#   * ~/.claude/projects — session transcripts are noise, but the per-project
#     memory/ directories live inside them
#
# Usage:
#   unbacked-links.sh                       # dry run against the map
#   unbacked-links.sh --apply               # create targets and links
#   unbacked-links.sh --apply .config       # only paths under .config
#   unbacked-links.sh --scan                # dump the live layout (the map)
#   unbacked-links.sh --add .npm npm        # move a new path out, then link
#   unbacked-links.sh --apply --force       # ignore the busy-path guards
set -u

UNBACKED="$HOME/.unbacked"
MAP="$(dirname "$0")/export/unbacked-links.map"
apply=0
force=0
scan=0
add=0
filters=()
problems=0

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'warn:  %s\n' "$*" >&2; problems=$((problems + 1)); }

while [ $# -gt 0 ]; do
    case "$1" in
        --apply) apply=1 ;;
        --force) force=1 ;;
        --scan) scan=1 ;;
        --add) add=1; apply=1 ;;
        -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
        -*) die "unknown option: $1" ;;
        *) filters+=("$1") ;;
    esac
    shift
done

# --- the live layout ------------------------------------------------------

# Every symlink in $HOME that resolves into ~/.unbacked, as the map format.
# -xdev keeps the walk on @home; symlinks are never followed, so ~/.unbacked
# itself is not descended into. Depth 3 covers .local/share/<x>.
scan_layout() {
    local rel target
    cd "$HOME" || return 1
    find . -maxdepth 3 -xdev -type l -printf '%P\n' 2> /dev/null | while read -r rel; do
        target=$(readlink -f "$rel") || continue
        case "$target" in
            "$UNBACKED"/*) printf '%s\t%s\n' "$rel" "${target#"$UNBACKED"/}" ;;
        esac
    done | sort -t$'\t' -k2,2 | awk -F'\t' '
        # drop links that merely point inside an already mapped tree, e.g.
        # the uv tool shims in .local/bin reaching into .unbacked/uv
        {
            for (i = 1; i <= n; i++)
                if (index($2, kept[i] "/") == 1) next
            kept[++n] = $2
            print
        }' | sort -t$'\t' -k1,1
}

if [ "$scan" = 1 ]; then
    scan_layout
    exit 0
fi

# --- process guards -------------------------------------------------------

# One find over every /proc link, not a shell loop calling readlink per
# descriptor: same answer, 0.1s instead of two minutes.
proc_paths=
proc_scanned=0
scan_proc() {
    [ "$proc_scanned" = 1 ] && return 0
    proc_scanned=1
    proc_paths=$(
        find /proc/[0-9]*/fd /proc/[0-9]*/cwd -maxdepth 1 -type l \
            -printf '%p %l\n' 2> /dev/null \
            | awk '{
                split($1, a, "/")
                p = $2
                for (i = 3; i <= NF; i++) p = p " " $i
                print a[3], a[4], p
            }'
    )
}

# Processes whose cwd or open files sit inside a path about to be moved.
# /proc reports physical paths, so check both the path and its resolved form.
busy() {
    local dir=$1 real
    real=$(readlink -f "$dir" 2> /dev/null || echo "$dir")
    scan_proc
    printf '%s\n' "$proc_paths" | awk -v d="$dir" -v r="$real" '
        { p = $3; for (i = 4; i <= NF; i++) p = p " " $i }
        p == d || p == r || index(p, d "/") == 1 || index(p, r "/") == 1 {
            printf "  pid %s %s %s\n", $1, $2, p
        }' | sort -u
}

# --- moving and linking ---------------------------------------------------

# Byte-for-byte comparison of a finished copy: rsync in dry-run mode prints a
# line per difference, so silence means the two trees are identical.
verified() {
    local src=$1 dst=$2 out
    if [ -d "$src" ]; then
        out=$(rsync -aHAXn --delete --itemize-changes "$src/" "$dst/")
        [ -z "$out" ] && return 0
        warn "verification failed for $src:"$'\n'"$out"
        return 1
    fi
    cmp -s "$src" "$dst" && return 0
    warn "verification failed for $src"
    return 1
}

link_only() {
    local src=$1 dst=$2
    printf 'link   %s -> %s\n' "$src" "$dst"
    if [ "$apply" != 1 ]; then
        printf '  would: mkdir -p %s && ln -s %s %s\n' "$dst" "$dst" "$src"
        return 0
    fi
    # on a fresh machine neither side exists yet: ~/.config, ~/.local/share
    # and friends have to be made before a link can be dropped into them
    if ! mkdir -p "$dst" "$(dirname "$src")" || ! ln -s "$dst" "$src"; then
        warn "could not link $src"
    fi
}

move_then_link() {
    local src=$1 dst=$2 hits
    hits=$(busy "$src")
    if [ -n "$hits" ]; then
        if [ "$force" = 1 ]; then
            warn "$src is in use, --force given:"$'\n'"$hits"
        else
            warn "$src is in use, skipped (close these or pass --force):"$'\n'"$hits"
            return 1
        fi
    fi

    printf 'move   %s -> %s  (%s)\n' "$src" "$dst" "$(du -sh "$src" | cut -f1)"
    if [ "$apply" != 1 ]; then
        printf '  would: cp -a --reflink=auto, verify, rm -rf, ln -s\n'
        return 0
    fi

    if ! mkdir -p "$(dirname "$dst")"; then
        warn "could not create $(dirname "$dst")"
        return 1
    fi
    if ! cp -a --reflink=auto "$src" "$dst"; then
        warn "copy of $src failed"
        return 1
    fi
    if ! verified "$src" "$dst"; then
        warn "$src left untouched, copy is at $dst"
        return 1
    fi
    if ! rm -rf --one-file-system "$src" || ! ln -s "$dst" "$src"; then
        warn "could not link $src"
    fi
}

# One map entry: link a missing path, move an existing one, leave anything
# unexpected alone.
handle() {
    local rel=$1 sub=$2 src dst
    src="$HOME/$rel"
    dst="$UNBACKED/$sub"

    if [ -L "$src" ]; then
        # an existing link is fine as long as it resolves to the same place,
        # relative or absolute
        if [ "$(readlink -f "$src")" = "$(readlink -f "$dst" 2> /dev/null || echo "$dst")" ]; then
            [ -e "$dst" ] || warn "$src is a dangling link to $dst"
        else
            warn "$src points at $(readlink "$src"), not $dst — left alone"
        fi
        return 0
    fi

    if [ ! -e "$src" ]; then
        link_only "$src" "$dst"
        return 0
    fi

    if [ -e "$dst" ] && [ -n "$(find "$dst" -mindepth 1 -maxdepth 1 -print -quit 2> /dev/null)" ]; then
        warn "$src holds data but $dst already exists and is not empty — resolve by hand"
        return 0
    fi
    [ -d "$dst" ] && rmdir "$dst"

    move_then_link "$src" "$dst"
}

# --- main -----------------------------------------------------------------

[ -d "$UNBACKED" ] || die "$UNBACKED does not exist (disk-prep.sh creates it as a subvolume)"
command -v rsync > /dev/null || die "rsync is required for copy verification"

if [ "$add" = 1 ]; then
    [ ${#filters[@]} -eq 2 ] || die "usage: $0 --add <path under \$HOME> <path under ~/.unbacked>"
    handle "${filters[0]}" "${filters[1]}"
    [ "$problems" -gt 0 ] && exit 1
    echo "added; refresh the map with: make install.export"
    exit 0
fi

[ -f "$MAP" ] || die "$MAP not found"
[ "$apply" = 1 ] || echo "--- dry run; pass --apply to execute ---"

wanted() {
    [ ${#filters[@]} -eq 0 ] && return 0
    local f
    for f in "${filters[@]}"; do
        case "$1" in "$f"|"$f"/*) return 0 ;; esac
    done
    return 1
}

while IFS=$'\t' read -r rel sub; do
    [ -z "${rel:-}" ] && continue
    case "$rel" in \#*) continue ;; esac
    [ -n "${sub:-}" ] || die "malformed map line: $rel"
    wanted "$rel" || continue
    handle "$rel" "$sub"
done < "$MAP"

if [ "$problems" -gt 0 ]; then
    printf '\n%s entr(y|ies) need attention\n' "$problems"
    exit 1
fi
echo "done"
