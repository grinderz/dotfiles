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
#   * ~/src — source is what the backup is for. A single checkout that has
#     to leave does so with --subvol, never with a link: Claude Code, direnv
#     and IDEs key their state on the physical path (pwd -P), which a
#     symlink changes
#   * ~/.local/share/calendars and ~/.local/state/vdirsyncer — kept backed on
#     purpose (top-level README): the vdirsyncer state directory holds the
#     per-account OAuth tokens, which need a browser to recreate
#   * ~/.claude/projects — session transcripts are noise, but the per-project
#     memory/ directories live inside them
#
# --add and --restore take the path the way the map has it (relative to
# $HOME), as an absolute path, or starting with ./ or ../ from the current
# directory. Without a second argument --add keeps the same relative path
# under ~/.unbacked (src/work/app/.venv -> ~/.unbacked/src/work/app/.venv).
#
# Every move first clones the original to ~/.unbacked/.moved/<time>/<path>:
# a reflink, so it costs no space, and no snapshot sees it. --restore puts
# the newest such clone back in place of the link. Nothing here ever removes
# the clones, that is for whoever has seen the moved path work.
#
# --scan looks three levels deep, so a path further down (a .venv inside a
# checkout) can be moved but stays out of the map: it belongs to the
# checkout, not to the machine layout, and the map is committed.
#
# --subvol is the other way out of the snapshots, for a directory whose path
# must not change or that a container has to see: a whole checkout that is
# built in place (tools key their state on pwd -P, build output is spread
# over dozens of directories), a cache written through a bind mount. The
# directory becomes a btrfs subvolume nested where it stands. A snapshot
# does not descend into a nested subvolume, so nothing moves and nothing is
# linked. What comes with it:
#
#   * a restored snapshot of @home has an empty directory in its place
#   * rolling @home back by swapping the subvolume leaves the nested one
#     inside the old @home; move it across (a rename) before deleting that
#   * rm -rf followed by a rebuild makes a plain directory again, the same
#     way a deleted link comes back as one
#   * du -x and find -xdev stop at it, and mv across it copies
#
# Run it from outside the directory and name it by path: the directory is
# swapped for the new subvolume, and a shell standing in it would be left in
# the one that is gone. The in-use guard sees that shell and skips the path,
# so `--subvol .` always refuses.
#
# Every link and subvolume made here is written down in
# ~/.local/state/unbacked/layout ("link<TAB>path<TAB>target" or
# "subvol<TAB>path"). A link is its own record only while it exists, and a
# subvolume looks like any directory; the file is what says a path was meant
# to be out of the snapshots once it no longer is. It sits in ~/.local/state
# (the script writes it, nobody edits it) and not in ~/.unbacked, so that the
# backup holds it: after @home comes back from a snapshot the subvolumes are
# empty directories again, and only this file says which of them to convert
# before they fill up. --check holds the record against the disk and the disk
# against the record, and reports where they part:
#
#   * a link whose target is missing
#   * a recorded link that is gone, with a real directory in its place (a
#     tool deleted the link and rebuilt) or nothing at all (the checkout
#     went away), and its data still under ~/.unbacked
#   * a recorded link that points somewhere else now
#   * a recorded subvolume that is a plain directory again
#   * a link into ~/.unbacked nothing records (made with ln -s)
#   * a nested subvolume nothing records
#   * data under ~/.unbacked no link points at and nothing records
#
# It changes nothing. --forget drops the record of a path that is meant to
# stay dead; --list prints the layout without judging it.
#
# --suggest looks the other way: not at what was moved, but at what in the
# snapshotted part of $HOME might be worth moving. Two signs, neither a
# verdict:
#
#   * a directory git ignores inside a checkout, of some size: by the
#     project's own word it is not source (.venv, node_modules, build output)
#   * a directory outside the checkouts whose files changed the most over
#     the last days: a snapshot pays for change, not for size
#
# The second list names data that belongs in the backup as readily as a
# cache; --keep <path> takes a path off both lists for good (the list of
# those is ~/.local/state/unbacked/keep, --forget takes one off it again).
#
# chezmoi links this file as ~/.local/bin/unbacked, for --add and --restore
# from inside a checkout. It stays here because the map, the Makefile and
# validate.sh sit next to it, and a link into the working tree picks up an
# edit without a chezmoi apply.
#
# Usage:
#   unbacked-links.sh                       # dry run against the map
#   unbacked-links.sh --apply               # create targets and links
#   unbacked-links.sh --apply .config       # only paths under .config
#   unbacked-links.sh --scan                # dump the live layout (the map)
#   unbacked-links.sh --add .npm npm        # move a new path out, then link
#   unbacked-links.sh --add -n ./.venv      # only show what --add would do
#   unbacked-links.sh --restore ./.venv     # put the backup back, drop the link
#   unbacked-links.sh --subvol ./checkout   # make it a nested subvolume in place
#   unbacked-links.sh --list                # every link and subvolume, any depth
#   unbacked-links.sh --check               # report dead links, orphans, lost subvolumes
#   unbacked-links.sh --forget ./.venv      # drop the record of a path, touch no data
#   unbacked-links.sh --suggest             # what else might be worth moving out
#   unbacked-links.sh --keep sync/notes     # never suggest this path again
#   unbacked-links.sh --apply --force       # ignore the busy-path guards
set -u

