from pyinfra.context import host
from pyinfra.operations import files, server, systemd

from util import block_with_diff

# --- /etc/snapper/configs/<name> options ---

for key, value in host.data.snapper_conf_options.items():
    files.line(
        name=f'snapper config: {key}',
        path=f'/etc/snapper/configs/{host.data.snapper_conf_name}',
        line=f'^#?{key}=',
        replace=f'{key}="{value}"',
        extended_regex=True,
        _sudo=True,
    )

# --- cleanup timer: daily instead of upstream hourly ---

files.directory(
    name='ensure snapper-cleanup.timer.d',
    path='/etc/systemd/system/snapper-cleanup.timer.d',
    _sudo=True,
)

override = files.put(
    name='render snapper-cleanup.timer override',
    src='templates/snapper/cleanup-timer-override.conf',
    dest='/etc/systemd/system/snapper-cleanup.timer.d/override.conf',
    mode='644',
    _sudo=True,
)

if override.changed:
    systemd.service(
        name='restart snapper-cleanup.timer',
        service='snapper-cleanup.timer',
        restarted=True,
        daemon_reload=True,
        _sudo=True,
    )

# --- snbk backup configs ---

for bc in host.data.snapper_backup_configs:
    files.template(
        name=f'render backup-config {bc["name"]}',
        src='templates/snapper/backup-config.json.j2',
        dest=f'/etc/snapper/backup-configs/{bc["name"]}.json',
        bc=bc,
        mode='644',
        _sudo=True,
    )

# --- archive disk: fstab + udev-triggered backup pipeline ---

units_changed = False
for mount in host.data.snapper_backup_mounts:
    # systemd mount unit name for /media/<label> (systemd-escape of the path)
    mount_unit = 'media-' + mount['name'].replace('-', '\\x2d') + '.mount'

    block_with_diff(
        name=f'fstab: {mount["name"]}',
        path='/etc/fstab',
        content=[
            f'# LABEL={mount["name"]}',
            f'UUID={mount["uuid"]}  {mount["path"]}  {mount["fstype"]}  {mount["opts"]}  0 0',
        ],
        marker='# {mark} PYINFRA BLOCK ' + mount['name'],
        _sudo=True,
    )

    server.shell(
        name='validate fstab',
        commands=['findmnt --verify'],
        _sudo=True,
    )

    files.template(
        name=f'render systemd-udev-rule-{mount["name"]}.sh',
        src='templates/snapper/udev-rule.sh.j2',
        dest=f'/usr/local/bin/systemd-udev-rule-{mount["name"]}.sh',
        mode='755',
        mount=mount,
        _sudo=True,
    )

    unit = files.template(
        name=f'render udev-rule-{mount["name"]}.service',
        src='templates/snapper/udev-rule.service.j2',
        dest=f'/etc/systemd/system/udev-rule-{mount["name"]}.service',
        mount=mount,
        mount_unit=mount_unit,
        mode='644',
        _sudo=True,
    )
    units_changed = units_changed or unit.changed

    files.template(
        name=f'render 99-systemd-{mount["name"]}.rules',
        src='templates/snapper/udev.rules.j2',
        dest=f'/etc/udev/rules.d/99-systemd-{mount["name"]}.rules',
        mount=mount,
        mode='644',
        _sudo=True,
    )

if units_changed:
    server.shell(
        name='systemctl daemon-reload',
        commands=['systemctl daemon-reload'],
        _sudo=True,
    )

# --- timers ---

systemd.service(
    name='enable snapper-cleanup.timer',
    service='snapper-cleanup.timer',
    running=True,
    enabled=True,
    _sudo=True,
)

systemd.service(
    name='disable snapper-timeline.timer',
    service='snapper-timeline.timer',
    running=False,
    enabled=False,
    _sudo=True,
)
