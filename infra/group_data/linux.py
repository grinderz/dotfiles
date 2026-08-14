# defaults, override per-host in linux.py
pacman_conf_parallel_downloads = 10
pacman_conf_no_extract = [
    'usr/lib/binfmt.d/wine.conf',
    'usr/share/applications/wine.desktop',
    'usr/share/applications/libreoffice-*.desktop',
    'usr/share/dbus-1/services/org.a11y.*',
    'etc/cron.hourly/snapper',
]

systemd_journal_system_max_use = '100M'
systemd_networks = []
# sway binds XF86PowerOff to the lock script; logind must not also react
systemd_handle_power_key = 'ignore'

zram_device = 'zram0'

hosts_entries = []

docker_users = []  # host data (machine-local chezmoi.toml)

btrfs_free_min_gb = 50

conservation_users = []  # host data (machine-local chezmoi.toml)
conservation_node = (
    '/sys/devices/pci0000:00/0000:00:14.3/PNP0C09:00/VPC2004:00/conservation_mode'
)

docker_storage_driver = 'overlay2'

snapper_conf_name = 'root'
snapper_conf_options = {
    'TIMELINE_CREATE': 'no',
    'TIMELINE_CLEANUP': 'no',
    'NUMBER_LIMIT': '8',
    'NUMBER_LIMIT_IMPORTANT': '4',
    'EMPTY_PRE_POST_CLEANUP': 'yes',
}
snap_pac_important_packages = [
    'linux', 'linux-lts', 'systemd', 'btrfs-progs', 'limine', 'cryptsetup',
]
snapper_backup_configs = []
snapper_backup_mounts = []

bootbackup_keep = 5
bootmirror_mountpoint = '/boot-mirror'

openconnect_debug = True
openconnect_exec_path = '/usr/bin/openconnect'
openconnect_vpnc_script_path = '/etc/vpnc/vpnc-script'

# vpn profiles are work data and live in the machine-local chezmoi.toml
from util import chezmoi_work_data

_work = chezmoi_work_data()
openconnect_profiles = _work.get('openconnect_profiles', [])
openconnect_csd_wrapper = _work.get('openconnect_csd_wrapper')

# inbound firewall holes; everything else is dropped (established allowed)
nftables_open_tcp = [
    {'port': 22, 'comment': 'sshd'},
    {'port': 22000, 'comment': 'syncthing transfers'},
    {'port': 53317, 'comment': 'localsend transfers'},
]
nftables_open_udp = [
    {'port': 22000, 'comment': 'syncthing quic'},
    {'port': 21027, 'comment': 'syncthing discovery'},
    {'port': 5353, 'comment': 'mdns'},
    # llmnr (5355) deliberately closed and disabled in resolved (poisoning
    # target, legacy); re-open here AND drop LLMNR=no from the resolved
    # drop-in if Windows hosts must resolve this machine by name
    {'port': 53317, 'comment': 'localsend'},
]
