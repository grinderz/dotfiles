#!/bin/sh
# Chroot glue between bootstrap.sh and the first reboot. Run from the
# ISO: arch-chroot /mnt /root/install/post-install.sh. Everything else
# system-level comes from pyinfra after the reboot — this script covers
# only what must exist for the first boot.
set -eu

: "${NEW_USER:?set NEW_USER}"

# limine + the AUR hook that owns our /boot layout (hash dirs, history,
# snapper sync). Without it the first mkinitcpio run would write a
# layout the deployed limine.conf does not point at.
pacman -S --needed --noconfirm base-devel git

# makepkg -s installs makedepends via sudo (limine-entry-tool pulls in
# gradle); the fresh user has no sudoers rights yet — grant them only
# for the duration of the builds
echo "$NEW_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-bootstrap
trap 'rm -f /etc/sudoers.d/99-bootstrap' EXIT

build_aur() {
    su "$NEW_USER" -c "
        cd /tmp && rm -rf $1 &&
        git clone --depth 1 https://aur.archlinux.org/$1.git &&
        cd $1 && makepkg --noconfirm -s
    "
    pacman -U --noconfirm /tmp/"$1"/*.pkg.tar.zst
}

# prebuilt package if one was dropped into install/pkgs/ (e.g. from the
# old machine's yay cache — skips the gradle-sized AUR build), source
# build otherwise
install_pkg() {
    pkg=$(find /root/install/pkgs -name "$1-[0-9]*.pkg.tar.zst" 2>/dev/null | sort -V | tail -1)
    if [ -n "$pkg" ]; then
        pacman -U --noconfirm "$pkg"
    else
        build_aur "$1"
    fi
}

install_pkg limine-mkinitcpio-hook
# snapshot-boot integration is btrfs-only
if [ "$(findmnt -no FSTYPE /)" = btrfs ]; then
    install_pkg limine-snapper-sync
    systemctl enable limine-snapper-sync.service

    # register the snapper root config (flat-layout dance): create-config
    # insists on creating .snapshots itself, so hand it the spot and then
    # swap our @snapshots subvolume back in. In the chroot no snapperd is
    # running yet, so its config cache cannot go stale.
    if command -v snapper > /dev/null && ! grep -q '^SNAPPER_CONFIGS=".*root' /etc/conf.d/snapper; then
        umount /.snapshots
        rmdir /.snapshots
        snapper --no-dbus -c root create-config /
        btrfs subvolume delete /.snapshots
        mkdir /.snapshots && chmod 750 /.snapshots
        mount /.snapshots
    fi
fi
limine-mkinitcpio

# session groups pyinfra does not manage (docker group comes from the
# docker deploy's docker_users)
usermod -aG input,seat,i2c "$NEW_USER" 2>/dev/null || usermod -aG input "$NEW_USER"

echo "post-install done; reboot, then: chezmoi.toml -> pyinfra deploys -> dotfiles.apply (README bootstrap order)"
