from pyinfra.context import host
from pyinfra.operations import files, systemd

from util import chezmoi_data

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
    mode='644',
    _sudo=True,
)

if journald_conf.changed:
    systemd.service(
        name='restart systemd-journald',
        service='systemd-journald',
        restarted=True,
        _sudo=True,
    )

systemd.service(
    name='enable and start systemd-timesyncd',
    service='systemd-timesyncd',
    enabled=True,
    running=True,
    _sudo=True,
)

files.directory(
    name='ensure /etc/systemd/resolved.conf.d',
    path='/etc/systemd/resolved.conf.d',
    _sudo=True,
)

resolved_conf = files.put(
    name='install resolved.conf.d/00-no-llmnr.conf',
    src='templates/resolved.conf.d/00-no-llmnr.conf',
    dest='/etc/systemd/resolved.conf.d/00-no-llmnr.conf',
    mode='644',
    _sudo=True,
)

no_fallback_dns = files.put(
    name='install resolved.conf.d/00-no-fallback-dns.conf',
    src='templates/resolved.conf.d/00-no-fallback-dns.conf',
    dest='/etc/systemd/resolved.conf.d/00-no-fallback-dns.conf',
    mode='644',
    _sudo=True,
)

if resolved_conf.changed or no_fallback_dns.changed:
    systemd.service(
        name='restart systemd-resolved',
        service='systemd-resolved',
        restarted=True,
        _sudo=True,
    )

# weekly pacman cache cleanup (keeps 3 versions); requires pacman-contrib
systemd.service(
    name='enable and start paccache.timer',
    service='paccache.timer',
    enabled=True,
    running=True,
    _sudo=True,
)

# smart card daemon for YubiKey (gpg/ssh via scdaemon); requires pcsclite
systemd.service(
    name='enable and start pcscd.socket',
    service='pcscd.socket',
    enabled=True,
    running=True,
    _sudo=True,
)

# user session: failed-units desktop notifier; the unit files come from
# chezmoi (~/.config/systemd/user), so run dotfiles apply first
systemd.service(
    name='enable and start failed-units-notify.timer (user)',
    service='failed-units-notify.timer',
    enabled=True,
    running=True,
    user_mode=True,
)

# user session: low-disk-space notifier for the btrfs root
systemd.service(
    name='enable and start disk-space-notify.timer (user)',
    service='disk-space-notify.timer',
    enabled=True,
    running=True,
    user_mode=True,
)

# user session: low-battery notifier (once per discharge cycle)
systemd.service(
    name='enable and start battery-low-notify.timer (user)',
    service='battery-low-notify.timer',
    enabled=True,
    running=True,
    user_mode=True,
)

# user session: reboot reminder after a kernel upgrade
systemd.service(
    name='enable and start reboot-required-notify.timer (user)',
    service='reboot-required-notify.timer',
    enabled=True,
    running=True,
    user_mode=True,
)

# user session: desktop notification while a yubikey waits for a touch
# (config from chezmoi enables libnotify); requires the
# yubikey-touch-detector package
systemd.service(
    name='enable and start yubikey-touch-detector (user)',
    service='yubikey-touch-detector.service',
    enabled=True,
    running=True,
    user_mode=True,
)

# user session: mail and calendar sync. Unit files and configs come from
# chezmoi and render only when [data.mail] / [data.cal] exist in the
# machine-local chezmoi.toml — gate the enables the same way so hosts
# without mail data do not trip over missing units.
_mail = chezmoi_data('mail')
_cal = chezmoi_data('cal')

if 'davmail_url' in _mail:
    systemd.service(
        name='enable and start davmail (user)',
        service='davmail.service',
        enabled=True,
        running=True,
        user_mode=True,
    )

if _mail:
    systemd.service(
        name='enable and start mbsync.timer (user)',
        service='mbsync.timer',
        enabled=True,
        running=True,
        user_mode=True,
    )

if _cal:
    systemd.service(
        name='enable and start vdirsyncer.timer (user)',
        service='vdirsyncer.timer',
        enabled=True,
        running=True,
        user_mode=True,
    )

    # meeting reminders from the EWS calendar without Evolution open
    systemd.service(
        name='enable and start evolution-alarm-notify (user)',
        service='evolution-alarm-notify.service',
        enabled=True,
        running=True,
        user_mode=True,
    )

# seat management for the sway session (sway runs as plain user via seatd)
systemd.service(
    name='enable and start seatd',
    service='seatd',
    enabled=True,
    running=True,
    _sudo=True,
)

# EPP + platform_profile switching on amd-pstate-epp laptops; requires the
# power-profiles-daemon package
systemd.service(
    name='enable and start power-profiles-daemon',
    service='power-profiles-daemon',
    enabled=True,
    running=True,
    _sudo=True,
)

files.directory(
    name='ensure /etc/systemd/logind.conf.d',
    path='/etc/systemd/logind.conf.d',
    _sudo=True,
)

logind_conf = files.template(
    name='render logind.conf.d/00-power-key.conf',
    src='templates/logind.conf.d/00-power-key.conf.j2',
    dest='/etc/systemd/logind.conf.d/00-power-key.conf',
    handle_power_key=host.data.systemd_handle_power_key,
    mode='644',
    _sudo=True,
)

inhibit_delay = files.put(
    name='install logind.conf.d/10-inhibit-delay.conf',
    src='templates/logind.conf.d/10-inhibit-delay.conf',
    dest='/etc/systemd/logind.conf.d/10-inhibit-delay.conf',
    mode='644',
    _sudo=True,
)

if logind_conf.changed or inhibit_delay.changed:
    systemd.service(
        name='restart systemd-logind',
        service='systemd-logind',
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
        # networkd runs as systemd-network, needs world-readable units
        mode='644',
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
