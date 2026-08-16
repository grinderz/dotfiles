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
# nest under the two snapshot-storage subvolumes and are filtered out.
if sudo -n true 2>/dev/null; then
    sudo btrfs subvolume list / | awk '{print $NF}' \
        | grep -vE '^(@snapshots|@btrbk_snapshots)/' \
        | sort | diff <(cut -f1 subvolumes.map | sed 's|^/||' | grep -v '^$' | sort) - || fail=1
else
    echo "skipped (no sudo)"
fi

section "snapper + btrbk (present only after the pyinfra deploys)"
if command -v snapper > /dev/null; then
    sudo snapper list-configs 2>/dev/null | grep -q '^root ' || { echo "no snapper root config"; fail=1; }
    systemctl is-enabled snapper-cleanup.timer > /dev/null 2>&1 || { echo "snapper-cleanup.timer not enabled"; fail=1; }
fi
if [ -f /etc/btrbk/btrbk.conf ]; then
    systemctl is-enabled btrbk-snapshot.timer > /dev/null 2>&1 || { echo "btrbk-snapshot.timer not enabled"; fail=1; }
fi

section "failed units (system)"
systemctl --failed --no-legend --plain | awk '{print $1}' | grep . && fail=1

section "running services (hw/session noise expected on VMs)"
systemctl list-units --type=service --state=running --no-legend --plain \
    | awk '{print $1}' | sort | diff running-services.txt - || fail=1

section "active timers"
systemctl list-units --type=timer --state=active --no-legend --plain \
    | awk '{print $1}' | sort | diff timers.txt - || fail=1

section "verdict"
[ $fail -eq 0 ] && echo OK || echo "DIFFS FOUND (expected on partial bootstrap: AUR/flatpak arrive late)"
exit $fail
