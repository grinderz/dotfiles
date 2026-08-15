from pyinfra.operations import files

# Blacklist only stops the module loading on future boots; if pcspkr is
# already loaded, `sudo rmmod pcspkr` silences it for the running session.
files.put(
    name='modprobe: blacklist pcspkr',
    src='templates/modprobe.d/nobeep.conf',
    dest='/etc/modprobe.d/nobeep.conf',
    user='root',
    group='root',
    mode='644',
    _sudo=True,
)
