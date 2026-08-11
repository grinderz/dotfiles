from pyinfra.context import host

from util import block_with_diff

for entry in host.data.hosts_entries:
    fqdn = f'{entry["alias"]}{entry["domain"]}'
    block_with_diff(
        name=f'/etc/hosts: {fqdn}',
        path='/etc/hosts',
        content=[f'{entry["ip"]} {fqdn} {entry["alias"]}'],
        marker='# {mark} PYINFRA BLOCK ' + fqdn,
        _sudo=True,
    )
