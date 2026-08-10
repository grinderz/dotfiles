# dotfiles

Personal machine configuration. Successor to `desktop-playbook` (archived, Ansible).

Two tools, split by scope:

* **chezmoi** (`home/`) — user dotfiles: fish, ssh client, etc.
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
make infra.linux.tb_6_dock deploy=systemd                 # remote over ssh
```

`--limit` value (the last target component) is a host name or an inventory
group. Remote sudo: pyinfra prompts for the password interactively.

## SSH / YubiKey

Auth key is ed25519-sk (FIDO2). paramiko cannot read sk key files and
gpg-agent refuses to host them, so each `infra.linux.*` run wraps pyinfra in a
throwaway OpenSSH agent with the key loaded (`PYINFRA_SSH_KEY` in the
Makefile). Requires pyinfra >= 3.10 (agent-held sk keys, PR 1858).

## Private data

Work and VPS specifics never enter the repo. Templates guard on machine-local
data from `~/.config/chezmoi/chezmoi.toml`:

```toml
[data.work]
okd_url = "..."
ssh_hosts = """..."""   # verbatim ssh Host blocks

[data.vps]
ssh_hosts = """..."""
```

Machines without a table simply render without those sections
(`{{ if hasKey . "work" }}`).

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

## Migration status

| old role | new location | status |
|---|---|---|
| fish | `home/.../fish/` | done (pilot) |
| sshclient | `home/private_dot_ssh/` | done |
| pacman | `infra/deploys/pacman.py` | done (pilot) |
| systemd | `infra/deploys/systemd.py` | done (pilot) |
| sublime | `infra/deploys/sublime.py` | done |
| everything else | — | still in desktop-playbook |

Notes:

* `pacman.conf` NoExtract: was N ansible marker blocks, now one pyinfra block.
  Old `# BEGIN/END ANSIBLE MANAGED BLOCK ...` markers must be removed by hand once.
* fish functions live in `functions/` (autoloaded); macOS-only ones are
  excluded on other systems via `home/.chezmoiignore`.
* OpenBSD hosts stay on the old repo until migrated.
