#!/bin/bash
# Compare a freshly installed system against the reference exports.
# Run on the NEW system after the full bootstrap (disk-prep +
# bootstrap + post-install + pyinfra + chezmoi). Zero output per
# section = match. bash: process substitution below.
set -u
cd "$(dirname "$0")/export" || exit 1
fail=0

section() { echo "== $1 =="; }

section "native explicit packages (missing < / extra >)"
pacman -Qqen | diff packages-native.txt - || fail=1

section "foreign (AUR) packages"
pacman -Qqem | diff packages-foreign.txt - || fail=1

section "enabled unit files"
systemctl list-unit-files --state=enabled --no-legend | awk '{print $1}' \
    | diff enabled-units.txt - || fail=1

section "flatpaks"
flatpak list --app --columns=application 2>/dev/null | diff flatpaks.txt - || fail=1

section "flatpak permission overrides"
{ for f in "$HOME"/.local/share/flatpak/overrides/*; do
    [ -f "$f" ] || continue
    printf '# user %s\n' "${f##*/}"; cat "$f"; echo
done; for f in /var/lib/flatpak/overrides/*; do
    [ -f "$f" ] || continue
    printf '# system %s\n' "${f##*/}"; cat "$f"; echo
done; } | diff flatpak-overrides.txt - || fail=1

section "btrfs subvolume mounts"
findmnt -t btrfs -rn -o TARGET,OPTIONS \
    | sed -n 's/^\([^ ]*\) .*subvol=\([^,]*\).*/\2\t\1/p' \
    | grep -v $'\t/media/' \
    | sed "s|/home/[^/]*/\.unbacked|/home/@USER@/.unbacked|" \
    | sort | diff <(cut -f1,2 subvolumes.map | sort) - || fail=1

section "subvolume mountpoint owners/permissions"
me=$(id -un)
while IFS=$'\t' read -r _ mp _; do
    rmp=${mp//@USER@/$me}
    printf '%s\t%s\n' "$(stat -c '%U:%G %a' "$rmp" 2>/dev/null || echo missing)" "$mp"
done < subvolumes.map | sed "s/\b$me\b/@USER@/g" | diff subvolume-perms.txt - || fail=1

section "subvolume parents (flat layout; needs sudo)"
# every subvolume must live at the top level (parent id 5) — the
# classic snapper trap is a .snapshots created NESTED under @ by a
# naive `snapper create-config`. Snapshots themselves legitimately
# nest under the two snapshot-storage subvolumes and are filtered out,
# and so is anything nested inside @home: those are directories taken
# out of the snapshots on purpose (unbacked-links.sh --subvol), which
# the "unbacked dead paths" section below accounts for.
if sudo -n true 2>/dev/null; then
    sudo btrfs subvolume list / | awk '{print $NF}' \
        | grep -vE '^(@snapshots|@btrbk_snapshots|@home)/' \
        | sort | diff <(cut -f1 subvolumes.map | sed 's|^/||' | grep -v '^$' | sort) - || fail=1
else
    echo "skipped (no sudo)"
fi

section "unbacked links (missing < / extra >)"
bash ../unbacked-links.sh --scan | diff unbacked-links.map - || fail=1

section "unbacked dead paths (dangling links, data without a link, lost subvolumes)"
# the backups it lists are not a fault, only what it warns about is
bash ../unbacked-links.sh --check 2>&1 | grep -vE '^(ok|backup .*)$'
[ "${PIPESTATUS[0]}" -eq 0 ] || fail=1

section "snapper + btrbk (present only after the pyinfra deploys)"
if command -v snapper > /dev/null; then
    # list-configs needs root; without a usable sudo it returns nothing and
    # a present config would read as missing
    if sudo -n true 2>/dev/null; then
        sudo -n snapper list-configs 2>/dev/null | grep -q '^root ' || { echo "no snapper root config"; fail=1; }
    else
        echo "snapper config check skipped (no sudo)"
    fi
    systemctl is-enabled snapper-cleanup.timer > /dev/null 2>&1 || { echo "snapper-cleanup.timer not enabled"; fail=1; }
fi
if [ -f /etc/btrbk/btrbk.conf ]; then
    systemctl is-enabled btrbk-snapshot.timer > /dev/null 2>&1 || { echo "btrbk-snapshot.timer not enabled"; fail=1; }
fi

section "failed units (system)"
systemctl --failed --no-legend --plain | awk '{print $1}' | grep . && fail=1

section "running boot services (hw noise expected on VMs)"
# only what default.target pulls in, the same filter as `make install.export`:
# a service started by hand, a socket, D-Bus or a device is not in the export
{ systemctl list-dependencies --all --plain --no-legend default.target | awk '{print "boot", $1}'
    systemctl list-units --type=service --state=running --no-legend --plain | awk '{print "up", $1}'; } \
    | awk '$1 == "boot" { boot[$2] = 1; next } boot[$2] { print $2 }' \
    | sort | diff running-services.txt - || fail=1

section "active timers"
systemctl list-units --type=timer --state=active --no-legend --plain \
    | awk '{print $1}' | sort | diff timers.txt - || fail=1

section "verdict"
[ $fail -eq 0 ] && echo OK || echo "DIFFS FOUND (expected on partial bootstrap: AUR/flatpak arrive late)"
exit $fail
