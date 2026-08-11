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

zram_device = 'zram0'

hosts_entries = []

docker_users = ['obsd']

docker_storage_driver = 'overlay2'

snapper_conf_name = 'root'
snapper_conf_options = {
    'TIMELINE_CREATE': 'no',
    'TIMELINE_CLEANUP': 'no',
    'NUMBER_LIMIT': '8',
    'NUMBER_LIMIT_IMPORTANT': '4',
    'EMPTY_PRE_POST_CLEANUP': 'yes',
}
snapper_backup_configs = []
snapper_backup_mounts = []

bootbackup_keep = 5

openconnect_debug = True
openconnect_exec_path = '/usr/bin/openconnect'
openconnect_vpnc_script_path = '/etc/vpnc/vpnc-script'

# vpn profiles are work data and live in the machine-local chezmoi.toml
from util import chezmoi_work_data

_work = chezmoi_work_data()
openconnect_profiles = _work.get('openconnect_profiles', [])
openconnect_csd_wrapper = _work.get('openconnect_csd_wrapper')
