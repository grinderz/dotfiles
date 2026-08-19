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
# The gate script lets PAM skip pam_u2f when no key is attached: success=1
# jumps over the next line, so an absent key means no cue prompt and no
# module delay, straight to the password.
files.put(
    name='install /usr/local/bin/yubikey-absent (pam gate)',
    src='templates/pam/yubikey-absent',
    dest='/usr/local/bin/yubikey-absent',
    mode='755',
    _sudo=True,
)

block_with_diff(
    name='pam sudo: yubikey touch (pam_u2f)',
    path='/etc/pam.d/sudo',
    content=[
        'auth       [success=1 default=ignore]   pam_exec.so quiet /usr/local/bin/yubikey-absent',
        'auth       sufficient   pam_u2f.so cue',
    ],
    marker='# {mark} PYINFRA BLOCK pam-u2f',
    line=r'^auth\s+include\s+system-auth$',
    before=True,
    _sudo=True,
)

# Unlock swaylock with the YubiKey Bio fingerprint: userverification=1 asks
# the authenticator for UV, which the Bio satisfies with a finger match.
# The Bio lives in its own authfile on purpose: swaylock has a single input
# field, and if the shared u2f_keys were used with userverification the
# non-bio keys would start demanding their PIN in a prompt that still says
# "password". The gate line skips the module when no key is attached.
# Register with `pamu2fcfg > ~/.config/Yubico/u2f_keys_bio` (only the Bio
# plugged in). After three failed matches the Bio blocks fingerprints until
# a successful PIN use; the fallback here is simply the user password.
block_with_diff(
    name='pam swaylock: yubikey bio fingerprint (pam_u2f)',
    path='/etc/pam.d/swaylock',
    content=[
        'auth       [success=1 default=ignore]   pam_exec.so quiet /usr/local/bin/yubikey-absent',
        # expand only knows %u and %%; %h would be an instant auth error
        'auth       sufficient   pam_u2f.so cue expand userverification=1 authfile=/home/%u/.config/Yubico/u2f_keys_bio',
    ],
    marker='# {mark} PYINFRA BLOCK pam-u2f-bio',
    line=r'^auth\s+include\s+login$',
    before=True,
    _sudo=True,
)
