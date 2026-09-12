SHELL := /usr/bin/env bash -o errtrace -o pipefail -o noclobber -o errexit -o nounset

CHEZMOI_SRC := $(CURDIR)/home

# every target here is a command, not a file
.PHONY: setup.pyinfra setup.pyinfra.upgrade lint.shellcheck lint.ruff lint \
	install.export install.validate dotfiles.diff dotfiles.apply dotfiles.merge-all

# --- setup ---

setup.pyinfra:
	uv tool install pyinfra

setup.pyinfra.upgrade:
	uv tool upgrade pyinfra

# --- lint ---
# shell scripts: everything with a sh/bash shebang except chezmoi
# templates (jinja braces are false positives for shellcheck) and the
# msmtpq scripts vendored from msmtp

lint.shellcheck:
	find home/dot_local/bin install -type f ! -name '*.tmpl' \
		! -name 'executable_msmtpq' ! -name 'executable_msmtp-queue' \
		-exec grep -lE '^#!/(usr/)?bin/(env )?(sh|bash)' {} + | xargs shellcheck

lint.ruff:
	uvx ruff check infra

lint: lint.shellcheck lint.ruff

# --- reproducible install (install/) ---
# refresh the reference exports from the live system; subvolumes.map and
# mkinitcpio.conf.template stay hand-maintained (see install/README.md)

install.export:
	@test "$$(uname -s)" = Linux || { echo "error: linux-only target" >&2; exit 1; }
	pacman -Qqen >| install/export/packages-native.txt
	pacman -Qqem >| install/export/packages-foreign.txt
	systemctl list-unit-files --state=enabled --no-legend | awk '{print $$1}' >| install/export/enabled-units.txt
	systemctl list-units --type=service --state=running --no-legend --plain | awk '{print $$1}' | sort >| install/export/running-services.txt
	systemctl list-units --type=timer --state=active --no-legend --plain | awk '{print $$1}' | sort >| install/export/timers.txt
	flatpak list --app --columns=application >| install/export/flatpaks.txt
	@# per-app permission overrides: the files themselves, user scope then
	@# system scope, each under a "# <scope> <app>" header
	{ for f in $$HOME/.local/share/flatpak/overrides/*; do \
		[ -f "$$f" ] || continue; \
		printf '# user %s\n' "$${f##*/}"; cat "$$f"; echo; \
	done; for f in /var/lib/flatpak/overrides/*; do \
		[ -f "$$f" ] || continue; \
		printf '# system %s\n' "$${f##*/}"; cat "$$f"; echo; \
	done; } >| install/export/flatpak-overrides.txt
	cd install/export && while IFS="$$(printf '\t')" read -r _ mp _; do \
		rmp=$${mp//@USER@/$$USER}; \
		printf '%s\t%s\n' "$$(stat -c '%U:%G %a' "$$rmp" 2>/dev/null || echo missing)" "$$mp"; \
	done < subvolumes.map | sed "s/\b$$USER\b/@USER@/g" >| subvolume-perms.txt
	bash install/unbacked-links.sh --scan >| install/export/unbacked-links.map
	git diff --stat -- install/export

install.validate:
	bash install/validate.sh

# --- dotfiles (chezmoi) ---

dotfiles.diff:
	chezmoi diff --source $(CHEZMOI_SRC)

dotfiles.apply:
	chezmoi apply --source $(CHEZMOI_SRC) $(args)

# usage: make dotfiles.add/.config/fish/config.fish  (path relative to $HOME)
dotfiles.add/%:
	chezmoi add --source $(CHEZMOI_SRC) $(HOME)/$* $(args)

# three-way merge for a file edited in place: source, target and the last
# applied state go into $EDITOR (vimdiff by default), so a hand-tweaked
# config comes back into the repo without losing template markup
# usage: make dotfiles.merge/.config/fish/config.fish  (path relative to $HOME)
dotfiles.merge/%:
	chezmoi merge --source $(CHEZMOI_SRC) $(HOME)/$* $(args)

# same, for every file that differs from the source
dotfiles.merge-all:
	chezmoi merge-all --source $(CHEZMOI_SRC) $(args)

# --- infra (pyinfra) ---
# usage: make infra.linux.<host> deploy=pacman args="--dry"
#
# paramiko cannot read ed25519-sk key files and gpg-agent refuses to host
# them, so each run gets a throwaway OpenSSH agent with the sk key loaded
# (pyinfra >= 3.10 / PR 1858 makes agent-held sk keys work)
PYINFRA_SSH_KEY := $(HOME)/.ssh/id_ed25519_sk_rk_personal-ansible

infra.linux.%:
	cd infra && ssh-agent bash -c 'ssh-add -q $(PYINFRA_SSH_KEY) && pyinfra --diff --limit $* linux.py deploys/$(deploy).py $(args)'

# --- infra, local machine only (no ssh, no agent) ---
# usage: make infra.local.linux.local deploy=pacman args="--dry"
# guarded by uname: local linux deploys must not run on a macos machine

infra.local.linux.%:
	@test "$$(uname -s)" = Linux || { echo "error: linux-only target, this machine is $$(uname -s)" >&2; exit 1; }
	@# one sudo auth (yubikey touch / password) per run: prime the normal
	@# tty-scoped timestamp; pyinfra gets no password and its sudo -n
	@# rides the cache (its children share this terminal's ctty)
	sudo -v
	cd infra && pyinfra --diff --limit $* linux.py deploys/$(deploy).py $(args)

# usage: make infra.local.macos.local deploy=openconnect args="--dry"

infra.local.macos.%:
	@test "$$(uname -s)" = Darwin || { echo "error: macos-only target, this machine is $$(uname -s)" >&2; exit 1; }
	cd infra && pyinfra --diff --limit $* macos.py deploys/$(deploy).py $(args)
