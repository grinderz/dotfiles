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
make dotfiles.merge/.config/foo/bar.conf            # three-way merge an edited file back
make dotfiles.merge-all                             # same, for everything that differs

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

Connections are multiplexed (`ControlMaster auto`, `ControlPersist 10m`):
the FIDO signature costs seconds with several tokens plugged in, a reused
socket costs nothing — measured 3.5-6 s per fresh connection against 37 ms
over an open one. `ssh -O exit <host>` drops a master that outlived its
network.

Commits are signed with ssh keys (`gpg.format = ssh`), and every machine
has its own YubiKey, so it signs and talks to the forges with its own
key. The private chezmoi.toml is identical everywhere, so the machine is
picked inside the templates: `personal_key` is the default and
`personal_key_by_host` overrides it per hostname,

```toml
personal_key = "~/.ssh/id_ed25519_sk_rk_personal-sa"
personal_key_by_host = { "<hostname>" = "~/.ssh/id_ed25519_sk_rk_personal-<machine>" }
```

which `config.personal.inc.tmpl` uses for `user.signingKey` and
`.ssh/config` for every `IdentityFile` — the forges, the home LAN and the
VPS alike — one key per machine,
no "device not found" from a token that is somewhere else. Taking a new
machine in: generate its key (`ssh-keygen -t ed25519-sk -O resident -O
application=ssh:personal-<machine> -f ~/.ssh/id_ed25519_sk_rk_personal-<machine>`),
upload the public key to GitHub and GitLab — as an authentication key and
again as a *signing* key, they are separate there — add the line to
`allowed_signers` below, and the hostname to the map.

The list of keys allowed to verify signatures is shared instead:
`~/.ssh/allowed_signers` is a symlink into the shared syncthing folder
(see above), so a key added on one machine reaches the others.
Every key of an identity goes in under the same principal — that is what
makes a commit signed on one machine verify on another; a retired key
keeps its line plus `valid-before="<yyyymmdd>"`, which git checks against
the commit date, so old history still verifies while the key can no
longer sign anything new. Each key also has to be uploaded to
GitHub/GitLab as a *signing* key, separate from an authentication key.
Without the syncthing folder the symlink dangles and verification stops
working, signing does not.

With two CCID YubiKeys plugged in, scdaemon can settle on the one without
OpenPGP keys (`gpg --card-status` then shows `[none]` for every key) and
every card operation has to switch cards first. Point it at the right one
without unplugging anything:

```sh
gpg --card-status                 # Serial number of the card it talks to
gpg-connect-agent 'scd serialno --demand=D27600012401000000060000000000000' \
                  'scd learn --force' /bye     # ...0006 + serial + 0000
```

If a prompt cannot be shown at all (`ssh sign request failed: No such file
or directory <Pinentry>` in `journalctl --user`), the agent came up without
a display: `systemctl --user restart gpg-agent.service`, then a fresh
terminal (fish runs `updatestartuptty`) keeps it that way.

## Shared state (syncthing folder `dotfiles`)

What is neither public enough for this repo nor secret enough for pass,
but has to be the same on every machine, lives in the syncthing folder
`dotfiles` (`~/sync/dotfiles`, shared with every device), and chezmoi
only puts symlinks in place:

| path | what |
|---|---|
| `chezmoi/chezmoi.toml` | the private template data below, so it no longer has to be copied between machines by hand |
| `ssh/allowed_signers` | git signing keys of every machine (see SSH / YubiKey) |
| `ssh/known_hosts` | host keys accepted once, trusted everywhere |
| `yubico/u2f_keys`, `u2f_keys_bio` | pam_u2f registrations for sudo and swaylock |
| `wallpapers/` | the set `sync-brave-wallpapers` fills (`-n` lists what it would copy) and sway, `lock` and the macOS autostart pick from |
| `claude/` | Claude Code auto memory of every synced checkout, work and personal (see the claude wrapper); the session transcripts live apart, in the `ai` folder below |

