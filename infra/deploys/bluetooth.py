from pyinfra.operations import files, systemd

# Experimental = true turns on the BlueZ battery profile (org.bluez.Battery1),
# which waybar's bluetooth module reads for {device_battery_percentage}.
# main.conf is a pacman backup= file, so the edit survives bluez upgrades.
main_conf = files.replace(
    name='bluetooth main.conf: enable experimental features',
    path='/etc/bluetooth/main.conf',
    text='^#Experimental = false$',
    replace='Experimental = true',
    _sudo=True,
)

systemd.service(
    name='enable and start bluetooth',
    service='bluetooth',
    enabled=True,
    running=True,
    _sudo=True,
)

if main_conf.changed:
    systemd.service(
        name='restart bluetooth',
        service='bluetooth',
        restarted=True,
        _sudo=True,
    )
