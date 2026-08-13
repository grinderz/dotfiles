from pyinfra.context import host
from pyinfra.operations import files, systemd

# monthly checksum scrub of the whole pool; units ship with btrfs-progs,
# '-' is the systemd path escape for '/'
systemd.service(
    name='enable btrfs-scrub@-.timer',
    service='btrfs-scrub@-.timer',
    enabled=True,
    running=True,
    _sudo=True,
)

# smart monitoring for nvme and the archive hdd; requires smartmontools
systemd.service(
    name='enable and start smartd',
    service='smartd',
    enabled=True,
    running=True,
    _sudo=True,
)

# weekly btrfs device error-counter check: btrfs keeps per-device i/o error
# counters, --check exits non-zero when any is set, so a tripped check shows
# up as a failed unit in `systemctl --failed`
stats_units_changed = False
for unit in ('btrfs-stats-check.service', 'btrfs-stats-check.timer'):
    put = files.put(
        name=f'render {unit}',
        src=f'templates/storage-health/{unit}',
        dest=f'/etc/systemd/system/{unit}',
        mode='644',
        _sudo=True,
    )
    stats_units_changed = stats_units_changed or put.changed

systemd.service(
    name='enable btrfs-stats-check.timer',
    service='btrfs-stats-check.timer',
    enabled=True,
    running=True,
    daemon_reload=stats_units_changed,
    _sudo=True,
)

# daily btrfs free space check; alerts through the same failed-unit path
files.template(
    name='render btrfs-free-check script',
    src='templates/storage-health/btrfs-free-check.j2',
    dest='/usr/local/bin/btrfs-free-check',
    min_gb=host.data.btrfs_free_min_gb,
    mode='755',
    _sudo=True,
)

free_units_changed = False
for unit in ('btrfs-free-check.service', 'btrfs-free-check.timer'):
    put = files.put(
        name=f'render {unit}',
        src=f'templates/storage-health/{unit}',
        dest=f'/etc/systemd/system/{unit}',
        mode='644',
        _sudo=True,
    )
    free_units_changed = free_units_changed or put.changed

systemd.service(
    name='enable btrfs-free-check.timer',
    service='btrfs-free-check.timer',
    enabled=True,
    running=True,
    daemon_reload=free_units_changed,
    _sudo=True,
)