User units under `.config/systemd/user` are enabled by apply itself:
`.chezmoiscripts/run_onchange_after_systemd-user.sh` reloads the user
manager and runs `systemctl --user enable --now` for every deployed unit
that carries an `[Install]` section — the timers, `davmail`,
`goimapnotify`. Units without one (`mbsync.service`, the notify services,
`evolution-alarm-notify`) are started by their timer or by
`sway-session.target` and are left alone, and a session without a user
bus (plain ssh, no lingering) skips the script instead of failing the
apply. pyinfra stays out of this: it runs as root over ssh and owns
system state, `/etc` and system services.

`agent-bash-guard` is a `PreToolUse` hook (registered in the merged
`~/.claude/settings.json`): it denies a Bash call that pipes a download
into a shell, sets `LD_PRELOAD`/`BASH_ENV` and friends inline, reads a
private ssh key or a credentials file (`.netrc`, `.aws/credentials`,
`.docker/config.json`), writes inside `.git` by hand, deletes `~` or `/`
recursively, or formats a device. Everything else passes to the normal
permission flow — `sed -i`, `tee`, `find -exec` and `~/.ssh/config` stay
allowed on purpose, since a guard that fires on daily work only teaches
everyone to work around it.

Taskwarrior splits work, personal and family life by the project a task
belongs to (`work.*`, `personal.*`, `family.*`), with a context per
sphere in `taskrc`: the `read` filter decides what a report shows, the
`write` one stamps the project on whatever is added while that context is
on, so `task context work` is the only thing to remember. `personal` also
matches tasks with no project, which is where everything added before the
split still lives. `task context none` shows all three again, and
taskwarrior-tui has the same switch behind its context menu.

Machine differences stay in the templates (`.chezmoi.os`, and maps keyed
by `.chezmoi.hostname` such as `personal_key_by_host`), not in
separate copies of the file. Editing the same key on two machines while
one of them is offline leaves a syncthing conflict copy to merge by hand,
which is the price for not copying anything.

Bootstrapping a machine therefore starts with syncthing: install it,
accept the folder, and only then `chezmoi init`, since the config it
reads is a symlink into that folder.

### Session transcripts (syncthing folder `ai`)

Transcripts are a different kind of data than the memory beside them:
tens of MB each, and a full record of the session — whole file contents,
command output, whatever was pasted. They get their own folder,
`~/sync/ai` (`claude/<project>/<session>.jsonl`), shared with the two
desktops only, so `claude --resume` finds yesterday's session on either
of them while the backup machines never see it. The `memory` symlink
inside each project points back into the `dotfiles` folder and is made
per machine by the wrapper, so syncthing ignores it.

`claude-prune-sessions` drops the ones nobody came back to. Age counts
from the last *use*: resuming appends to the transcript, so its newest
record marks the last visit (`/home` is `noatime`, the file system does
not track reads). It reports and deletes nothing unless told to:

```sh
claude-prune-sessions                  # what is older than 90 days
claude-prune-sessions --days 30        # stricter window
claude-prune-sessions --days 30 --apply
```

A session used within the last hour is never a candidate, so a running
session cannot prune itself.

## Private data

Identity (name/emails/signing keys), work and VPS specifics never enter the
repo. Templates guard on machine-local data from
`~/.config/chezmoi/chezmoi.toml`:

