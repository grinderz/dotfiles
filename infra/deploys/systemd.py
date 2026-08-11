from pyinfra.context import host
from pyinfra.operations import files, systemd

files.directory(
    name='ensure /etc/systemd/journald.conf.d',
    path='/etc/systemd/journald.conf.d',
    _sudo=True,
)

journald_conf = files.template(
    name='render journald.conf.d/00-journal-size.conf',
    src='templates/journald.conf.d/00-journal-size.conf.j2',
    dest='/etc/systemd/journald.conf.d/00-journal-size.conf',
    journal_system_max_use=host.data.systemd_journal_system_max_use,
    _sudo=True,
)

if journald_conf.changed:
    systemd.service(
        name='restart systemd-journald',
        service='systemd-journald',
        restarted=True,
        _sudo=True,
    )

networks_changed = False
for net in host.data.systemd_networks:
    unit = files.template(
        name=f'render network/{net["file"]}',
        src='templates/network/unit.network.j2',
        dest=f'/etc/systemd/network/{net["file"]}',
        net=net,
        _sudo=True,
    )
    networks_changed = networks_changed or unit.changed

for stale in host.data.get('systemd_networks_absent', []):
    removed = files.file(
        name=f'remove network/{stale}',
        path=f'/etc/systemd/network/{stale}',
        present=False,
        _sudo=True,
    )
    networks_changed = networks_changed or removed.changed

if networks_changed:
    systemd.service(
        name='restart systemd-networkd',
        service='systemd-networkd',
        restarted=True,
        _sudo=True,
    )
