from pyinfra.operations import files, systemd

conf = files.put(
    name='sshd: key-only auth drop-in',
    src='templates/sshd_config.d/10-no-password-auth.conf',
    dest='/etc/ssh/sshd_config.d/10-no-password-auth.conf',
    user='root',
    group='root',
    mode='644',
    _sudo=True,
)

# reload (SIGHUP) re-reads the config without dropping live sessions —
# a botched config cannot lock us out mid-deploy the way restart could
if conf.changed:
    systemd.service(
        name='reload sshd',
        service='sshd',
        reloaded=True,
        _sudo=True,
    )
