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
./unbacked-links.sh --add -n ./.venv    # only show what --add would do
./unbacked-links.sh --restore ./.venv   # put the backup back, drop the link
./unbacked-links.sh --subvol ./checkout # make it a nested subvolume in place
./unbacked-links.sh --list              # every link and subvolume, any depth
./unbacked-links.sh --check             # report what has gone dead
./unbacked-links.sh --forget ./.venv    # drop the record of a path
./unbacked-links.sh --suggest           # what else might be worth moving out
./unbacked-links.sh --keep sync/notes   # never suggest this path again
```

chezmoi links it as `~/.local/bin/unbacked` (linux only), so inside a
checkout the same thing is `unbacked --add -n ./.venv`. The link points
into the working tree: the script stays next to the map, and an edit to
it needs no `chezmoi apply`.

On a fresh machine nothing exists yet, so `--apply` only creates targets
and symlinks (VM-checked: a bare `$HOME` plus `~/.unbacked` reproduces
the map exactly). Where the data is still in place — the reference
machine — it is moved first: a backup clone, `cp -a --reflink=auto` (a
CoW clone within the same filesystem, no extra space), an `rsync -n`
comparison, and only then `rm -rf` plus the symlink. A path some process
has open is skipped unless `--force`; anything unexpected is left alone
with a warning and a non-zero exit. Re-running is a no-op.

Moving a new path out, in order:

1. `unbacked --add -n <path>`: the size, the target and whatever holds
   the path open. Nothing is touched.
2. Close what holds it, then `unbacked --add <path>`.
3. Use the program that owns the path and see that it still works.
4. If it does not: `unbacked --restore <path>`, then remove the copy the
   restore reports as left under `~/.unbacked`.
5. If it does: remove the backup, `~/.unbacked/.moved/<time>`.
6. For a path up to three levels deep, `make install.export` and commit
   the refreshed map. A deeper one does not change the map.

Never edit the map first: `--add <path> [<path under ~/.unbacked>]` is
what moves the existing data out safely. `validate.sh` diffs the live
layout against the map. The path is relative to `$HOME` as in the map,
absolute, or `./`-relative to the current directory; without the second
argument the target keeps the same relative path.

The backup clone lands in `~/.unbacked/.moved/<time>/<path>` before the
original is removed: also a reflink, and outside every snapshot.
`--restore <path>` copies the newest one back in place of the link. It
leaves the moved copy under `~/.unbacked` alone (it may have changed
since), so remove that by hand before moving the same path again; the
clones in `.moved` are likewise never removed by the script.

### A directory that has to keep its path: `--subvol`

A symlink changes `pwd -P`, and tools keyed on the physical path lose
their state (Claude Code sessions, direnv, IDE indexes). It also dangles
inside a container that bind-mounts the checkout, and a docker build
cannot `COPY` through a link that leaves its context. For those cases
`--subvol <directory>` turns the directory into a btrfs subvolume nested
where it stands: a snapshot of `@home` does not descend into a nested
subvolume, so the path is out of the snapshots with nothing moved and
nothing linked. The steps are the same as for `--add` (`-n` first, a
backup clone, `--restore` to undo); `--restore` puts the backup back as a
plain directory and moves what the subvolume held next to the backups.

Use it for a whole checkout that is built in place (dozens of `build/`
directories that `clean` deletes and recreates cannot be linked one by
one) or a cache a container writes through a bind mount. What it costs:

* the checkout is not backed up at all: unpushed commits, stashes and
  ignored local files live on this disk only
* a restored snapshot of `@home` has an empty directory in its place
* rolling `@home` back by swapping the subvolume leaves the nested one
  inside the old `@home`; move it across (a rename) before deleting that
* `rm -rf` followed by a rebuild makes a plain directory again
* `du -x` and `find -xdev` stop at it, and `mv` across it copies

Run it from outside the directory and name it by path
(`unbacked --subvol ~/src/work/app`, not `--subvol .`). The directory is
swapped for the new subvolume, so a shell standing in it would be left in
the one that is gone; the in-use guard sees that shell and skips the
path.

### Dead paths: `--check`

A link is its own record only while it exists, and a subvolume looks like
any other directory. So every link and subvolume made here is also
written to `~/.local/state/unbacked/layout`; a no-op `--apply` or
`--add` records a link that was made before the file existed. The file
sits in `~/.local/state` and not in `~/.unbacked` so that the backup
holds it: after `@home` comes back from a snapshot the subvolumes are
empty directories, and this file is what says which ones to convert
again before they fill up. `--check` holds the record against the disk
and the disk against the record, and reports where they part, changing
nothing. What the record names and the disk no longer has:

* a link whose target is missing
* a recorded link that is gone — a tool deleted it and rebuilt a real
  directory in its place, which is back in the snapshots, or the checkout
  went away — with its data still under `~/.unbacked`
* a recorded link that points somewhere else now
* a recorded subvolume that is a plain directory again

What the disk has and the record does not name:

* a link into `~/.unbacked` nothing records, one made with `ln -s` (the
  message gives the `--add` line that writes it down)
* a nested subvolume nothing records (`--subvol` on it records it)
* data under `~/.unbacked` that no link points at and nothing records

The backups still kept under `.moved` are listed as well, without
counting as a fault. What to do with a finding is a decision: `--add` the
path again after removing the stale copy, delete the orphan, or
`--forget <path>` when the path is meant to stay as it is now.
`validate.sh` runs the check in its own section.

### What else could go: `--suggest`

`--check` looks at what was moved. `--suggest` looks at the snapshotted
part of `$HOME` for what might be worth moving, by two signs:

* a directory git ignores inside a checkout, 20M or more: by the
  project's own word it is not source (`.venv`, `node_modules`, build
  output). One that holds a checkout further down is marked, since
  somebody's work may sit in it.
* a directory outside the checkouts whose files changed by 5M or more
  over the last 7 days, summed under the first three levels of the path.
  A snapshot pays for change, not for size.

Neither is a verdict, and the second list names data that belongs in the
backup (synced notes, session transcripts) as readily as a cache.
`--keep <path>` takes a path off both lists for good; the kept paths are
in `~/.local/state/unbacked/keep`, and `--forget <path>` takes one off
again. Nested subvolumes and `~/.unbacked` are not walked: they are out
of the snapshots already.

`--scan` looks three levels deep. A path further down, such as a `.venv`
inside a checkout, can be moved the same way and stays out of the map: it
belongs to the checkout, not to the machine layout. Two things to know
before moving one of those:

* git does not take a symlink for a directory, so a `.venv/` line in
  `.gitignore` stops matching and the link shows up as untracked. The
  same goes for a cache ignored only by a `.gitignore` inside itself
  (`.mypy_cache`). The global ignore chezmoi installs
  (`~/.config/git/ignore`) lists the bare names for that reason.
* the link holds an absolute host path, so it dangles inside a container
  that bind-mounts the checkout. Harmless for a virtualenv the container
  never uses, not for a cache the tools in the container write into.

Not chezmoi on purpose: chezmoi applies a declaration, so a `symlink_`
entry aimed at a path that still holds data deletes that data on the
next `chezmoi apply`. Moving data out with a verified copy is imperative
work. The script's header lists what is deliberately left backed up
(`~/src` as a whole — source is what a backup is for, and a checkout
that must leave goes by `--subvol`, not by a link; vdirsyncer state
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
