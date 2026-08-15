from util import block_with_diff

# gnome-keyring as the Secret Service provider (app secrets: Evolution,
# PyCharm...; personal passwords stay in KeePassXC, which is deliberately
# NOT exposed over the bus). PAM hands the login password over so the
# default keyring unlocks at tty login; the daemon itself is D-Bus
# activated on first org.freedesktop.secrets use.
# PAM evaluates lines per-type, so appending at the end keeps the keyring
# hooks after the system-local-login stack, which is where they belong.
block_with_diff(
    name='pam login: gnome-keyring unlock',
    path='/etc/pam.d/login',
    content=[
        'auth       optional     pam_gnome_keyring.so',
        'session    optional     pam_gnome_keyring.so auto_start',
    ],
    marker='# {mark} PYINFRA BLOCK gnome-keyring',
    _sudo=True,
)
