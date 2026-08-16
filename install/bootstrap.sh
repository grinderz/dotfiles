#!/bin/sh
# Base install onto the tree disk-prep.sh mounted at /mnt: pacstrap the
# exported package set, fstab, locale/tz/hostname, user, mkinitcpio
# template, limine EFI fallback binary. Everything above the base comes
# from pyinfra + chezmoi after the first reboot; the AUR limine hook and
# the final initramfs build happen in post-install.sh.
#
# Usage (arch ISO, after disk-prep.sh):
#   NEW_USER=someuser NEW_HOSTNAME=somehost TIMEZONE=Europe/London ./bootstrap.sh
set -eu
cd "$(dirname "$0")"

: "${NEW_USER:?}"
: "${NEW_HOSTNAME:?}"
: "${TIMEZONE:?}"
MNT=${MNT:-/mnt}
# minimal (default): just enough to boot and run the pyinfra/chezmoi
# bootstrap; full: the complete exported package set of the reference
# machine (PKG_SET=full)
PKG_SET=${PKG_SET:-minimal}
case "$PKG_SET" in
    minimal) PKG_FILE=export/packages-minimal.txt ;;
    full)    PKG_FILE=export/packages-native.txt ;;
    *) echo "error: PKG_SET must be minimal or full" >&2; exit 1 ;;
esac

findmnt "$MNT" > /dev/null || { echo "error: nothing mounted at $MNT (run disk-prep.sh)" >&2; exit 1; }

# filesystem- and encryption-specific packages, derived from what
# disk-prep actually built (only relevant for the minimal set — the
# full reference set carries them anyway, pacstrap dedupes)
root_fstype=$(findmnt -no FSTYPE "$MNT")
extra_pkgs=""
case "$root_fstype" in
    btrfs) extra_pkgs="btrfs-progs snapper snap-pac" ;;
    ext4)  extra_pkgs="e2fsprogs" ;;
esac
root_src=$(findmnt -no SOURCE "$MNT" | sed 's/\[.*//')
[ "$root_src" = /dev/mapper/root ] && extra_pkgs="$extra_pkgs cryptsetup"

# shellcheck disable=SC2046,SC2086  # word splitting is the point
pacstrap -K "$MNT" $(grep -v '^#' "$PKG_FILE") $extra_pkgs

genfstab -U "$MNT" >> "$MNT/etc/fstab"

install -m 644 mkinitcpio.conf.template "$MNT/etc/mkinitcpio.conf"
if [ "$root_fstype" != btrfs ]; then
    # overlayfs-on-snapshot boot only exists for btrfs
    sed -i 's/ sd-btrfs-overlayfs//' "$MNT/etc/mkinitcpio.conf"
fi

# First-boot kernel cmdline: limine-mkinitcpio (post-install) reads
# /etc/default/limine; without it the generated entries have no root=.
# Derived from what disk-prep actually mounted (LUKS or plain, btrfs or
# ext4); the LUKS+btrfs shape matches the pyinfra limine template,
# which converges the file on the first deploy.
rootflags=""
[ "$root_fstype" = btrfs ] && rootflags=" rootflags=subvol=@"
if [ "$root_src" = /dev/mapper/root ]; then
    luks_dev=$(cryptsetup status root | awk '/device:/ {print $2}')
    luks_uuid=$(blkid -s UUID -o value "$luks_dev")
    cmdline="root=/dev/mapper/root cryptdevice=UUID=$luks_uuid:root rd.luks.name=$luks_uuid=root rd.luks.options=$luks_uuid=fido2-device=auto$rootflags zswap.enabled=0 rw"
else
    cmdline="root=UUID=$(blkid -s UUID -o value "$root_src")$rootflags zswap.enabled=0 rw"
fi
{
    echo 'ENABLE_LIMINE_FALLBACK=yes'
    echo "KERNEL_CMDLINE[default]+=\"$cmdline\""
    [ "$root_fstype" = btrfs ] && echo 'ROOT_SNAPSHOTS_PATH="/@snapshots"'
} > "$MNT/etc/default/limine"

# First-boot network: the pyinfra network deploy replaces this later,
# but it cannot run without a link — wired DHCP until then
mkdir -p "$MNT/etc/systemd/network"
printf '[Match]\nName=en*\n\n[Network]\nDHCP=yes\n' > "$MNT/etc/systemd/network/99-bootstrap-dhcp.network"
arch-chroot "$MNT" systemctl enable systemd-networkd systemd-resolved
# sshd too: the rest of the bootstrap (pyinfra) is usually driven from
# another machine; key-only lockdown arrives with the sshd deploy
arch-chroot "$MNT" systemctl enable sshd
ln -sf /run/systemd/resolve/stub-resolv.conf "$MNT/etc/resolv.conf"

# encrypted /home on a second disk unlocks via crypttab (the root
# passphrase is asked by the initramfs, this one by systemd at boot)
if [ -e /dev/mapper/home ]; then
    home_dev=$(cryptsetup status home | awk '/device:/ {print $2}')
    echo "home UUID=$(blkid -s UUID -o value "$home_dev") none luks" >> "$MNT/etc/crypttab"
fi

# limine loads via the EFI fallback path — no NVRAM entry needed, which
# is exactly what lets the mirror stick boot on any machine
install -D -m 644 "$MNT/usr/share/limine/BOOTX64.EFI" "$MNT/boot/EFI/BOOT/BOOTX64.EFI"

arch-chroot "$MNT" /bin/sh -eu <<EOF
# btrfs layout only: the subvolume mountpoints disk-prep created
# predate pacstrap, and pacman does not fix modes/owners of
# pre-existing dirs ("directory permissions differ" warnings);
# /.snapshots matches snapper's 750. On ext4 pacstrap creates these
# dirs itself with correct permissions.
if [ "$root_fstype" = btrfs ]; then
    chmod 750 /root /.snapshots
    chown root:games /var/games && chmod 775 /var/games
    chmod 775 /var/lib/AccountsService
fi
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'KEYMAP=us' > /etc/vconsole.conf
echo '$NEW_HOSTNAME' > /etc/hostname
useradd -m -G wheel -s /usr/bin/bash '$NEW_USER'
# disk-prep pre-created the home dir (unbacked mountpoint) as root;
# useradd keeps it — hand it to the user (sshd StrictModes cares)
chown '$NEW_USER:$NEW_USER' '/home/$NEW_USER' '/home/$NEW_USER/.unbacked' 2>/dev/null || \
    chown '$NEW_USER:$NEW_USER' '/home/$NEW_USER'
sed -i 's/^# \(%wheel ALL=(ALL:ALL) ALL\)/\1/' /etc/sudoers
EOF

# outside the heredoc: passwd needs the real stdin, inside it would
# read the heredoc itself and abort
echo "set root password:"
arch-chroot "$MNT" passwd
echo "set $NEW_USER password:"
arch-chroot "$MNT" passwd "$NEW_USER"

echo "base done; next: NEW_USER=$NEW_USER arch-chroot $MNT /root/install/post-install.sh (copy this dir to $MNT/root/install first)"
