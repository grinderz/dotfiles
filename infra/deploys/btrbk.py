from pyinfra.context import host
from pyinfra.operations import files, server, systemd

conf = host.data.get('btrbk')
assert conf, 'btrbk config must be set in host data'

files.template(
    name='render /etc/btrbk/btrbk.conf',
    src='templates/btrbk/btrbk.conf.j2',
    dest='/etc/btrbk/btrbk.conf',
    conf=conf,
    mode='644',
    _sudo=True,
)

ssh_conf = conf.get('ssh')

units = ['btrbk-snapshot.service', 'btrbk-snapshot.timer']
if ssh_conf:
    units += ['btrbk-resume-ssh.service', 'btrbk-resume-ssh.timer']

units_changed = False
for unit in units:
    op = files.template(
        name=f'render {unit}',
        src=f'templates/btrbk/{unit}.j2',
        dest=f'/etc/systemd/system/{unit}',
        calendar=ssh_conf.get('resume_calendar', '*-*-* 18:00') if ssh_conf else None,
        mode='644',
        _sudo=True,
    )
    units_changed = units_changed or op.changed

if units_changed:
    server.shell(
        name='systemctl daemon-reload',
        commands=['systemctl daemon-reload'],
        _sudo=True,
    )

timers = ['btrbk-snapshot.timer']
if ssh_conf:
    timers.append('btrbk-resume-ssh.timer')

for timer in timers:
    systemd.service(
        name=f'enable {timer}',
        service=timer,
        running=True,
        enabled=True,
        _sudo=True,
    )

files.template(
    name='render /etc/logrotate.d/btrbk',
    src='templates/btrbk/logrotate.j2',
    dest='/etc/logrotate.d/btrbk',
    mode='644',
    _sudo=True,
)

systemd.service(
    name='enable logrotate.timer',
    service='logrotate.timer',
    running=True,
    enabled=True,
    _sudo=True,
)
