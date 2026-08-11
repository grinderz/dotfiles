from pyinfra.context import host
from pyinfra.operations import files, systemd

device = host.data.zram_device

conf = files.template(
    name='render /etc/systemd/zram-generator.conf',
    src='templates/zram-generator.conf.j2',
    dest='/etc/systemd/zram-generator.conf',
    device=device,
    _sudo=True,
)

if conf.changed:
    systemd.service(
        name=f'enable and restart systemd-zram-setup@{device}',
        service=f'systemd-zram-setup@{device}.service',
        enabled=True,
        restarted=True,
        daemon_reload=True,
        _sudo=True,
    )