```toml
[data.work]
name = "..."
email = "..."
git_signing_key = "~/.ssh/..."     # work signs with its own YubiKey
git_includes = """..."""           # verbatim [includeIf] git config blocks
okd_url = "..."

[data.personal]
name = "..."
email = "..."
personal_key = "~/.ssh/..."

# every ssh host is a table, rendered by private_dot_ssh/private_config.tmpl:
# data.personal.hosts (home LAN), .git_hosts (forges), .oth_hosts,
# data.work.hosts, data.vps.hosts. Hosts that name no key of their own
# are collected into one block that hands them personal_key, so the
# per-host blocks carry only what differs from the ssh defaults.
[[data.personal.hosts]]
name = "srv1-example"       # the only required field
hostname = "10.0.0.9"       # default: name
user = "admin"              # default: root
port = 2222                 # default: 22
key = false                 # false drops pubkey auth, a path pins another key
agent = true                # adds IdentityAgent SSH_AUTH_SOCK
extra = ["KexAlgorithms ..."]   # copied verbatim into the block

[data.desktop]
wallpaper_dir = "~/pictures/wallpapers/brave"   # sway bg, swaylock bg, sync script
latitude = "51.48"                              # wlsunset night light
longitude = "-0.01"
output_left = "Make Model Serial"               # kanshi profile + sway workspace pins
output_right = "Make Model Serial"
traffic_url = "https://..."                     # regional traffic XML feed, waybar module
traffic_map_url = "https://..."                 # map page opened on click

[data.jetbrains]                                # see JetBrains vmoptions
options = ["-XX:MaxRAMPercentage=50"]           # verbatim vmoptions lines
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
  other than the laptop also override `conservation_node` (ideapad sysfs path
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
  `udisks2` (usb-storage waybar module), `zathura` +
  `zathura-pdf-mupdf` (the viewer `application/pdf` opens in: vim keys,
  and `recolor` inverts the page rather than dimming the window. The
  backend is a separate package -- zathura without one starts and shows
  nothing. sioyek was the other candidate and lost on weight: it is a Qt
  app and would have pulled ~250 MB of Qt6 onto a desktop that has none);
  before the first apply, generate
  the locale the waybar clock names (`en_DK.UTF-8`: English with ISO dates
  and a Monday-first week, which is what the `%V` week number counts) —
  `sudo sed -i 's/^#en_DK.UTF-8 UTF-8/en_DK.UTF-8 UTF-8/' /etc/locale.gen
  && sudo locale-gen`; without it waybar disables the whole clock module
  with `locale::facet::_S_create_c_locale name not valid`, and a running
  waybar needs a restart rather than a reload to see a locale generated
  under it;
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
  (used by vdirsyncer directly and mirrored into oama's config). Apply
  enables the units itself (see below), goimapnotify among them: IMAP
  IDLE push, new mail starts mbsync.service at once and the timer stays
  as the fallback. Sending goes
  through `msmtp` (package) via the vendored `msmtpq`: a failed send is
  queued under `~/.local/state/msmtpq/queue`, retried by mbsync.service
  and counted in the waybar mail module until it leaves; sends are
  logged to the journal (`journalctl --user -t msmtp`). Then
  a one-time `oama authorize google <email>` per Google mail account and
  `vdirsyncer discover` (browser OAuth per google calendar), then
  `enable --now vdirsyncer.timer`. Address completion in the composer
  (`mail-addr`, aerc's `address-book-cmd`) reads the table that
  `maildir-rank-addr` (AUR) builds from the maildir, so the people written
  to most and most recently come first instead of alphabetically, rebuilt
  twice a day by its timer. Without
  the package the script falls back to a notmuch query, and either way the
  Exchange address list (`ewsctl contacts`) is appended for colleagues
  never written to, cached per query for a week because it costs ~2 s.

### Mail password rotation

The mail and calendar timers read secrets through `pass-cache`: a kernel
user-keyring cache in front of pass, so the gpg pinentry does not show up
on every 5-minute sync. The 24h TTL slides on every hit, so an entry the
timers keep asking for expires only after the machine has been off; pass
remains the only source of truth — the cache never touches disk and dies
with the session.

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
  first lines in the kernel keyring, and every hit pushes the day-long
  expiry out. One pinentry after boot, silence after. gpg-agent TTLs stay
  short on purpose, so interactive gpg (commit signing) still asks.
* **Timers auth-fail after a password change?** You forgot `pass-cache
  drop` — the cache serves the stale password until the timers stop asking
  for it.
* **Meetings vs khal?** khal is the fast local view and personal events;
  anything with attendees, invitations or recurring-exception edits goes
  through Evolution (EWS handles iTIP, CalDAV via davmail does not).
* **Why is the maildir under `~/.unbacked`?** Gigabytes, churns every 5
  minutes, fully re-syncable from the servers — snapshot noise. OAuth
  tokens and calendars stay backed: tokens need a browser to recreate,
  calendars must stay consistent with their sync status.

### pass into Bitwarden

Some passwords have to exist outside the terminal — the phone, a browser on
someone else's machine. `pass-rbw-sync` pushes a hand-picked subset of the
stores into Bitwarden through `rbw` (package `rbw`, the unofficial Rust
client — one agent, no Node startup cost per call; `jq` for the comparison):

```sh
rbw config set email <address> && rbw register && rbw login
pass-rbw-sync -n                 # dry run: would create / would update / unchanged
pass-rbw-sync                    # ~/.config/pass-rbw-sync.list
pass-rbw-sync ~/.config/other.list
```

`rbw` asks for the master password through a pinentry; `pinentry-pass`
is one that reads it from pass instead (`sync/bitwarden.com` in the
personal store by default, `PINENTRY_PASS_ENTRY` / `PINENTRY_PASS_CMD` to
change), so unlocking costs a gpg prompt at most, and gpg-agent caches
that one:

```sh
rbw config set pinentry ~/.local/bin/pinentry-pass
```

Which entries travel is data, not a hand-written file: `[[data.rbw.entries]]`
in the private chezmoi.toml renders `~/.config/pass-rbw-sync.list` (schema in
the header of `private_pass-rbw-sync.list.tmpl`, commented example at the
bottom of the toml). Without the table the list is not created at all
(`home/.chezmoiignore`) and the script only runs against a list passed as an
argument.

The store is per entry, not per run: `cmd` is the command the entry is read
with — `passp` (default), `passw`, or plain `pass` against whatever
`PASSWORD_STORE_DIR` says — and it also picks the Bitwarden folder: `passp`
entries land under `personal/`, `passw` under `work/`, and the entry's pass
directory becomes the subfolder (`bank/paypal.com` → `personal/bank`), so
the store's layout carries over. `folder` overrides the subfolder (`"-"`
for the root itself), roots are overridable with `[data.rbw.folders]`.
Site-as-directory entries (`oth/example.org/password`) want `name` and `folder`
spelled out, or the item is called `password`. Name, user and folder together identify an item, so
`GitHub` in both stores stays two items. Username and URIs come from the
pass entry itself — `login:` (`user:`, `username:`, falling back to
`email:`) and every `url:` (`uri:`) line, any case — so browser and phone
autofill work; `user` and `uri` in the toml override them. TOTP and custom
fields stay behind: rbw cannot write them. Whether work credentials belong in a personal vault is a
policy question, not a technical one.

The sync is one-way and pass wins: each run overwrites the Bitwarden copy, so
an edit made in the web vault is lost on the next run. Items whose password
and note already match are skipped, so a run costs nothing on the other
clients. `rbw edit` can only replace the password and the note — username,
URI and folder are set once when the item is created (and TOTP secrets never
travel), so a changed user or folder means removing the item in Bitwarden
and letting the next run recreate it. Items under `personal/` or `work/` that
no list line claims are printed as `extra` at the end and left alone; an
ambiguous match aborts the run rather than creating a duplicate. There is no
timer: `rbw unlock` wants a human, and this is a rotate-time action anyway.

### Car status in the bar

`starline-status` shows the alarm and car state from the StarLine cloud in
waybar (`custom/starline`, read only: lock icon armed/disarmed, warning
icon while an alarm zone is triggered, the details in the tooltip; click
opens the last position on a map, right click the web cabinet). It speaks the developer.starline.ru API, so
it needs an application registered at https://my.starline.ru/developer
and the StarLine ID login, both in pass; `[data.starline]` in the private
chezmoi.toml names the entries and renders
`~/.config/starline-status/config.toml` (nothing renders without it):

```toml
[data.starline]
app  = "car/starline.ru/app"        # password: app_secret, "login:" line: app_id
user = "car/starline.ru/password"   # password: StarLine ID password, "login:" line: phone or email
cmd  = "passp"                      # optional, the pass command the entries are read with
```

```sh
starline-status login    # once per new place: the server sends an SMS code
starline-status          # what waybar runs; hidden without the config
starline-status raw      # the device json, for new tooltip fields
```

The session cookie and the long-lived slid token live in
`~/.local/state/starline-status/`; the daily cookie expiry is renewed with
the token alone, so pass/gpg is only touched on a full login. The module
shows a warning and asks for `login` when even that fails. Needs
`python-httpx`.

The account gets about 1000 API calls a day; past that every call answers
429 "Exceeding limit" until the window rolls over. The module then keeps
showing the last good state (cached in the same directory) with a
warning and makes no further calls that tick — a 429 is never taken for
a lost session, since the renew and login it would trigger only burn more
quota. Budget at the 5-minute interval: one call per tick, plus the OBD
block (fuel, mileage, DTC) every three hours, about 300 a day.

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

### Claude Code state shared between machines

Claude Code keeps sessions (`--resume`), auto memory and todos per project
under `~/.claude/projects/<name>`, and derives `<name>` from the absolute
working directory, so the same checkout gets a different name on every
machine. `~/.local/bin/claude` (a wrapper in front of the real binary,
rendered only when `[[data.claude.sync]]` entries exist) names the project
after its path relative to the root's parent instead
(`~/src/work/acme/app` -> `src-work-acme-app`) and points that name at
`<dir>/<name>` inside the entry's syncthing folder (and the auto memory at
`<memory_dir>/<name>/memory`, linked in), so the state follows the
project. Directories outside the roots are untouched. The wrapper has
to set `CLAUDE_CONFIG_DIR`, which also moves the global config (login,
onboarding, per-project trust) to `~/.claude/.claude.json`; that path is
kept as a symlink to `~/.claude.json` so nothing asks to log in twice.

Sharing another tree takes one entry in the private chezmoi.toml, which
is itself synced, so it is written once and not per machine:

```toml
# paths relative to $HOME
[[data.claude.sync]]
root = "src"                        # the whole tree, at any depth below it
dir  = "sync/ai/claude"             # transcripts (the two desktops)
memory_dir = "sync/dotfiles/claude" # auto memory (every device); defaults to dir
```

A root covers everything under it, so `~/src` is one entry rather than one
per checkout; further entries are for trees elsewhere (notes, vaults) or
for one that needs different folders. A root that does not exist on a
machine simply never matches there. The project name is the path from the root's *parent*, so
`~/src/work/acme/app` becomes `src-work-acme-app` and each directory you
start claude in is its own project, exactly as Claude Code splits them by
absolute path.

Then `make dotfiles.apply` on each machine — that is what re-renders the
wrapper — and move whatever state Claude already keeps for that tree,
before the first run there (the wrapper refuses to run while a real
directory sits where its symlink goes). A checkout at `~/src/foo/bar`
becomes `src-foo-bar`: the path relative to the root's *parent*, slashes
turned into dashes, while the old name is the absolute path the same way:

```sh
name=src-foo-bar; old=~/.claude/projects/-home-me-src-foo-bar
mkdir -p ~/sync/ai/claude/$name ~/sync/dotfiles/claude/$name
mv "$old"/memory ~/sync/dotfiles/claude/$name/
mv "$old"/* ~/sync/ai/claude/$name/          # transcripts and their dirs
rmdir "$old"                                  # the wrapper makes the links
```

Working on both machines at the same time is
fine for sessions (one file each) but can leave a syncthing conflict copy
of `memory/MEMORY.md`.

### JetBrains vmoptions

The IDE settings themselves stay out of this repo (JetBrains Backup and
Sync carries them), but VM options are not part of that sync, so the user
vmoptions file is written by chezmoi instead. The lines are listed
verbatim in the private toml:

```toml
[data.jetbrains]
options = ["-XX:MaxRAMPercentage=50"]   # every IDE on every machine

[data.jetbrains.per_product]      # key = config directory without the version
GoLand   = ["-Xmx8192m"]
DataGrip = ["-Xmx4096m"]

[data.jetbrains.per_host]         # the private toml is shared by syncthing, so
"<hostname>" = ["-Xmx4096m"]      # hardware sizes and machine-local paths
                                  # go by hostname
```

`run_after_jetbrains-vmoptions.sh` writes one marked block into the user
vmoptions file of the newest config directory of every IDE —
`~/.config/JetBrains/GoLand2026.2/goland64.vmoptions`, on macOS
`~/Library/Application Support/JetBrains/GoLand2026.2/goland.vmoptions`.
An IDE that is no longer installed is skipped (its launcher has to exist),
and older version directories are left as they are. Inside the block the
order is `options`, `per_product`, `per_host`; the JVM takes the last of
two conflicting values, so the more specific key wins.

The launcher concatenates that file with the one in the IDE's own `bin/`,
so the block carries the extra lines alone and the defaults stay — with
two exceptions it makes itself: `-XX:InitialRAMPercentage` here drops the
packaged `-Xms`, `-XX:(Max|Min)RAMPercentage` drops `-Xmx`, and any
`-XX:+...GC` drops the packaged GC flags. Options added by hand or through
`Help | Edit Custom VM Options` live outside the markers and are left
alone.

After an IDE upgrade, start the new version once (it creates the config
directory), then `chezmoi apply` and restart it — the vmoptions file is
per version, and the script writes to the newest directory only. Without
the table nothing is rendered at all.

### macOS window manager and bar

AeroSpace and SketchyBar stand in for sway and waybar: same keys, same
workspace numbers and labels, same app-to-workspace assignments, the bar
at the bottom in the same blue. Same finger too: sway's `$mod` is Super,
physically the Cmd key, so Karabiner-Elements swaps Cmd and Ctrl on the
external keyboard (`.config/karabiner/karabiner.json`, rules scoped to
that device) and AeroSpace binds `ctrl`. The physical Ctrl then carries
the app shortcuts (Cmd+C/V under the Ctrl key, Linux-style, Cmd+Tab
under Ctrl+Tab), and `alacritty.toml` turns the Cmd+<key> the terminal
now sees back into control characters, so `^C`, `^R`, `^W` work as
before (a real ctrl in the terminal is no option: AeroSpace grabs its
ctrl keys globally and would take `^R` for resize mode); copy/paste in
the terminal is Cmd+Shift+C/V, physically Ctrl+Shift+C/V like foot.
AeroSpace grabs its keys globally: native Ctrl shortcuts of macOS apps
(Ctrl+Tab tab cycling,
Emacs keys in text fields) now sit on the physical Super and the bound
ones (`ctrl-tab`, `ctrl-hjkl`, ...) are gone; browser tabs cycle with
Cmd+Shift+[ ] instead. The builtin keyboard has no swap: physical Ctrl
drives the windows there. Karabiner sits below WindowServer, so it is
also the place to swallow a system shortcut macOS will not let go of
(Cmd+Tab, Cmd+Alt+Esc): a manipulator with an empty `to`.
Configs: `.config/aerospace/aerospace.toml` (chezmoi template) and
`.config/sketchybar/`. Once per machine:

```sh
brew tap FelixKratz/formulae
brew install sketchybar jq blueutil tesseract zbar macmon
brew tap ungive/media-control && brew install media-control   # now playing
brew install --cask nikitabobko/tap/aerospace sf-symbols font-sketchybar-app-font raycast
brew install --cask karabiner-elements    # pkg: run in a real terminal, asks sudo
make dotfiles.apply
brew services start sketchybar    # launchd, survives aerospace reloads
open -a AeroSpace                 # registers itself as a login item
```

The workspace swipe has no package; it is built from source once per
machine (the config it reads comes from chezmoi):

```sh
git clone https://github.com/acsandmann/aerospace-swipe ~/.local/share/aerospace-swipe
cd ~/.local/share/aerospace-swipe
make install                      # builds, ad-hoc signs, loads the launch agent
```

Run that `open` from a plain terminal, never from a shell inside Claude
Code (or any tool that marks its children): `open` hands its environment
to the app and AeroSpace hands it to every terminal it spawns
(`inherit-env-vars`), so a `claude` started there sees
`CLAUDE_CODE_CHILD_SESSION` and stops saving transcripts ("Transcript
saving is off"). Relaunch with a clean environment when in doubt:

```sh
pkill -x AeroSpace
launchctl submit -l aerospace-relaunch -- /usr/bin/open -a AeroSpace
launchctl remove aerospace-relaunch
```

OCR (`ctrl-o`, `ocr-mac`) wants the Russian model next to the English
one in a dir that survives brew upgrades:

```sh
mkdir -p ~/.local/share/tessdata
curl -sfL -o ~/.local/share/tessdata/rus.traineddata \
    https://github.com/tesseract-ocr/tessdata_fast/raw/main/rus.traineddata
ln -sf /opt/homebrew/opt/tesseract/share/tessdata/eng.traineddata ~/.local/share/tessdata/
```

then in System Settings:

* Karabiner-Elements (`brew install --cask karabiner-elements`, a pkg,
  needs sudo in a real terminal): approve its driver extension and
  grant what its settings window asks for. Karabiner owns
  `karabiner.json` and rewrites it on every settings change, so the
  rules come from a chezmoi `modify_` script that merges them into
  whatever is there (no diff after a round trip, no `--force`). No
  Modifier Keys swap in macOS on top of it
* Privacy & Security → Accessibility: allow AeroSpace (it asks on first run)
* optional: Control Center → "Automatically hide and show the menu
  bar": Always (the bar carries the same information, the input source
  in the `keyboard` item; AeroSpace keeps the windows clear of the
  native menu bar either way)
* Desktop & Dock: "Automatically rearrange Spaces based on most recent
  use" off, "Displays have separate Spaces" on
* aerospace-swipe is sway's four-finger workspace swipe: a launchd
  daemon that reads `.config/aerospace-swipe/config.json` (chezmoi), so
  the settings are a file rather than a `defaults` domain. It needs
  Accessibility, and asks for it on first start. Four fingers only work
  with `swipe_tolerance` above zero, which the shipped config sets to 2
  and no documentation mentions: the armed state drops the gesture when
  any finger fails to move its `min_step` within a frame, and four
  fingers never move in lockstep — with the stock `0` a swipe landed
  about one time in four. A rebuild changes the ad-hoc
  signature, which invalidates the Accessibility grant without asking
  again: `tccutil reset Accessibility com.example.swipe`, then
  `make restart`, and approve the prompt. It survives an AeroSpace
  restart, unlike the SwipeAeroSpace app it replaced (that one never
  reconnected to the socket, which is why `autostart-mac` used to
  start it after AeroSpace). Its event tap is listen-only, so the swipe
  also reaches whatever is underneath, and a browser reads a horizontal
  one as back/forward. The fix is to let macOS swallow it first: the
  system four-finger horizontal gesture is left **on**
  (`TrackpadFourFingerHorizSwipeGesture = 2` on both trackpads and
  `com.apple.trackpad.fourFingerHorizSwipeGesture` in globals, applied
  after a re-login), and since every display holds a single Space it has
  nowhere to switch and does nothing visible. The daemon reads raw
  touches through MultitouchSupport, a layer below the event system, so
  it still fires — and two-finger back/forward keeps working in the
  browser, which turning page-swipe navigation off there would have
  cost. A display with a second Space breaks the trick: any app going
  full screen makes one, and then the four-finger swipe walks into it.
  The three-finger swipes (Mission Control, App Exposé) stay off, as
  does three-finger drag (it ate the first fingers of a swipe)
* Media keys stay with the bar's `media` item instead of opening Music:
  macOS routes them through `com.apple.rcd`, which launches the app on
  the first press. `Library/LaunchAgents/com.user.disable-rcd.plist`
  (chezmoi, macOS only) unloads that agent at login; it takes effect on
  the next login, or right away with
  `launchctl unload -w /System/Library/LaunchAgents/com.apple.rcd.plist`
* Low Power Mode from the bar (`lowpower` toggle) needs `pmset` without
  a password, `sudo visudo -f /etc/sudoers.d/lowpower`:
  `<user> ALL=(root) NOPASSWD: /usr/bin/pmset -a lowpowermode 0, /usr/bin/pmset -a lowpowermode 1`;
  without it the click opens the Battery settings
* The Focus toggle in the bar (`focus`, waybar's notify/DND) works
  through the Focus menu bar item, which has to be shown always:
  `defaults -currentHost write com.apple.controlcenter FocusModes -int 18`
  and `killall ControlCenter` (Control Center → Focus → "Always Show in
  Menu Bar"). The bar clones that item's picture (the only readable
  state, its accessibility attributes never change), a click opens its
  popover and flips the Do Not Disturb checkbox, so
  sketchybar goes under Privacy & Security → Accessibility (without it
  the click opens the Focus settings) and under Full Disk Access for
  the bell's color and popup, which read the DoNotDisturb assertions
  store under ~/Library (re-grant after a brew upgrade moves the
  binary). A Shortcut would be cleaner, but importing one needs an
  iCloud login, and the system DND hotkey ignores synthetic key
  events.

Optional overrides in the private `chezmoi.toml`, all under
`[data.desktop]`:

```toml
aerospace_mod = "alt"                            # default "ctrl" (see above)
aerospace_monitor_odd  = ["dell.*", "samsung.*", "main"]  # 1 3 5 7 9: as sway,
aerospace_monitor_even = ["2", "main"]                    # 2 4 6 8 10: right Dell
```

The bar runs the same module scripts as waybar (`weather`,
`gitlab-status`, `jira-status`; the traffic and car modules stay on
Linux): they
print waybar JSON and `sketchybar/plugins/waybar.sh` paints it, text as
the label, class as the color from `waybar/style.css`, tooltip as a popup
under the mouse. The scripts stay portable through two helpers in
`~/.local/bin`: `open-url` (xdg-open / open) and `menu-pick` (fuzzel /
an AppleScript list dialog) for the pick menus. Each module hides itself
without its setup, so on the Mac gitlab needs `glab auth login` and jira
the `jira-cli` config and token. Bluetooth comes from `blueutil` (brew), what is
playing from `media-control` (the mediaremote-adapter; sketchybar's own
`media_change` event is dead on macOS 15.4+ where Apple locked
MediaRemote down), polled every 5 s, a click toggles play/pause. There is
no tray: sketchybar can clone menu bar extras as images, but the clones
take clicks nowhere and the builtin screen has no room for them beside
the window title, so the native menu bar (one mouse move to the top
edge) does that job. Syncthing has a module of its own
(`syncthing-status`, both bars): hidden while every folder is idle and
every device is connected and caught up, otherwise it counts what is
left to pull, the devices that are away (`⊘`) and the folders in error,
with the breakdown in the tooltip; the same script prints a table for
the terminal (`syncthing-status show`) and opens the web GUI on click,
and it reads the address and the API key from syncthing's own
`config.xml`. The wired link, the toggles (keep-awake via `caffeinate`,
Low Power Mode, Focus), the power menu, the recording indicator, the system health
(`system-stats-mac`: temperature on the bar, cpu/load/mem in the popup,
sensors read by macmon without root) and the calendar / battery-time /
Wi-Fi-signal popups are small plugins of their own.

The sway session extras have macOS scripts of their own, all under
`~/.local/bin` and bound in `aerospace.toml` (notifications through
`notify-mac`, terminal-notifier in place of notify-send): `screenshot-mac` (area,
clipboard, window, monitor; files land in `XDG_SCREENSHOTS_DIR`, the
same path as on Linux), `ocr-mac`, `qr-mac`, `aerospace-bindings` (the
cheatsheet, fzf in a floating terminal), `screen-record-mac` (one key
starts and stops; the focused window's frame or the monitor, since
screencapture has no interactive video area), `scratch-term-mac` (the
drop-down terminal, parked on the hidden workspace S and centered with
System Events on every show) and `autostart-mac` (after-startup-command:
a random wallpaper when the wallpaper dir exists on the machine, the
`dev` zellij and `cli` terminals on workspaces 2 and 1). Browser, chats
and notes start as Login Items and the window rules place them. The
launcher (`ctrl-d`) is Raycast; Spotlight is switched off on this
machine, indexing (`sudo mdutil -a -i off && sudo mdutil -a -E`) and
both shortcuts under Keyboard > Keyboard Shortcuts > Spotlight. The
lock (`ctrl-esc`) is the system Lock Screen as a synthetic keystroke,
Sequoia has no CGSession any more.

Not carried over: focus-parent and mod+drag of tiles (AeroSpace has
neither), media/brightness keys (macOS handles them natively), the mail
stack, usb-storage (MountMate does it from the menu bar) and the battery charge
limit (no CLI on macOS, AlDente if ever).

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
* `dotfiles.merge*` needs a merge tool: chezmoi defaults to `vimdiff`, which
  neovim does not provide, so the private chezmoi.toml names one. A custom
  command gets no default arguments, hence the explicit three files —
  destination (what is in `$HOME`), source (the file in the repo), target
  (what chezmoi would render). Edit the source one.

  ```toml
  [merge]
  command = "nvim"
  args = ["-d", "{{ .Destination }}", "{{ .Source }}", "{{ .Target }}"]
  ```
* limine: the deploy edits `/etc/default/limine` and `/boot/limine.conf` but
  does not regenerate boot entries — kernel cmdline changes take effect on the
  next kernel transaction (or run `limine-update` by hand).
