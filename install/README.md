# Reproducible install

Rebuilds the machine from blank disks to the state managed by this
repo with three plain scripts — no installer framework. (An archinstall
variant was prototyped first and dropped: our layout — ESP on a usb
stick, an untouched swap-reserve partition, 25 flat btrfs subvolumes,
LUKS invisible to `pre_mounted_config` — pushed all the real work out
of it anyway, leaving only pacstrap+locale+user, which is this script.)

Split of responsibility:

* `disk-prep.sh` — LUKS2, btrfs, the subvolume scheme from
  `export/subvolumes.map`, everything mounted under /mnt
* `bootstrap.sh` — pacstrap, fstab, locale/tz/hostname/user, mkinitcpio
  template, limine EFI fallback binary. Package set: minimal by default
  (boot + bootstrap tooling, `export/packages-minimal.txt`, plus
  fs/crypto packages picked by what disk-prep built);
  `PKG_SET=full` installs the reference machine's whole exported set
* `post-install.sh` — chroot glue before the first reboot: AUR limine
  hooks (own the /boot layout), initramfs build, session groups
* pyinfra + chezmoi — everything else, unchanged (top-level README)

## Order

On the arch ISO with the repo checked out:

```sh
cd install
ROOT_PART=/dev/nvme0n1p2 BOOT_PART=/dev/sda1 NEW_USER=<user> ./disk-prep.sh
NEW_USER=<user> NEW_HOSTNAME=<host> TIMEZONE=<Area/City> ./bootstrap.sh
cp -r . /mnt/root/install
NEW_USER=<user> arch-chroot /mnt /root/install/post-install.sh
reboot
```

After the reboot — the normal bootstrap from the top-level README:
copy `~/.config/chezmoi/chezmoi.toml`, run every pyinfra deploy, then
`make dotfiles.apply`, then `./unbacked-links.sh --apply` (section
below), then the per-deploy one-time notes (fido2 enrollment, u2f_keys,
boot mirror stick, LUKS header backup).

All private values (user, hostname, timezone, disk paths) are env
vars — nothing to copy or template, nothing private in this directory.
Layout knobs live in disk-prep.sh (`NO_LUKS`, `RESERVE`, `ESP_SIZE`,
`BTRFS_OPTS` — the mount options also become the fstab via genfstab;
`FS=ext4` for a plain ext4 root without subvolumes, optionally with
`HOME_DISK=/dev/sdX` — a second disk as /home, LUKS'ed unless NO_LUKS,
unlocked via crypttab).

Caveat: the pyinfra limine deploy templates a LUKS cmdline
(`rd.luks.*` from host data) — an unencrypted host must skip that
deploy or grow its own template variant; bootstrap.sh itself writes a
correct first-boot `/etc/default/limine` for both cases.

## Snapper one-time (btrfs layout)

The pyinfra snapper deploy renders config files, but the config itself
must be registered once, and `snapper create-config` insists on
creating `.snapshots` itself. **post-install.sh automates this** for
btrfs installs (snapper is in both package sets; the chroot has no
stale snapperd to interfere). On a system installed some other way run
the flat-layout dance by hand (found the hard way on the VM):

```sh
sudo umount /.snapshots && sudo rmdir /.snapshots
sudo snapper --no-dbus -c root create-config /
sudo btrfs subvolume delete /.snapshots      # the nested one it just made
sudo mkdir /.snapshots && sudo chmod 750 /.snapshots && sudo mount /.snapshots
sudo systemctl restart snapperd              # the dbus daemon caches the config list
```

Then re-run the snapper deploy (it re-renders the config file over the
generated one). Without the snapperd restart snap-pac silently creates
no snapshots. validate.sh's "subvolume parents" section proves no
nested `.snapshots` was left behind.

## ~/.unbacked links

Caches, browser profiles, toolchain stores and the maildir live on the
`@home_unbacked` subvolume and are symlinked back into `$HOME`, so no
btrbk snapshot ever pins their churned state.

`export/unbacked-links.map` is that layout, dumped from the reference
machine like every other file in `export/`: two tab-separated relative
columns, no user name in it.

```
.config/BraveSoftware	config/BraveSoftware
```

`unbacked-links.sh` both produces and applies it:

```sh
./unbacked-links.sh                     # dry run against the map
./unbacked-links.sh --apply             # create the targets and the links
./unbacked-links.sh --apply .config     # only paths under .config
./unbacked-links.sh --scan              # dump the live layout
./unbacked-links.sh --add .npm npm      # move a new path out, then link it
```

On a fresh machine nothing exists yet, so `--apply` only creates targets
and symlinks (VM-checked: a bare `$HOME` plus `~/.unbacked` reproduces
the map exactly). Where the data is still in place — the reference
machine — it is moved first: `cp -a --reflink=auto` (a CoW clone within
the same filesystem, no extra space), an `rsync -n` comparison, and only
then `rm -rf` plus the symlink. A path some process has open is skipped
unless `--force`; anything unexpected is left alone with a warning and a
non-zero exit. Re-running is a no-op.

