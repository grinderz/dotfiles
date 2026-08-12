import getpass
from io import StringIO

from pyinfra.context import host
from pyinfra.facts.server import Home, Os
from pyinfra.operations import files, server

darwin = host.get_fact(Os) == 'Darwin'

profiles = host.data.openconnect_profiles
debug = host.data.openconnect_debug
# user-facing scripts (run or dropped-to as the user) live in ~/.local/bin;
# root-executed ones (vpnc-script, dns hooks) stay under /etc/vpnc
bin_path = f'{host.get_fact(Home)}/.local/bin'

files.directory(
    name='ensure /etc/vpnc',
    path='/etc/vpnc',
    _sudo=True,
)

for profile in profiles:
    if not profile['enabled']:
        files.file(
            name=f'remove vpnc-script-{profile["name"]} (profile disabled)',
            path=f'/etc/vpnc/vpnc-script-{profile["name"]}',
            present=False,
            _sudo=True,
        )
        continue
    files.template(
        name=f'render vpnc-script-{profile["name"]}',
        src='templates/openconnect/vpnc-script.j2',
        dest=f'/etc/vpnc/vpnc-script-{profile["name"]}',
        mode='755',
        profile=profile,
        debug=debug,
        vpnc_script_path=host.data.openconnect_vpnc_script_path,
        _sudo=True,
    )

files.directory(
    name=f'ensure {bin_path}',
    path=bin_path,
)

files.put(
    name='sudoers for openconnect',
    src=StringIO(
        f'{getpass.getuser()} ALL=(ALL) NOPASSWD: {host.data.openconnect_exec_path}\n'
    ),
    dest='/etc/sudoers.d/openconnect',
    mode='440',
    _sudo=True,
)

server.shell(
    name='validate sudoers',
    commands=['visudo -cf /etc/sudoers.d/openconnect'],
    _sudo=True,
)

for profile in profiles:
    if not profile['enabled']:
        files.file(
            name=f'remove vpn-{profile["name"]}.sh (profile disabled)',
            path=f'{bin_path}/vpn-{profile["name"]}.sh',
            present=False,
        )
        continue
    files.template(
        name=f'render vpn-{profile["name"]}.sh',
        src='templates/openconnect/vpn.sh.j2',
        dest=f'{bin_path}/vpn-{profile["name"]}.sh',
        mode='755',
        profile=profile,
        debug=debug,
        darwin=darwin,
        exec_path=host.data.openconnect_exec_path,
    )

csd_wrapper = host.data.openconnect_csd_wrapper
if csd_wrapper:
    files.template(
        name='render csd-wrapper.sh',
        src='templates/openconnect/csd-wrapper.sh.j2',
        dest=f'{bin_path}/csd-wrapper.sh',
        mode='755',
        debug=debug,
        device_uniqueid=csd_wrapper['device_uniqueid'],
    )

# dns hook scripts are macOS-only (scutil/networksetup); the distro
# vpnc-script handles DNS itself on linux
for sub in () if not darwin else ('post-connect.d', 'post-disconnect.d'):
    files.directory(
        name=f'ensure /etc/vpnc/{sub}',
        path=f'/etc/vpnc/{sub}',
        _sudo=True,
    )

dns_scripts = (
    (
        ('dns-vpn', 'post-connect.d/dns-vpn'),
        ('dns-default', 'post-disconnect.d/dns-default'),
    )
    if darwin
    else ()
)
for src, dst in dns_scripts:
    files.template(
        name=f'render {dst}',
        src=f'templates/openconnect/{src}.j2',
        dest=f'/etc/vpnc/{dst}',
        mode='644',
        profiles=profiles,
        debug=debug,
        net_svc=host.data.get('openconnect_net_svc', []),
        _sudo=True,
    )
