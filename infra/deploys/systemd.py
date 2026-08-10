from pyinfra.context import host
from pyinfra.operations import files, systemd

files.directory(
    name="ensure /etc/systemd/journald.conf.d",
    path="/etc/systemd/journald.conf.d",
    _sudo=True,
)

journald_conf = files.template(
    name="render journald.conf.d/00-journal-size.conf",
    src="templates/journald.conf.d/00-journal-size.conf.j2",
    dest="/etc/systemd/journald.conf.d/00-journal-size.conf",
    journal_system_max_use=host.data.systemd_journal_system_max_use,
    _sudo=True,
)

if journald_conf.changed:
    systemd.service(
        name="restart systemd-journald",
        service="systemd-journald",
        restarted=True,
        _sudo=True,
    )

if host.data.systemd_network_wired_dock_match_name:
    files.template(
        name="render network wired dock",
        src="templates/network/20-wired-dock.network.j2",
        dest="/etc/systemd/network/20-wired-dock.network",
        match_name=host.data.systemd_network_wired_dock_match_name,
        _sudo=True,
    )
