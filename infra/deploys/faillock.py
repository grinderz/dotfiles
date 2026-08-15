from pyinfra import host
from pyinfra.facts.files import FindInFile
from pyinfra.operations import files

# Stock pam locks the account for 10 minutes after 3 failed attempts —
# too twitchy for a laptop where every unlock is a typed password. 10
# keeps typos harmless while still throttling online guessing (ssh is
# key-only anyway, see the sshd deploy). faillock.conf is a pacman
# backup= file, so the edit survives pam upgrades.
DENY = 10

# files.replace re-runs sed (and reports a change) whenever its pattern
# matches, so a catch-all pattern alone would never converge; check for
# the target line first and only rewrite when it is absent.
if not host.get_fact(
    FindInFile,
    path='/etc/security/faillock.conf',
    pattern=f'^deny = {DENY}$',
):
    files.replace(
        name=f'faillock: {DENY} attempts before lockout',
        path='/etc/security/faillock.conf',
        text='^#? ?deny = [0-9]+$',
        replace=f'deny = {DENY}',
        extended_regex=True,  # BRE has no ? quantifier
        _sudo=True,
    )
