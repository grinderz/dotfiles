# hosts (including @local placeholders) are private and live in the
# machine-local chezmoi.toml under [[data.infra.macos]]
from util import chezmoi_infra_hosts

for _host in chezmoi_infra_hosts('macos'):
    globals().setdefault(_host['group'], []).append(
        (_host['name'], _host.get('data', {}))
    )

# fallback so local deploys work before the private toml lands on the machine
if 'local' not in globals():
    local = [('@local', {})]
