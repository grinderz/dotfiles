SHELL := /usr/bin/env bash -o errtrace -o pipefail -o noclobber -o errexit -o nounset

CHEZMOI_SRC := $(CURDIR)/home

# --- dotfiles (chezmoi) ---

dotfiles.diff:
	chezmoi diff --source $(CHEZMOI_SRC)

dotfiles.apply:
	chezmoi apply --source $(CHEZMOI_SRC) $(args)

# usage: make dotfiles.add/.config/fish/config.fish  (path relative to $HOME)
dotfiles.add/%:
	chezmoi add --source $(CHEZMOI_SRC) $(HOME)/$* $(args)

# --- infra (pyinfra) ---
# usage: make infra.linux.tb-6-dock2-mokin-3707 deploy=pacman args="--dry"
#
# paramiko cannot read ed25519-sk key files and gpg-agent refuses to host
# them, so each run gets a throwaway OpenSSH agent with the sk key loaded
# (pyinfra >= 3.10 / PR 1858 makes agent-held sk keys work)
PYINFRA_SSH_KEY := $(HOME)/.ssh/id_ed25519_sk_rk_personal-ansible

infra.linux.%:
	cd infra && ssh-agent bash -c 'ssh-add -q $(PYINFRA_SSH_KEY) && pyinfra --diff --limit $* linux.py deploys/$(deploy).py $(args)'

# --- infra, local machine only (no ssh, no agent) ---
# usage: make infra.local.linux.local deploy=pacman args="--dry"

infra.local.linux.%:
	cd infra && pyinfra --diff --limit $* linux.py deploys/$(deploy).py $(args)