UNBACKED="$HOME/.unbacked"
BACKUPS="$UNBACKED/.moved"
RECORD="${XDG_STATE_HOME:-$HOME/.local/state}/unbacked/layout"
KEEP="$(dirname "$RECORD")/keep"
# --suggest: how many days back "changed" looks, the size below which an
# ignored directory is not worth a line, and the change below which a
# directory outside the checkouts is not
SUGGEST_DAYS=7
SUGGEST_MIN_MB=20
SUGGEST_CHURN_MB=5
# paths under ~/.unbacked a program is pointed at directly, with no link in
# $HOME: davmail's log file (davmail.properties)
DIRECT=(davmail)
STAMP=$(date +%Y%m%d-%H%M%S)
# resolved, since $0 may be the ~/.local/bin/unbacked link
MAP="$(dirname "$(readlink -f "$0")")/export/unbacked-links.map"
apply=0
dry=0
force=0
scan=0
add=0
restore=0
subvol=0
list=0
check=0
forget=0
suggest=0
keep=0
backed=0
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
        --restore) restore=1; apply=1 ;;
        --subvol) subvol=1; apply=1 ;;
        --list) list=1 ;;
        --check) check=1 ;;
        --forget) forget=1 ;;
        --suggest) suggest=1 ;;
        --keep) keep=1 ;;
        -n|--dry-run) dry=1 ;;
        -h|--help) awk 'NR > 1 { if (!/^#/) exit; print }' "$0"; exit 0 ;;
        -*) die "unknown option: $1" ;;
        *) filters+=("$1") ;;
    esac
    shift
done
[ "$dry" = 1 ] && apply=0
[ $((scan + add + restore + subvol + list + check + forget + suggest + keep)) -le 1 ] \
    || die "--scan, --add, --restore, --subvol, --list, --check, --forget, --suggest and --keep do not go together"

# --- the record -----------------------------------------------------------

