from pyinfra.context import host
from pyinfra.operations import files, systemd

conf = files.template(
    name='render /etc/nftables.conf',
    src='templates/nftables.conf.j2',
    dest='/etc/nftables.conf',
    nftables_open_tcp=host.data.nftables_open_tcp,
    nftables_open_udp=host.data.nftables_open_udp,
    mode='644',
    _sudo=True,
)

# the arch unit is a bare oneshot without RemainAfterExit: it loads the
# ruleset at boot and goes back to inactive, so running=True would show a
# phantom start on every deploy; no ExecStop either, restart just re-runs
# `nft -f` (destroy + recreate our table atomically, docker tables intact)
systemd.service(
    name='enable nftables',
    service='nftables',
    enabled=True,
    # oneshot without RemainAfterExit: inactive after success is its
    # steady state, and pyinfra's default running=True would "start" it
    # on every run
    running=False,
    _sudo=True,
)

if conf.changed:
    systemd.service(
        name='restart nftables',
        service='nftables',
        restarted=True,
        _sudo=True,
    )
