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

[data.vps]
ssh_hosts = """..."""
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
3. `chezmoi init --apply --source ./home` as the user

## Layout

```
home/                  # chezmoi source dir
infra/
├── linux.py           # inventory per group; group name = file name
├── group_data/        # defaults per group (was roles/*/defaults)
├── deploys/           # one file per former role
├── templates/         # jinja2, reused from ansible almost verbatim
└── util.py            # block_with_diff: files.block + textual diff output
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
* **btrbk** — before: create the target directory on the mounted archive
  disk (btrbk requires it to exist);
  ssh target (if enabled): `ssh-keygen -t ed25519 -N '' -f /etc/btrbk/ssh/id_ed25519`
  and authorize the pubkey on the receiver (`ssh_filter_btrbk.sh` forced command)
* **git** (chezmoi) — after: delete the old work include from
  `~/.config/git/`, renamed to `config.work.inc`
* **bin** (chezmoi) — after, macOS: delete `/usr/local/bin/okd-token.sh` from
  the old ansible role, superseded by `~/.local/bin/okd-token.sh`
* **openconnect** — after, macOS: delete old `/usr/local/bin/vpn-*.sh`,
  superseded by `~/.local/bin/vpn-*.sh`

## Notes

* fish functions live in `functions/` (autoloaded); macOS-only ones are
  excluded on other systems via `home/.chezmoiignore`.
* gpg: pinentry is picked per OS in `gpg-agent.conf.tmpl` (pinentry-mac on
  macOS, `/usr/bin/pinentry` elsewhere).
* limine: the deploy edits `/etc/default/limine` and `/boot/limine.conf` but
  does not regenerate boot entries — kernel cmdline changes take effect on the
  next kernel transaction (or run `limine-update` by hand).
* OpenBSD hosts stay on the old repo until migrated.