# record link <path> <target> | record subvol <path>; both relative, the
# path to $HOME and the target to ~/.unbacked. One line per path and kind.
record() {
    local line
    line=$(printf '%s\t%s' "$1" "$2")
    [ $# -ge 3 ] && line+=$'\t'$3
    mkdir -p "$(dirname "$RECORD")" || return 1
    {
        [ -f "$RECORD" ] && awk -F'\t' -v k="$1" -v r="$2" '!($1 == k && $2 == r)' "$RECORD"
        printf '%s\n' "$line"
    } | sort -u > "$RECORD.tmp" && mv "$RECORD.tmp" "$RECORD"
}

# Drop whatever is recorded for a path; true when there was something.
forget_path() {
    [ -f "$RECORD" ] || return 1
    awk -F'\t' -v r="$1" '$2 == r { found = 1 } END { exit !found }' "$RECORD" || return 1
    awk -F'\t' -v r="$1" '$2 != r' "$RECORD" > "$RECORD.tmp" && mv "$RECORD.tmp" "$RECORD"
}

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

# Comparison of a finished copy: rsync in dry-run mode prints a line per
# difference in size, mtime, mode, owner, hard links, ACLs or xattrs, so
# silence means the two trees match. It does not reread the contents; a
# single file is compared byte for byte.
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

# True when some process has the path open and --force was not given; says
# who either way.
in_use() {
    local src=$1 hits
    hits=$(busy "$src")
    [ -z "$hits" ] && return 1
    if [ "$force" = 1 ]; then
        warn "$src is in use, --force given:"$'\n'"$hits"
        return 1
    fi
    warn "$src is in use, skipped (close these or pass --force):"$'\n'"$hits"
    return 0
}

# The clone every change starts with: if it cannot be made, nothing else has
# happened yet.
keep_backup() {
    local src=$1 backup=$2
    if ! mkdir -p "$(dirname "$backup")" || ! cp -a --reflink=auto "$src" "$backup" \
        || ! verified "$src" "$backup"; then
        warn "backup of $src to $backup failed, nothing changed"
        return 1
    fi
    backed=1
    printf '  backup %s\n' "$backup"
}

move_then_link() {
    local src=$1 dst=$2 backup
    backup="$BACKUPS/$STAMP/${src#"$HOME"/}"
    printf 'move   %s -> %s  (%s)\n' "$src" "$dst" "$(du -sh "$src" | cut -f1)"
    in_use "$src" && return 1

    if [ "$apply" != 1 ]; then
        printf '  would: clone to %s, cp -a --reflink=auto, verify, rm -rf, ln -s\n' "$backup"
        return 0
    fi

    keep_backup "$src" "$backup" || return 1

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
            if [ -e "$dst" ]; then
                # a link from before the record existed gets written down here
                [ "$apply" = 1 ] && record link "$rel" "$sub"
            else
                warn "$src is a dangling link to $dst"
            fi
        else
            warn "$src points at $(readlink "$src"), not $dst — left alone"
        fi
        return 0
    fi

    if [ ! -e "$src" ]; then
        link_only "$src" "$dst"
    else
        if [ -e "$dst" ] && [ -n "$(find "$dst" -mindepth 1 -maxdepth 1 -print -quit 2> /dev/null)" ]; then
            warn "$src holds data but $dst already exists and is not empty — resolve by hand"
            return 0
        fi
        [ "$apply" = 1 ] && [ -d "$dst" ] && rmdir "$dst"

        move_then_link "$src" "$dst"
    fi
    [ "$apply" = 1 ] && [ -L "$src" ] && record link "$rel" "$sub"
    return 0
}

# --- nested subvolumes ----------------------------------------------------

# The root directory of a btrfs subvolume has inode 256 and nothing else
# does, which needs no root to read (btrfs subvolume show does).
is_subvol() {
    [ -d "$1" ] && [ ! -L "$1" ] && [ "$(stat -c %i "$1")" = 256 ] \
        && [ "$(stat -f -c %T "$1")" = btrfs ]
}

# Every subvolume nested under a directory, at any depth. -xdev stops find at
# a subvolume but still reports its root, so each one found is walked in
# turn. A mount point is a subvolume root as well, but not a nested one, and
# ~/.unbacked is never the business of this list, mounted or not.
subvols_under() {
    local p
    find "$1" -mindepth 1 -xdev -type d -inum 256 2> /dev/null | while read -r p; do
        is_subvol "$p" || continue
        [ "$p" = "$UNBACKED" ] && continue
        mountpoint -q "$p" && continue
        printf '%s\n' "$p"
        subvols_under "$p"
    done
}

# Turn a directory into a subvolume where it stands: a new subvolume next to
# it, the contents cloned across, then the two swapped by renaming.
make_subvol() {
    local rel=$1 src tmp old backup
    src="$HOME/$rel"
    if [ -L "$src" ] || [ ! -d "$src" ]; then
        warn "$src is not a directory — left alone"
        return 1
    fi
    if is_subvol "$src"; then
        printf 'subvol %s is one already\n' "$src"
        [ "$apply" = 1 ] && record subvol "$rel"
        return 0
    fi
    if [ "$(stat -f -c %T "$src")" != btrfs ]; then
        warn "$src is not on btrfs"
        return 1
    fi

    backup="$BACKUPS/$STAMP/$rel"
    printf 'subvol %s  (%s)\n' "$src" "$(du -sh "$src" | cut -f1)"
    in_use "$src" && return 1

    if [ "$apply" != 1 ]; then
        printf '  would: clone to %s, btrfs subvolume create, cp -a --reflink=auto, verify, swap the two, rm -rf the plain one\n' "$backup"
        return 0
    fi

    keep_backup "$src" "$backup" || return 1

    tmp="$src.subvol.$$"
    old="$src.plain.$$"
    if ! btrfs subvolume create "$tmp" > /dev/null; then
        warn "could not create a subvolume next to $src"
        return 1
    fi
    if ! cp -a --reflink=auto "$src/." "$tmp/" || ! verified "$src" "$tmp"; then
        rm -rf "$tmp"
        warn "copy into the new subvolume failed, $src left as it was"
        return 1
    fi
    if ! mv -T "$src" "$old"; then
        rm -rf "$tmp"
        warn "could not move $src aside, left as it was"
        return 1
    fi
    if ! mv -T "$tmp" "$src"; then
        mv -T "$old" "$src"
        warn "could not put the subvolume in place, $src put back (the subvolume is at $tmp)"
        return 1
    fi
    rm -rf --one-file-system "$old" || warn "the plain copy is left at $old"
    record subvol "$rel"
}

# --- restoring ------------------------------------------------------------

# Undo one change: the newest backup of a path goes back in its place as a
# plain directory. What was there is never deleted, since it may hold changes
# made after the backup. Behind a link that is the copy under ~/.unbacked,
# which stays where it is and has to go by hand before the path is moved
# again; a subvolume is moved next to the backups.
restore_path() {
    local rel=$1 src dst='' backup='' b tmp was_subvol=0 old aside
    src="$HOME/$rel"
    for b in "$BACKUPS"/*/; do
        [ -e "$b$rel" ] && backup=$b$rel
    done
    if [ -z "$backup" ]; then
        warn "no backup of $rel under $BACKUPS"
        return 1
    fi

    if [ -L "$src" ]; then
        dst=$(readlink -f "$src")
        case "$dst" in
            "$UNBACKED"/*) ;;
            *) warn "$src points at $dst, outside $UNBACKED — left alone"; return 1 ;;
        esac
    elif is_subvol "$src"; then
        was_subvol=1
    elif [ -e "$src" ]; then
        warn "$src is neither a link nor a subvolume and holds data — left alone"
        return 1
    fi

    printf 'restore %s <- %s  (%s)\n' "$src" "$backup" "$(du -sh "$backup" | cut -f1)"
    if [ -L "$src" ] || [ "$was_subvol" = 1 ]; then
        in_use "$src" && return 1
    fi

    if [ "$apply" != 1 ]; then
        printf '  would: cp -a --reflink=auto next to it, verify, swap it in\n'
        return 0
    fi

    # copied under a temporary name first, so what is there stays until the
    # data is back and verified
    tmp="$src.restore.$$"
    if ! mkdir -p "$(dirname "$src")" || ! cp -a --reflink=auto "$backup" "$tmp" \
        || ! verified "$backup" "$tmp"; then
        rm -rf --one-file-system "$tmp"
        warn "could not copy $backup back, $src left as it was"
        return 1
    fi

    if [ "$was_subvol" = 1 ]; then
        old="$src.subvol.$$"
        aside="$BACKUPS/$STAMP/$rel.replaced"
        if ! mv -T "$src" "$old" || ! mv -T "$tmp" "$src"; then
            warn "could not put $tmp in place of $src"
            return 1
        fi
        forget_path "$rel"
        if mkdir -p "$(dirname "$aside")" && mv -T "$old" "$aside"; then
            printf '  what the subvolume held is now at %s\n' "$aside"
        else
            warn "what the subvolume held is left at $old"
        fi
        return 0
    fi

    if { [ -L "$src" ] && ! rm "$src"; } || ! mv -T "$tmp" "$src"; then
        warn "could not put $tmp in place of $src"
        return 1
    fi
    forget_path "$rel"
    [ -n "$dst" ] && printf '  the moved copy is still at %s\n' "$dst"
    return 0
}

# --- the whole layout -----------------------------------------------------

# Every symlink that points into ~/.unbacked, at any depth, inside nested
# subvolumes too: "live<TAB>link<TAB>resolved target" or, when the target is
# gone, "dead<TAB>link<TAB>where it points". A link that merely reaches into
# an already linked tree (the uv tool shims) is left out, as in scan_layout.
layout_links() {
    local root p raw abs
    { printf '%s\n' "$HOME"; subvols_under "$HOME"; } | while read -r root; do
        find "$root" -xdev -path "$UNBACKED" -prune -o -type l -printf '%p\t%l\n' 2> /dev/null
    done | awk -F'\t' '$2 ~ /(^|\/)\.unbacked(\/|$)/' | while IFS=$'\t' read -r p raw; do
        case "$raw" in
            /*) abs=$raw ;;
            *) abs=$(dirname "$p")/$raw ;;
        esac
        abs=$(realpath -ms -- "$abs")
        case "$abs" in
            "$UNBACKED"/*) ;;
            *) continue ;;
        esac
        if [ -e "$p" ]; then
            printf 'live\t%s\t%s\n' "$p" "$(readlink -f "$p")"
        else
            printf 'dead\t%s\t%s\n' "$p" "$abs"
        fi
    done | sort -t$'\t' -k3,3 | awk -F'\t' '
        $1 == "live" {
            for (i = 1; i <= n; i++)
                if (index($3, kept[i] "/") == 1) next
            kept[++n] = $3
        }
        { print }' | sort -t$'\t' -k2,2
}

list_layout() {
    local state p t
    while IFS=$'\t' read -r state p t; do
        [ -n "$state" ] || continue
        [ "$state" = dead ] && state='dead link'
        printf '%-9s %s -> %s\n' "${state/live/link}" "${p#"$HOME"/}" "${t#"$UNBACKED"/}"
    done <<< "$(layout_links)"
    while read -r p; do
        [ -n "$p" ] && printf '%-9s %s\n' subvol "${p#"$HOME"/}"
    done <<< "$(subvols_under "$HOME")"
    for p in "${DIRECT[@]}"; do
        printf '%-9s %s\n' direct "$p"
    done
}

# Where a path under ~/.unbacked belongs in $HOME: the map knows the renamed
# ones (cache -> .cache), everything else mirrors its own path.
home_path_of() {
    local sub=${1#"$UNBACKED"/} rel=''
    [ -f "$MAP" ] && rel=$(awk -F'\t' -v s="$sub" '$2 == s { print $1; exit }' "$MAP")
    printf '%s\n' "$HOME/${rel:-$sub}"
}

# What stands in $HOME where a link should be.
home_state() {
    if [ -L "$1" ]; then
        printf '%s is a link to %s' "$1" "$(readlink "$1")"
    elif [ -e "$1" ]; then
        printf '%s is a real path again' "$1"
    elif [ -e "$(dirname "$1")" ]; then
        printf 'nothing at %s' "$1"
    else
        printf '%s is gone' "$(dirname "$1")"
    fi
}

# live, lost and above belong to check_layout: the targets of the links that
# exist, the recorded targets whose link does not, and every directory on
# the way down to either.
mark_above() {
    local e=${1%/*}
    while [ "$e" != "$UNBACKED" ] && [ -n "$e" ]; do
        above[$e]=1
        e=${e%/*}
    done
}

# Walk ~/.unbacked down to the link targets. Whatever is met on the way that
# is not one is data nothing points at.
orphans_under() {
    local dir=$1 e size
    for e in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
        [ -e "$e" ] || [ -L "$e" ] || continue
        [ "${live[$e]:-}" = 1 ] && continue
        [ "$e" = "$BACKUPS" ] && continue
        if [ -z "${lost[$e]:-}" ] && [ "${above[$e]:-}" = 1 ] && [ -d "$e" ] && [ ! -L "$e" ]; then
            orphans_under "$e"
            continue
        fi
        size=$(du -sh "$e" 2> /dev/null | cut -f1)
        if [ -n "${lost[$e]:-}" ]; then
            warn "the link to $e ($size) is lost: $(home_state "${lost[$e]}")"
        else
            warn "nothing points at $e ($size) and nothing records it: $(home_state "$(home_path_of "$e")")"
        fi
    done
}

check_layout() {
    local state p t e kind rel sub
    local -A live=() above=() lost=() known=() recorded=()

    # the record first, so that the disk can be held against it as well
    while IFS=$'\t' read -r kind rel sub; do
        case "$kind" in
            link) recorded[$HOME/$rel]="$UNBACKED/$sub" ;;
            subvol) known[$HOME/$rel]=1 ;;
        esac
    done < <(cat "$RECORD" 2> /dev/null)

    # the disk against the record: every link that is there
    while IFS=$'\t' read -r state p t; do
        [ -n "$state" ] || continue
        if [ "$state" = dead ]; then
            warn "dangling link: $p -> $t"
            continue
        fi
        live[$t]=1
        mark_above "$t"
        [ -n "${recorded[$p]:-}" ] \
            || warn "$p is a link nothing records: unbacked --add ${p#"$HOME"/} ${t#"$UNBACKED"/} writes it down"
    done <<< "$(layout_links)"
    for e in "${DIRECT[@]}"; do
        live[$UNBACKED/$e]=1
        mark_above "$UNBACKED/$e"
    done

    # the record against the disk: every link and subvolume it names
    while read -r p; do
        [ -n "$p" ] || continue
        t=${recorded[$p]}
        [ "${live[$t]:-}" = 1 ] && continue
        if [ -e "$t" ]; then
            # reported by the walk below, next to the data it left behind
            lost[$t]=$p
            mark_above "$t"
        elif [ -L "$p" ] && [ -e "$p" ]; then
            warn "$p is recorded as a link to $t, which is gone, and points at $(readlink -f "$p") (--add records that instead)"
        elif [ ! -L "$p" ]; then
            # a link left dangling was reported above already
            warn "the recorded link $p is gone and so is its data at $t (--forget drops the record)"
        fi
    done <<< "$(printf '%s\n' "${!recorded[@]}" | sort)"
    while read -r p; do
        [ -n "$p" ] || continue
        if is_subvol "$p"; then
            :
        elif [ -e "$p" ]; then
            warn "$p was made a subvolume and is a plain directory again: the snapshots hold it"
        else
            warn "the recorded subvolume $p is gone (--forget drops the record)"
        fi
    done <<< "$(printf '%s\n' "${!known[@]}" | sort)"

    orphans_under "$UNBACKED"

    while read -r p; do
        [ -n "$p" ] || continue
        [ "${known[$p]:-}" = 1 ] \
            || warn "$p is a subvolume nothing records: no snapshot holds it (--subvol records it)"
    done <<< "$(subvols_under "$HOME")"

    for e in "$BACKUPS"/*/; do
        [ -d "$e" ] || continue
        printf 'backup %s  (%s)\n' "${e%/}" "$(du -sh "$e" 2> /dev/null | cut -f1)"
    done
}

# --- suggesting -----------------------------------------------------------

# True for a path the user said stays in the backup, and for anything under it.
is_kept() {
    [ -f "$KEEP" ] || return 1
    awk -v p="$1" '$0 == p || index(p, $0 "/") == 1 { found = 1 } END { exit !found }' "$KEEP"
}

# Megabytes in the files under a directory that changed within SUGGEST_DAYS.
changed_mb() {
    find "$1" -xdev -type f -mtime "-$SUGGEST_DAYS" -printf '%s\n' 2> /dev/null \
        | awk '{ s += $1 } END { printf "%d", s / 1048576 }'
}

# What in the snapshotted part of $HOME might be worth moving out. -xdev
# keeps the walk off ~/.unbacked and out of the nested subvolumes, which are
# outside the snapshots already; a link is never followed.
suggest_paths() {
    local repos r entry abs rel mb key note

    repos=$(find "$HOME" -xdev -path "$UNBACKED" -prune -o -name .git -printf '%h\n' -prune \
        2> /dev/null | sort)

    printf 'ignored by git inside a checkout, %sM or more (size, changed in %s days):\n' \
        "$SUGGEST_MIN_MB" "$SUGGEST_DAYS"
    while read -r r; do
        [ -n "$r" ] || continue
        while IFS= read -r -d '' entry; do
            # a directory git ignores as a whole: "!! path/"
            case "$entry" in '!! '*/) ;; *) continue ;; esac
            abs="$r/${entry#'!! '}"
            abs=${abs%/}
            [ -L "$abs" ] && continue
            # a nested subvolume is out of the snapshots already
            is_subvol "$abs" && continue
            # a checkout inside a checkout is source, whatever the outer one says
            [ -e "$abs/.git" ] && continue
            rel=${abs#"$HOME"/}
            is_kept "$rel" && continue
            mb=$(du -sxm --apparent-size "$abs" 2> /dev/null | cut -f1)
            [ "${mb:-0}" -ge "$SUGGEST_MIN_MB" ] || continue
            # ignored as a whole, yet somebody's work may sit further down
            note=''
            [ -n "$(find "$abs" -mindepth 2 -name .git -print -quit 2> /dev/null)" ] \
                && note='  (holds a checkout)'
            printf '%s\t%s\t%s%s\n' "$mb" "$(changed_mb "$abs")" "$rel" "$note"
        done < <(git -C "$r" status --porcelain --ignored -z 2> /dev/null)
    done <<< "$repos" | sort -t$'\t' -k1,1nr \
        | awk -F'\t' '{ printf "  %6sM  %5sM  %s\n", $1, $2, $3 } END { if (!NR) print "  nothing" }'

    printf '\noutside the checkouts, changed by %sM or more in %s days (changed, size):\n' \
        "$SUGGEST_CHURN_MB" "$SUGGEST_DAYS"
    # files are summed under the first three levels of their path, which is
    # where a program keeps a tree of its own (.local/state/<program>)
    find "$HOME" -xdev -path "$UNBACKED" -prune -o -type f -mtime "-$SUGGEST_DAYS" -printf '%s\t%P\n' \
        2> /dev/null | awk -F'\t' -v home="$HOME" -v min="$((SUGGEST_CHURN_MB * 1048576))" '
        FNR == NR { if ($0 != "") repo[++m] = substr($0, length(home) + 2) "/"; next }
        {
            for (i = 1; i <= m; i++)
                if (index($2, repo[i]) == 1) next
            k = split($2, c, "/")
            if (k < 2) next
            key = c[1]
            for (i = 2; i < k && i <= 3; i++) key = key "/" c[i]
            sum[key] += $1
        }
        END {
            for (key in sum)
                if (sum[key] >= min) printf "%d\t%s\n", sum[key] / 1048576, key
        }' <(printf '%s\n' "$repos") - | sort -t$'\t' -k1,1nr | while IFS=$'\t' read -r mb key; do
        is_kept "$key" && continue
        printf '  %6sM  %5sM  %s\n' "$mb" \
            "$(du -sxm --apparent-size "$HOME/$key" 2> /dev/null | cut -f1)" "$key"
    done | awk '{ print } END { if (!NR) print "  nothing" }'

    printf '\nunbacked --add <path> moves one out, --subvol when a container or pwd -P has to see it;\n'
    printf 'unbacked --keep <path> stops naming one that stays in the backup on purpose.\n'
}

