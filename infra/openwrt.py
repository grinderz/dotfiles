# OpenWrt routers: inventory from [[data.routers]] in the machine-local
# chezmoi.toml (the table openwrt-scripts' configs render from). Every
# router lands in the `openwrt` group; --limit <ssh name> picks one.
#
# The devices run dropbear without sftp-server and busybox without stat,
# so group_data/openwrt.py switches file transfers to legacy scp and the
# File fact falls back to `ls -ld` on its own. Per-router data is flattened
# into host data: `deploy` (the file map, deploy.sh format) feeds
# deploys/openwrt-files.py, a router without an `adblock` table gets
# adblock_allow = None and the adblock deploy skips it.
from util import chezmoi_routers

openwrt = []
for _router in chezmoi_routers():
    _data = {}
    if 'deploy' in _router:
        _data['deploy'] = _router['deploy']
    if 'adblock' in _router:
        _data['adblock_allow'] = list(_router['adblock'].get('allow', []))
    openwrt.append((_router.get('ssh', _router['name']), _data))
