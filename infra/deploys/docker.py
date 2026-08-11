from pyinfra.context import host
from pyinfra.facts.server import Users
from pyinfra.operations import files, server, systemd

files.directory(
    name='ensure /etc/docker',
    path='/etc/docker',
    _sudo=True,
)

# without docker_data_dir the host keeps the stock data-root (/var/lib/docker)
data_dir = host.data.get('docker_data_dir')
if data_dir:
    files.directory(
        name=f'ensure docker data dir {data_dir}',
        path=data_dir,
    )

daemon_config = {}
if data_dir:
    daemon_config['data-root'] = data_dir
if host.data.get('docker_storage_driver'):
    daemon_config['storage-driver'] = host.data.docker_storage_driver

daemon_json = files.template(
    name='render /etc/docker/daemon.json',
    src='templates/docker-daemon.json.j2',
    dest='/etc/docker/daemon.json',
    config=daemon_config,
    _sudo=True,
)

# mind that a restart kills running containers
if daemon_json.changed:
    systemd.service(
        name='restart docker',
        service='docker.service',
        restarted=True,
        _sudo=True,
    )

users = host.get_fact(Users)
for user in host.data.get('docker_users', []):
    info = users.get(user)
    if info and 'docker' not in info['groups']:
        server.shell(
            name=f'add {user} to docker group',
            commands=[f'usermod -aG docker {user}'],
            _sudo=True,
        )