# --- main -----------------------------------------------------------------

[ -d "$UNBACKED" ] || die "$UNBACKED does not exist (disk-prep.sh creates it as a subvolume)"
command -v rsync > /dev/null || die "rsync is required for copy verification"

# A path from the command line, made relative to $HOME without resolving
# symlinks: after a move the path itself is one.
home_rel() {
    local p=$1
    case "$p" in
        /*) ;;
        . | .. | ./* | ../*) p=$PWD/$p ;;
        *) p=$HOME/$p ;;
    esac
    p=$(realpath -ms -- "$p") || return 1
    case "$p" in
        "$UNBACKED" | "$UNBACKED"/*) return 1 ;;
        "$HOME"/*) printf '%s\n' "${p#"$HOME"/}" ;;
        *) return 1 ;;
    esac
}

if [ "$list" = 1 ]; then
    list_layout
    exit 0
fi

if [ "$check" = 1 ]; then
    check_layout
    if [ "$problems" -gt 0 ]; then
        printf '\n%s finding(s)\n' "$problems"
        exit 1
    fi
    echo "ok"
    exit 0
fi

if [ "$suggest" = 1 ]; then
    suggest_paths
    exit 0
fi

if [ "$keep" = 1 ]; then
    [ ${#filters[@]} -eq 1 ] || die "usage: $0 --keep <path>"
    rel=$(home_rel "${filters[0]}") \
        || die "${filters[0]} is not a path under \$HOME outside ~/.unbacked"
    mkdir -p "$(dirname "$KEEP")" || exit 1
    { cat "$KEEP" 2> /dev/null; printf '%s\n' "$rel"; } | sort -u > "$KEEP.tmp" && mv "$KEEP.tmp" "$KEEP"
    echo "kept $rel: --suggest will not name it"
    exit 0
fi

if [ "$forget" = 1 ]; then
    [ ${#filters[@]} -eq 1 ] || die "usage: $0 --forget <path>"
    rel=$(home_rel "${filters[0]}") \
        || die "${filters[0]} is not a path under \$HOME outside ~/.unbacked"
    dropped=0
    forget_path "$rel" && dropped=1
    if grep -qxF -- "$rel" "$KEEP" 2> /dev/null; then
        grep -vxF -- "$rel" "$KEEP" > "$KEEP.tmp"
        mv "$KEEP.tmp" "$KEEP"
        dropped=1
    fi
    [ "$dropped" = 1 ] || die "nothing is recorded or kept for $rel"
    echo "forgot $rel; its data is untouched"
    exit 0
fi

if [ "$add" = 1 ] || [ "$restore" = 1 ] || [ "$subvol" = 1 ]; then
    if [ "$add" = 1 ]; then
        [ ${#filters[@]} -eq 1 ] || [ ${#filters[@]} -eq 2 ] \
            || die "usage: $0 --add [-n] <path> [<path under ~/.unbacked>]"
    elif [ "$subvol" = 1 ]; then
        [ ${#filters[@]} -eq 1 ] || die "usage: $0 --subvol [-n] <directory>"
    else
        [ ${#filters[@]} -eq 1 ] || die "usage: $0 --restore [-n] <path>"
    fi
    rel=$(home_rel "${filters[0]}") \
        || die "${filters[0]} is not a path under \$HOME outside ~/.unbacked"
    [ "$apply" = 1 ] || echo "--- dry run; nothing is touched ---"

    if [ "$restore" = 1 ]; then
        restore_path "$rel"
        [ "$problems" -gt 0 ] && exit 1
        [ "$apply" = 1 ] && echo "restored"
        exit 0
    fi

    if [ "$subvol" = 1 ]; then
        make_subvol "$rel"
        [ "$problems" -gt 0 ] && exit 1
        [ "$apply" = 1 ] || exit 0
        [ "$backed" = 1 ] && echo "backup kept under $BACKUPS/$STAMP, remove it once the path is known to work"
        echo "now a subvolume, recorded in $RECORD"
        exit 0
    fi

    sub=${filters[1]:-$rel}
    sub=${sub%/}
    case "$sub" in
        /* | .. | ../* | */.. | */../* | .moved | .moved/*)
            die "$sub is not a path under ~/.unbacked" ;;
    esac
    handle "$rel" "$sub"
    [ "$problems" -gt 0 ] && exit 1
    [ "$apply" = 1 ] || exit 0
    [ "$backed" = 1 ] && echo "backup kept under $BACKUPS/$STAMP, remove it once the path is known to work"
    case "$rel" in
        */*/*/*) echo "added; deeper than --scan looks, so it stays out of the map" ;;
        *) echo "added; refresh the map with: make install.export" ;;
    esac
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

[ "$backed" = 1 ] && echo "backups kept under $BACKUPS/$STAMP, remove them once the paths are known to work"
if [ "$problems" -gt 0 ]; then
    printf '\n%s entr(y|ies) need attention\n' "$problems"
    exit 1
fi
echo "done"
