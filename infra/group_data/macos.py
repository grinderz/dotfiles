# defaults, override per-host in macos.py
openconnect_debug = True
openconnect_exec_path = '/opt/homebrew/bin/openconnect'
openconnect_vpnc_script_path = '/opt/homebrew/etc/vpnc/vpnc-script'
openconnect_net_svc = [
    'USB 10/100/1000 LAN',
    'Wi-Fi',
]

# vpn profiles are work data and live in the machine-local chezmoi.toml
from util import chezmoi_work_data

_work = chezmoi_work_data()
openconnect_profiles = _work.get('openconnect_profiles', [])
openconnect_csd_wrapper = _work.get('openconnect_csd_wrapper')
