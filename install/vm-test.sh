#!/bin/bash
# Assemble the validation VM for the install scripts: UEFI (OVMF), an
# NVMe disk, two usb sticks (boot + mirror), the arch ISO, and this
# repo shared read-only over 9p. Disks live on the @var_libvirt
# subvolume (VM images belong there; excluded from root snapshots and
# backups). One-time: sudo install -d -o $USER /var/lib/libvirt/images/test-vm
# Delete the directory to start clean.
#
# Host packages: qemu-base qemu-ui-gtk edk2-ovmf
# Usage: ISO=~/downloads/archlinux-x86_64.iso ./vm-test.sh
#        ./vm-test.sh clean     # delete the disks and NVRAM, keep the dir
set -eu

DIR=${VM_DIR:-/var/lib/libvirt/images/test-vm}
REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
OVMF=/usr/share/edk2/x64

if [ "${1:-}" = clean ]; then
    ls -lh "$DIR" 2>/dev/null || { echo "nothing at $DIR"; exit 0; }
    printf 'Delete these VM images? [y/N] '
    read -r answer
    [ "$answer" = y ] && rm -v "$DIR"/*.img "$DIR"/OVMF_VARS.fd
    exit 0
fi

: "${ISO:?path to the archlinux iso}"
[ -d "$DIR" ] || { echo "error: $DIR missing — sudo install -d -o $USER $DIR" >&2; exit 1; }
[ -f "$DIR/nvme.img" ]   || qemu-img create -f qcow2 "$DIR/nvme.img" 60G
[ -f "$DIR/boot.img" ]   || qemu-img create -f raw "$DIR/boot.img" 6G
[ -f "$DIR/mirror.img" ] || qemu-img create -f raw "$DIR/mirror.img" 6G
[ -f "$DIR/OVMF_VARS.fd" ] || cp "$OVMF/OVMF_VARS.4m.fd" "$DIR/OVMF_VARS.fd"

exec qemu-system-x86_64 \
    -enable-kvm -cpu host -smp 4 -m 4096 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF/OVMF_CODE.4m.fd" \
    -drive if=pflash,format=raw,file="$DIR/OVMF_VARS.fd" \
    -drive file="$DIR/nvme.img",if=none,id=nvme0 \
    -device nvme,drive=nvme0,serial=vmnvme1 \
    -device qemu-xhci,id=xhci \
    -drive file="$DIR/boot.img",if=none,id=usb0,format=raw \
    -device usb-storage,bus=xhci.0,drive=usb0 \
    -drive file="$DIR/mirror.img",if=none,id=usb1,format=raw \
    -device usb-storage,bus=xhci.0,drive=usb1 \
    -drive file="$ISO",if=none,id=cd0,format=raw,media=cdrom,read-only=on \
    -device ide-cd,drive=cd0,bootindex=0 \
    -virtfs "local,path=$REPO,mount_tag=repo,security_model=none,readonly=on" \
    -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22 \
    -monitor unix:"$DIR/monitor.sock",server,nowait
