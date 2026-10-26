# OpenWrt hosts: inventory from [[data.openwrt_hosts]] in the machine-local
# chezmoi.toml (the table openwrt-scripts' configs render from). Every
# host lands in the `openwrt` group; --limit <ssh name> picks one.
#
# The devices run dropbear without sftp-server and busybox without stat,
# so group_data/openwrt.py switches file transfers to legacy scp and the
# File fact falls back to `ls -ld` on its own. Per-host entries are flattened
# into host data: `deploy` (the file map, deploy.sh format) feeds
# deploys/openwrt-files.py, a host without an `adblock` table gets
# adblock_allow = None and the adblock deploy skips it.
from util import chezmoi_openwrt_hosts

openwrt = []
for _entry in chezmoi_openwrt_hosts():
    _data = {}
    if 'deploy' in _entry:
        _data['deploy'] = _entry['deploy']
    if 'adblock' in _entry:
        _data['adblock_allow'] = list(_entry['adblock'].get('allow', []))
    openwrt.append((_entry.get('ssh', _entry['name']), _data))
