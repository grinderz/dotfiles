# dotfiles

Personal machine configuration. Successor to `desktop-playbook` (archived, Ansible).

Two tools, split by scope:

* **chezmoi** (`home/`) — user dotfiles: fish, ssh client, git, gpg, etc.
  Templates use `.chezmoi.os` / `.chezmoi.hostname` instead of Ansible facts.
* **pyinfra** (`infra/`) — system state: packages, `/etc`, services.
  Agentless over ssh, jinja2 templates carried over from the old roles.

## Usage

```sh
# dotfiles
make dotfiles.diff                                  # preview, never changes anything
make dotfiles.apply
make dotfiles.add/.config/foo/bar.conf              # adopt a file, path relative to $HOME

# system, single host/group + single deploy; --diff is always on
make infra.local.linux.local deploy=pacman args="--dry"   # on the machine itself, no ssh
make infra.linux.<host-or-group> deploy=systemd           # remote over ssh
```

`--limit` value (the last target component) is a host name or an inventory
group. Remote sudo: pyinfra prompts for the password interactively.

To run deploys on a managed host locally (no ssh), its own
`~/.config/chezmoi/chezmoi.toml` declares the same host as `@local` —
group and data stay identical, only `name` differs:

```toml
[[data.infra.linux]]
name = '@local'        # instead of the ssh host name
group = 'somehost'
[data.infra.linux.data]
# same data as in the ssh variant
```

```sh
make infra.local.linux.somehost deploy=pacman args="--dry"
```

## SSH / YubiKey

Auth key is ed25519-sk (FIDO2). paramiko cannot read sk key files and
gpg-agent refuses to host them, so each `infra.linux.*` run wraps pyinfra in a
throwaway OpenSSH agent with the key loaded (`PYINFRA_SSH_KEY` in the
Makefile). Requires pyinfra >= 3.10 (agent-held sk keys, PR 1858).

## Private data

Identity (name/emails/signing keys), work and VPS specifics never enter the
repo. Templates guard on machine-local data from
`~/.config/chezmoi/chezmoi.toml`:

```toml
[data.work]
name = "..."
email = "..."
git_signing_key = "~/.ssh/..."
git_includes = """..."""    # verbatim [includeIf] git config blocks
allowed_signers = """..."""
okd_url = "..."
ssh_hosts = """..."""       # verbatim ssh Host blocks

[data.personal]
name = "..."
email = "..."
git_signing_key = "~/.ssh/..."
allowed_signers = """..."""
ssh_hosts = """..."""       # home LAN Host blocks

[data.vps]
ssh_hosts = """..."""

[data.desktop]
wallpaper_dir = "~/pictures/wallpapers/brave"   # sway bg, swaylock bg, sync script
latitude = "51.48"                              # wlsunset night light
longitude = "-0.01"
output_left = "Make Model Serial"               # kanshi profile + sway workspace pins
output_right = "Make Model Serial"
traffic_url = "https://..."                     # regional traffic XML feed, waybar module
traffic_map_url = "https://..."                 # map page opened on click
```

Machines without a table simply render without those sections
(`{{ if hasKey . "work" }}`); `.config/git/config.work.inc` is not even
created (see `home/.chezmoiignore`).

pyinfra reads the same file (`util.chezmoi_work_data`, `util.chezmoi_infra_hosts`):
vpn profiles come from `[data.work]`, and real inventory hosts (names, disk
ids, MACs, hosts entries) from `[[data.infra.linux]]` — `infra/linux.py` keeps
only `@local` and builds `--limit` groups from each entry's `group` key.

## Bootstrap of a new machine

1. `pyinfra` deploys packages, services, sshd (installs chezmoi too)
2. copy `~/.config/chezmoi/chezmoi.toml` (private data, kept out of the repo)
3. `make dotfiles.apply` as the user

## Layout

```
home/                  # chezmoi source dir
infra/
├── linux.py           # inventory per group; group name = file name
├── group_data/        # defaults per group (was roles/*/defaults)
├── deploys/           # one file per former role
├── templates/         # jinja2, reused from ansible almost verbatim
└── util.py            # block_with_diff, sudoers_template (visudo-checked
                       # staging install), chezmoi.toml readers
```

## One-time operations

Bootstrap, before the first deploy on a machine:

* install tooling: `make setup.pyinfra` (needs `uv`), chezmoi (brew / pacman)
* copy `~/.config/chezmoi/chezmoi.toml` (private data, kept out of the repo)

Per deploy, once per host:

* **pacman** — after: remove old `# ANSIBLE MANAGED BLOCK` markers from
  `/etc/pacman.conf` (NoExtract entries, sublime-text repo)
* **hosts** — after: remove old ansible markers from `/etc/hosts`
* **snapper** — after: remove old ansible markers from `/etc/fstab`
  (the archive disk mount)
