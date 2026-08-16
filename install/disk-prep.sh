#!/bin/sh
# Disk preparation for bootstrap.sh. Default layout: LUKS2+btrfs root
# with the flat subvolume scheme from export/subvolumes.map (the
# laptop). Alternative: FS=ext4 — plain ext4 root, no subvolumes, with
# an optional second disk carrying /home. ESP goes on a separate
# device (usb-stick /boot) or on the system disk. Destructive steps
# run only after an explicit WIPE confirmation.
#
# Entry modes:
# * existing partitions (the laptop: nvme p1 stays reserved for swap):
#     ROOT_PART=/dev/nvme0n1p2 BOOT_PART=/dev/sda1 NEW_USER=u ./disk-prep.sh
# * blank disks — partition first, then continue as above:
#     ROOT_DISK=/dev/nvme0n1 BOOT_DISK=/dev/sda NEW_USER=u ./disk-prep.sh
#   with BOOT_DISK: boot stick = single ESP; system disk = reserve + root
#   without BOOT_DISK: single-disk layout = ESP + reserve + root
#   HOME_DISK=/dev/sdb: second disk, single partition for /home
#
# Knobs (all optional):
#   FS=ext4          ext4 root (+ext4 home) instead of btrfs subvolumes
#   NO_LUKS=1        no encryption (applies to root and home)
#   RESERVE=40G      swap-reserve placeholder partition; 0 = none
#   ESP_SIZE=1G      single-disk mode only
#   BTRFS_OPTS=...   btrfs mount options (become the fstab via genfstab)
set -eu
cd "$(dirname "$0")"

: "${NEW_USER:?set NEW_USER (login name, used for the unbacked mountpoint)}"
MNT=${MNT:-/mnt}
FS=${FS:-btrfs}
NO_LUKS=${NO_LUKS:-}
BTRFS_OPTS=${BTRFS_OPTS:-noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,commit=120}

part_dev() {
    # /dev/nvme0n1 1 -> /dev/nvme0n1p1; /dev/sda 1 -> /dev/sda1
    case "$1" in *[0-9]) echo "${1}p$2" ;; *) echo "${1}$2" ;; esac
}

luks_open() { # $1 partition, $2 mapper name -> sets TARGET
    if [ -n "$NO_LUKS" ]; then
        TARGET=$1
    else
        echo "LUKS passphrase for $2 ($1):"
        cryptsetup luksFormat --type luks2 "$1"
        cryptsetup open "$1" "$2"
        TARGET=/dev/mapper/$2
    fi
}

if [ -n "${ROOT_DISK:-}" ]; then
    RESERVE=${RESERVE:-40G}
    ESP_SIZE=${ESP_SIZE:-1G}
    lsblk -o NAME,SIZE,MODEL "$ROOT_DISK" ${BOOT_DISK:+"$BOOT_DISK"} ${HOME_DISK:+"$HOME_DISK"}
    printf 'Type WIPE to repartition %s%s%s (ALL data lost): ' \
        "$ROOT_DISK" "${BOOT_DISK:+, $BOOT_DISK}" "${HOME_DISK:+, $HOME_DISK}"
    read -r answer
    [ "$answer" = WIPE ] || { echo aborted; exit 1; }

    n=1
    sgdisk --zap-all "$ROOT_DISK" > /dev/null
    if [ -z "${BOOT_DISK:-}" ]; then
        sgdisk -n "$n:0:+$ESP_SIZE" -t "$n:ef00" "$ROOT_DISK"
        BOOT_PART=$(part_dev "$ROOT_DISK" $n)
        n=$((n + 1))
    else
        sgdisk --zap-all -n 1:0:0 -t 1:ef00 "$BOOT_DISK"
        BOOT_PART=$(part_dev "$BOOT_DISK" 1)
    fi
    if [ "$RESERVE" != 0 ]; then
        sgdisk -n "$n:0:+$RESERVE" -t "$n:0700" "$ROOT_DISK"
        n=$((n + 1))
    fi
    sgdisk -n "$n:0:0" -t "$n:8309" "$ROOT_DISK"
    ROOT_PART=$(part_dev "$ROOT_DISK" $n)
    if [ -n "${HOME_DISK:-}" ]; then
        sgdisk --zap-all -n 1:0:0 -t 1:8302 "$HOME_DISK"
        HOME_PART=$(part_dev "$HOME_DISK" 1)
    fi
    partprobe "$ROOT_DISK" ${BOOT_DISK:+"$BOOT_DISK"} ${HOME_DISK:+"$HOME_DISK"}
