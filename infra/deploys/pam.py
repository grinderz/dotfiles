from pyinfra.operations import files

from util import block_with_diff

# Only wheel members may even attempt `su` (non-wheel processes cannot
# brute-force the root password). Login/sudo/sshd stacks live in other
# pam.d files and are not touched. Both files are pacman backup= files;
# once uncommented the pattern no longer matches, so re-runs are no-ops.
for pam_file in ('su', 'su-l'):
    files.replace(
        name=f'pam {pam_file}: su for wheel only',
        path=f'/etc/pam.d/{pam_file}',
        text='^#auth           required        pam_wheel.so use_uid$',
        replace='auth            required        pam_wheel.so use_uid',
        _sudo=True,
    )

# sudo by YubiKey touch: sufficient = key plugged in -> touch, otherwise
# fall through to the password. Keys are registered per machine with
# pamu2fcfg (see README); a missing ~/.config/Yubico/u2f_keys just means
# the module fails quietly and the password prompt appears as before.
# The line must run before the system-auth include, else the password
# gets asked first.
#
# Note for automation (pyinfra): a touch cannot be cached and replayed
# the way sudo's askpass replays a password, and PAM cannot tell the two
# apart either (pyinfra's sudo children inherit the terminal's ctty, so
# even tty matches). The local make target primes the normal tty-scoped
# sudo timestamp with `sudo -v` instead — one touch per deploy run.
block_with_diff(
    name='pam sudo: yubikey touch (pam_u2f)',
    path='/etc/pam.d/sudo',
    content=['auth       sufficient   pam_u2f.so cue'],
    marker='# {mark} PYINFRA BLOCK pam-u2f',
    line=r'^auth\s+include\s+system-auth$',
    before=True,
    _sudo=True,
)