Grow the layout with `--add <path under $HOME> <path under ~/.unbacked>`,
then `make install.export` to refresh the map — never by editing the map
first, since `--add` is what moves the existing data out safely.
`validate.sh` diffs the live layout against the map.

Not chezmoi on purpose: chezmoi applies a declaration, so a `symlink_`
entry aimed at a path that still holds data deletes that data on the
next `chezmoi apply`. Moving data out with a verified copy is imperative
work. The script's header lists what is deliberately left backed up
(`~/src` needs a bind mount instead — a symlink changes `pwd -P` and
tools keyed on the physical path lose their state; vdirsyncer state
holds OAuth tokens; `~/.claude/projects` holds the per-project memory).

## Validation

* `./validate.sh` on the new system — diffs packages / units /
  subvolume mounts / mountpoint owners+modes against `export/`.
  Run it as the regular user with the whole install dir alongside
  (it reads `export/` next to itself — from the repo checkout, or
  copy the directory over). Zero output per section = match; while
  the bootstrap is only partial, diffs in the foreign/flatpak and
  enabled-units sections are expected (AUR packages and service
  enablement arrive with yay and the pyinfra deploys later), the
  package / mounts / permissions sections must be clean right after
  bootstrap. Non-zero exit = at least one section differed.
* every pyinfra deploy run twice — the second run must be empty
* `chezmoi diff` empty; boots from the usb stick via limine, LUKS
  opens with the passphrase

## Tested configurations

Every knob and both entry modes were VM-validated (boot to login):

| FS    | LUKS      | ESP         | Extras                                   | PKG_SET |
|-------|-----------|-------------|------------------------------------------|---------|
| btrfs | yes       | usb stick   | full pyinfra + chezmoi layers on top     | full    |
| ext4  | yes (×2)  | single-disk | `HOME_DISK` second disk via crypttab     | minimal |
| btrfs | NO_LUKS   | usb stick   |                                          | minimal |
| ext4  | NO_LUKS   | usb stick   | `RESERVE=0` (single root partition)      | minimal |
| btrfs | yes       | single-disk | existing-partitions mode (`ROOT_PART`/`BOOT_PART`, the laptop path) over a table made by a first pass; `+C` map column inheritance | minimal |
| btrfs | yes       | usb stick   | composed package set (fs/crypto extras auto-added) + automated snapper config dance | minimal |

## VM dry run

`./vm-test.sh` (host packages: `qemu-desktop edk2-ovmf`; ISO from any
mirror) boots the arch ISO in a UEFI VM with an NVMe disk, two "usb
sticks" and this repo on a 9p share. Host port 2222 forwards to the
VM's sshd (running on the ISO out of the box) — set a root password in
the VM console (`passwd`) and the whole run can be driven over
`ssh -p 2222 root@localhost`. Inside the ISO:

```sh
mkdir /repo && mount -t 9p -o trans=virtio,ro repo /repo

cp -r /repo/install /root/install && cd /root/install
# blank disks: ROOT_DISK/BOOT_DISK partition first (reserve + root;
# drop BOOT_DISK for a single-disk ESP layout, NO_LUKS=1 for a plain
# root); the real laptop passes ROOT_PART/BOOT_PART to keep its table
ROOT_DISK=/dev/nvme0n1 BOOT_DISK=/dev/sda RESERVE=4G NEW_USER=vmtest ./disk-prep.sh
NEW_USER=vmtest NEW_HOSTNAME=vmtest TIMEZONE=UTC ./bootstrap.sh
cp -r /root/install /mnt/root/install
NEW_USER=vmtest arch-chroot /mnt /root/install/post-install.sh
reboot
```

Pass criteria: limine menu appears (boot from the usb stick), the LUKS
passphrase prompt unlocks, every subvolume mounts (`./validate.sh`
section), both kernels boot. pyinfra/chezmoi validation continues on
the booted VM per the section above.

## Keeping exports fresh

`export/` files are dumps of the live system; regenerate after
package-set or layout changes:

```sh
make install.export     # from the repo root; also refreshes subvolume-perms.txt
```

(`export/subvolumes.map` changes only with the disk layout — edit by
hand, keep `@USER@` in the unbacked path; the optional third column is
chattr attributes applied to the fresh subvolume — `+C` (No_COW, at
the cost of checksums and compression) on the rewrite-heavy homes:
docker, libvirt, postgres, machines, portables. `/var/log/journal`'s
`+C` needs no entry — systemd's own tmpfiles sets it on first boot. `subvolume-perms.txt` is the
matching owners/modes dump — refreshed by `make install.export`, which also
regenerates `unbacked-links.map` via `unbacked-links.sh --scan` and
`flatpak-overrides.txt`, the per-app permission overrides from both scopes
(`flatpaks.txt` only lists what is installed, not how it is sandboxed).
`mkinitcpio.conf.template` mirrors `/etc/mkinitcpio.conf` — update on hook
changes.)