fi

: "${ROOT_PART:?set ROOT_PART (e.g. /dev/nvme0n1p2) — will be WIPED}"
: "${BOOT_PART:?set BOOT_PART (e.g. /dev/sda1) — will be WIPED}"
[ "$FS" = btrfs ] || [ "$FS" = ext4 ] || { echo "error: FS must be btrfs or ext4" >&2; exit 1; }
if [ -n "${HOME_PART:-}" ] && [ "$FS" != ext4 ]; then
    echo "error: HOME_DISK/HOME_PART only makes sense with FS=ext4 (btrfs uses the @home subvolume)" >&2
    exit 1
fi

lsblk -o NAME,SIZE,MODEL,FSTYPE "$ROOT_PART" "$BOOT_PART" ${HOME_PART:+"$HOME_PART"}
printf 'Type WIPE to mkfs (%s%s) %s%s and %s: ' \
    "$FS" "${NO_LUKS:+, NO encryption}" "$ROOT_PART" "${HOME_PART:+, $HOME_PART}" "$BOOT_PART"
read -r answer
[ "$answer" = WIPE ] || { echo aborted; exit 1; }

luks_open "$ROOT_PART" root
ROOT_TARGET=$TARGET
mkfs.vfat -F 32 -n ARCHBOOT "$BOOT_PART"

if [ "$FS" = ext4 ]; then
    mkfs.ext4 -L archlinux "$ROOT_TARGET"
    mount "$ROOT_TARGET" "$MNT"
    if [ -n "${HOME_PART:-}" ]; then
        luks_open "$HOME_PART" home
        mkfs.ext4 -L home "$TARGET"
        mkdir -p "$MNT/home"
        mount "$TARGET" "$MNT/home"
    fi
else
    mkfs.btrfs -L archlinux "$ROOT_TARGET"

    # create the flat subvolume scheme (top-level, then nested names
    # as-is); the optional third map column carries file attributes
    # (e.g. +C = No_COW for /var/lib/docker) — set on the empty
    # subvolume so every future file inherits them
    mount "$ROOT_TARGET" "$MNT"
    while IFS="$(printf '\t')" read -r sv _ attrs; do
        [ "$sv" = "/" ] && continue
        btrfs subvolume create "$MNT${sv}"
        [ -z "$attrs" ] || chattr "$attrs" "$MNT${sv}"
    done < export/subvolumes.map
    umount "$MNT"

    # mount everything for pacstrap, parents before children
    # (the map is fstab-ordered; / first, /.btrfs_pool = subvolid 5 last)
    while IFS="$(printf '\t')" read -r sv mp _; do
        mp=$(printf '%s' "$mp" | sed "s/@USER@/$NEW_USER/")
        mkdir -p "$MNT$mp"
        if [ "$sv" = "/" ]; then
            mount -o "$BTRFS_OPTS,subvolid=5" "$ROOT_TARGET" "$MNT$mp"
        else
            mount -o "$BTRFS_OPTS,subvol=$sv" "$ROOT_TARGET" "$MNT$mp"
        fi
    done < export/subvolumes.map
fi

mkdir -p "$MNT/boot"
mount "$BOOT_PART" "$MNT/boot"

echo "mounted; next: bootstrap.sh (see README.md for the env vars)"