* **btrbk** — before:
  * `pacman -S btrbk`
  * snapshot dir subvolume must exist:
    `btrfs subvolume create /.btrfs_pool/@btrbk_snapshots`
  * create the target directory on the mounted archive disk (btrbk requires
    it to exist): `mkdir /media/archive-usb-hdd/home`
  * ssh target (if enabled): `ssh-keygen -t ed25519 -N '' -f /etc/btrbk/ssh/id_ed25519`
    and authorize the pubkey on the receiver (`ssh_filter_btrbk.sh` forced command)

  after:
  * config sanity + planned actions: `btrbk -n run`
  * first snapshot: `systemctl start btrbk-snapshot.service`, then
    `btrbk list snapshots`
  * transfer: plug the archive disk (udev pipeline runs `btrbk resume`) or run
    `btrbk resume` by hand, then `btrbk list backups`
  * timer armed: `systemctl list-timers btrbk-snapshot.timer`;
    log: `/var/log/btrbk.log`
* **git** (chezmoi) — after: delete the old work include from
  `~/.config/git/`, renamed to `config.work.inc`
* **bin** (chezmoi) — after, macOS: delete `/usr/local/bin/okd-token.sh` from
  the old ansible role, superseded by `~/.local/bin/okd-token.sh`
* **openconnect** — after, macOS: delete old `/usr/local/bin/vpn-*.sh`,
  superseded by `~/.local/bin/vpn-*.sh`
* **backup-boot** — before (hosts with `bootmirror_mountpoint`): prepare the
  mirror stick, see below
* **storage-health** — before: `pacman -S smartmontools` (deploys only
  configure, packages are installed by hand)
* **systemd** — before: `pacman -S power-profiles-daemon pacman-contrib
  yubikey-touch-detector`
* **nftables** — inbound firewall; extra holes go to `nftables_open_tcp` /
  `nftables_open_udp` in host or group data
* **battery** / **docker** — `conservation_users` / `docker_users` live in
  host data (machine-local chezmoi.toml, `[data.infra.linux.data]`); hosts
  other than tb-6 also override `conservation_node` (ideapad sysfs path
  differs per machine)
* **bluetooth** — before: `pacman -S bluez bluez-utils`
* **keyring** — before: `pacman -S gnome-keyring libsecret`; takes effect on
  next tty login (PAM unlocks the default keyring with the login password)
* **pam** — before: `pacman -S pam-u2f`; after: register the yubikeys for
  sudo-by-touch (per machine, file stays out of the repo):
  `mkdir -p ~/.config/Yubico && pamu2fcfg > ~/.config/Yubico/u2f_keys`,
  each additional key: `pamu2fcfg -n >> ~/.config/Yubico/u2f_keys`
* **sway session** (chezmoi) — packages: `kanshi` (output profiles),
  `swayidle`/`swaylock`, `waybar`, `mako`, `fuzzel`, `sway-contrib`
  (grimshot), `wlsunset`, `tesseract` + `tesseract-data-eng`/`-rus`
  (OCR bind); the failed-units
  notifier timer is enabled by the systemd deploy (run dotfiles apply
  first — the unit files come from chezmoi); dark theme for GTK4/portal
  apps and web (dconf state, chezmoi only covers the settings.ini files):
  `gsettings set org.gnome.desktop.interface color-scheme prefer-dark`

### Boot mirror stick

The `96-bootmirror.hook` rsyncs `/boot` to a second bootable stick after every
transaction that touches it, removing the single point of failure. One-time
prep of the stick (assuming it shows up as `sdX`):

```sh
sudo pacman -S --needed dosfstools
sudo parted /dev/sdX --script mklabel gpt mkpart ESP fat32 1MiB 100% set 1 esp on
sudo mkfs.vfat -n BOOTMIRROR /dev/sdX1

sudo mkdir -p /boot-mirror
# fstab entry, UUID from `lsblk -f /dev/sdX1`; noauto+automount so an absent
# stick never blocks boot and the hook mounts it on demand
# UUID=XXXX-XXXX  /boot-mirror  vfat  rw,noauto,x-systemd.automount,x-systemd.idle-timeout=1min,fmask=0022,dmask=0022  0 0
sudo systemctl daemon-reload

sudo rsync -rt --modify-window=1 /boot/ /boot-mirror/   # initial sync
```

Then verify the machine actually boots from the mirror once (firmware boot
menu; limine is picked up via the `EFI/BOOT` fallback path rsync carries
over). Add `nofail` to the `/boot` fstab options so booting from the mirror
does not drop to emergency when the primary stick is dead — the failed
`boot.mount` is surfaced by the `failed-units-notify` user timer instead.

## Notes

* fish functions live in `functions/` (autoloaded); macOS-only ones are
  excluded on other systems via `home/.chezmoiignore`.
* gpg: pinentry is picked per OS in `gpg-agent.conf.tmpl` (pinentry-mac on
  macOS, `/usr/bin/pinentry` elsewhere).
* limine: the deploy edits `/etc/default/limine` and `/boot/limine.conf` but
  does not regenerate boot entries — kernel cmdline changes take effect on the
  next kernel transaction (or run `limine-update` by hand).
