"""adblock on an OpenWrt host: feed list, allowlist, sysupgrade backup, reload.

The custom feed file replaces adblock's default list entirely, so it is
generated in openwrt-scripts (make adblock-feeds) and only shipped here.
The allowlist is rendered from the host's adblock.allow list in the
private toml. A changed file triggers a reload; a changed feed file also
drops the cached lists in /tmp/adblock-backup first, because reload
restores an unchanged feed (same ETag) from there instead of parsing it
with the new rule.
"""

import pathlib

from pyinfra.context import host
from pyinfra.facts.server import Which
from pyinfra.operations import files, server

if host.data.adblock_allow is None:
    host.noop('adblock: no adblock table for this host')
else:
    # files.put compares uploads by sha1 and busybox on OpenWrt has none of
    # sha1sum/shasum/sha1: without it every run re-uploads and reloads. The
    # fact for the first upload below is already collected when this runs,
    # so the first run is never idempotent; every later one is.
    if not host.get_fact(Which, command='sha1sum'):
        server.shell(
            name='adblock: install sha1sum (idempotent uploads)',
            commands=[
                (
                    'if command -v apk >/dev/null 2>&1; then apk add coreutils-sha1sum; '
                    'else opkg install coreutils-sha1sum; fi'
                )
            ],
        )

    feeds = files.put(
        name='adblock: custom feed list',
        src=str(pathlib.Path(host.data.adblock_custom_feeds).expanduser()),
        dest='/etc/adblock/adblock.custom.feeds',
        mode='644',
    )
    allow = files.template(
        name='adblock: allowlist',
        src='templates/openwrt/adblock.allowlist.j2',
        dest='/etc/adblock/adblock.allowlist',
        mode='644',
        adblock_allow=host.data.adblock_allow,
    )

    # survive sysupgrade: both files are conffiles of the package, but a
    # custom feed file is not part of its default set
    for path in ('/etc/adblock/adblock.custom.feeds', '/etc/adblock/adblock.allowlist'):
        files.line(
            name=f'sysupgrade.conf: keep {path}',
            path='/etc/sysupgrade.conf',
            line=path,
            escape_regex_characters=True,
        )

    server.shell(
        name='adblock: drop cached feeds (rule change)',
        commands=['rm -f /tmp/adblock-backup/adb_list.*.gz'],
        _if=lambda: feeds.changed,
    )
    server.shell(
        name='adblock: reload',
        commands=['/etc/init.d/adblock reload'],
        _if=lambda: feeds.changed or allow.changed,
    )
