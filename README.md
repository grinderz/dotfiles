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
  (OCR bind), `otf-font-awesome` + `ttf-roboto` (waybar font stack),
  `udisks2` (usb-storage waybar module);
  the failed-units
  notifier timer is enabled by the systemd deploy (run dotfiles apply
  first — the unit files come from chezmoi); dark theme for GTK4/portal
  apps and web (dconf state, chezmoi only covers the settings.ini files):
  `gsettings set org.gnome.desktop.interface color-scheme prefer-dark`

* **mail / calendar** (chezmoi) — packages: `aerc isync notmuch pass w3m
  dante khal vdirsyncer python-aiohttp-oauthlib keyutils`, AUR: `davmail
  oama cyrus-sasl-xoauth2` (the last two for Google mail over XOAUTH2 —
  the default for Google accounts, app passwords are legacy). Accounts
  are data-driven from `[data.mail]` / `[data.cal]` in the private
  chezmoi.toml — schema in the headers of `isyncrc.tmpl` and
  `vdirsyncer/config.tmpl`. Secrets live in pass: `passp` (personal store,
  `~/sync/pass`) and `passw` (work store, `~/sync/work/pass`); the shared
  Google OAuth client sits at `oauth/google/client-id` / `client-secret`
  (used by vdirsyncer directly and mirrored into oama's config). After
  apply: `systemctl --user enable --now davmail.service mbsync.timer`,
  a one-time `oama authorize google <email>` per Google mail account and
  `vdirsyncer discover` (browser OAuth per google calendar), then
  `enable --now vdirsyncer.timer`.

### Mail password rotation

The mail and calendar timers read secrets through `pass-cache`: a kernel
user-keyring cache (24h TTL) in front of pass, so the gpg pinentry shows
up once a day instead of on every 5-minute sync. pass remains the only
source of truth — the cache never touches disk and dies with the session.

When rotating a password (company policy or otherwise), update the store
and flush the cache in one go:

```sh
passw insert mail/work && pass-cache drop mail/work
```

Skipping the drop leaves the timers retrying the stale password for up to
a day — enough for an AD lockout. `pass-cache drop` with no entry flushes
everything cached.

Full Exchange rotation, zero lockout risk (davmail itself holds no
credentials — only the clients below do):

```sh
systemctl --user stop mbsync.timer vdirsyncer.timer
# close Evolution too — it keeps its own copy in gnome-keyring and retries

# change the password in AD / the corporate portal, then:
passw insert mail/work
pass-cache drop mail/work
mbsync -a -V                 # one manual run with the new password
systemctl --user start mbsync.timer vdirsyncer.timer
# Evolution prompts for the new password on next start
```

Strictly the stop/start is optional — between the portal change and the
drop the timers fit at most one failed attempt, below any sane lockout
threshold — but stopping costs nothing.

### Mail account changes

The first `[[data.mail.accounts]]` entry is the primary identity: notmuch
`primary_email` (the rest become `other_email`) and the aerc tab active on
start. Semantically it barely matters — aerc picks From per account on its
own — so order the accounts by daily use and reorder freely; `chezmoi
apply` regenerates everything, mail and tags untouched.

Replacing an account (job change): swap its blocks in the private
chezmoi.toml (`[data.mail]` / `[data.cal]`, new `davmail_url`), rotate the
pass entries (`passw insert` new, `passw rm` + `pass-cache drop` old),
`chezmoi apply`. Templates never touch data of removed accounts — clean up
by hand: `~/.unbacked/mail/<name>` (or keep it as a dead folder, notmuch
keeps indexing it), `~/.local/share/calendars/<name>` plus its vdirsyncer
status, then `notmuch new` and `vdirsyncer discover`. Revoke the oama
token if the account used one.

### Mail / calendar FAQ

* **How do I add a mailbox?** One `[[data.mail.accounts]]` block in the
  private chezmoi.toml + `passp/passw insert mail/<name>` + `chezmoi
  apply`. Commented examples for every kind sit at the bottom of the toml.
* **How do I find the davmail url?** `curl -sk -o /dev/null -w
  '%{http_code}' https://<owa-host>/EWS/Exchange.asmx` — 401 means the
  endpoint exists, use that url. 404 — ask autodiscover, or hand davmail
  the plain OWA url and let it resolve.
* **Several Exchange accounts?** Same server — just more `kind =
  "davmail"` accounts, credentials are per IMAP login. A second server
  needs a second davmail instance (own ports and properties file) — not
  wired up, extend when it actually happens.
* **Google mail — OAuth or app password?** OAuth: `kind = "gmail-oauth"`
  (XOAUTH2 via oama, browser login once — works for personal accounts and
  Workspace behind SSO alike; app passwords are legacy at Google). `kind =
  "gmail"` with an app password stays as the low-ceremony fallback. One
  OAuth client serves every account — tokens are per account (oama's own
  store for mail, `~/.local/state/vdirsyncer/token_<name>` for calendars);
  enable both Gmail API and Calendar API on the client.
  `admin_policy_enforced` means the Workspace admin blocks unverified
  OAuth apps — that account then needs an admin-approved client (per-
  account client override: not wired up, extend when it happens).
* **Why does only the first line of a pass entry get used?** pass
  convention — password first, metadata below. Everything down the chain
  (pass-cache, okd-token, vpn.sh) trims to line one on purpose.
* **Pinentry on every sync?** It shouldn't be: `pass-cache` keeps decrypted
  first lines in the kernel keyring for a day. One pinentry after boot,
  silence after. gpg-agent TTLs stay short on purpose.
* **Timers auth-fail after a password change?** You forgot `pass-cache
  drop` — the cache serves the stale password for up to a day.
* **Meetings vs khal?** khal is the fast local view and personal events;
  anything with attendees, invitations or recurring-exception edits goes
  through Evolution (EWS handles iTIP, CalDAV via davmail does not).
* **Why is the maildir under `~/.unbacked`?** Gigabytes, churns every 5
  minutes, fully re-syncable from the servers — snapshot noise. OAuth
  tokens and calendars stay backed: tokens need a browser to recreate,
  calendars must stay consistent with their sync status.

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

## Fish functions and abbreviations

Autoloaded from `fish/functions/`; deps in parentheses are installed by
hand (see the pacman/AUR notes).

| Command | Does |
|---|---|
| `extract FILE` | unpack any archive by extension |
| `mkcd DIR` | `mkdir -p` && `cd` |
| `tarzst DIR` | pack a directory into `DIR.tar.zst` |
| `rarr DIR` | rar with 10% recovery record (AUR `rar`) |
| `parr DIR` | single par2 set (10%) over a directory — immutable exports leaving btrfs; repair with `par2 repair DIR.par2` (`par2cmdline`) |
| `parr-each DIR` | per-file par2 sets, incremental, reports orphans — for directories that keep changing |
| `parr-verify DIR` / `parr-repair DIR` | check / fix the per-file sets |
| `rhashr DIR` | `DIR.sha256` integrity audit, incremental via `rhash --update` (`rhash`) |
| `rhash-verify DIR` | verify against `DIR.sha256`, lists missing files |
| `zl-layout NAME` | attach-or-create a zellij session |
| `showfiles` / `hidefiles` | macOS Finder hidden-files toggle |

Abbreviations (`config.fish`):

| Abbr | Expands to | OS |
|---|---|---|
| `vim` | `nvim` | all |
| `kk` | `kubectl` | all |
| `ls` | `eza --icons --group-directories-first` | all |
| `news` | `yay -Pw` (Arch news) | linux |
| `mirrors-update` | `reflector … --save /etc/pacman.d/mirrorlist` | linux |
| `poweroff` / `reboot` | graceful `power` wrapper (closes windows first) | linux |
| `ql` | `qlmanage -p` (Quick Look) | macOS |
| `cpwd` | `pwd \| pbcopy` | macOS |
| `flushdns` | flush DNS cache + HUP mDNSResponder | macOS |
| `ports` | `lsof -iTCP -sTCP:LISTEN -n -P` | macOS |

## Notes

* fish functions live in `functions/` (autoloaded); macOS-only ones are
  excluded on other systems via `home/.chezmoiignore`.
* gpg: pinentry is picked per OS in `gpg-agent.conf.tmpl` (pinentry-mac on
  macOS, `/usr/bin/pinentry` elsewhere).
* limine: the deploy edits `/etc/default/limine` and `/boot/limine.conf` but
  does not regenerate boot entries — kernel cmdline changes take effect on the
  next kernel transaction (or run `limine-update` by hand).
