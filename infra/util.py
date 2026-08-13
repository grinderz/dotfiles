import pathlib
import tomllib

from pyinfra import logger, state
from pyinfra.context import host
from pyinfra.facts.files import Block
from pyinfra.operations import files, server
from pyinfra.operations.files import generate_color_diff


def block_with_diff(path, content, marker=None, begin=None, end=None, **kwargs):
    """files.block + textual diff output.

    files.block does not implement config.DIFF (pyinfra 3.10), so when --diff
    is on read the current block via the Block fact and log the difference in
    the same format files.line uses.
    """
    desired = content.splitlines() if isinstance(content, str) else list(content)

    if state.config.DIFF:
        current = (
            host.get_fact(Block, path=path, marker=marker, begin=begin, end=end) or []
        )
        if current != desired:
            host.log(f'block changes in {path}:', logger.info)
            for diff_line in generate_color_diff(current, desired):
                logger.info('  %s', diff_line)

    files.block(
        path=path, content=desired, marker=marker, begin=begin, end=end, **kwargs
    )


def sudoers_template(name, src, dest, **kwargs):
    """files.template for sudoers.d: render to a staging path, visudo -c,
    then copy into place. A syntax error never reaches the live path, where
    it could break sudo entirely.

    The staging file is kept around (and lives in /var/tmp, not tmpfs) so
    unchanged runs stay idempotent: no re-upload, no install step. If the
    live file is ever deleted by hand, remove the staging copy too to force
    a reinstall.
    """
    staging = f'/var/tmp/.pyinfra-staging-{pathlib.Path(dest).name}'
    staged = files.template(
        name=f'{name} (staging)',
        src=src,
        dest=staging,
        mode='440',
        _sudo=True,
        **kwargs,
    )
    if staged.changed:
        server.shell(
            name=f'{name}: visudo check + install',
            commands=[f'visudo -c -q -f {staging} && cp -p {staging} {dest}'],
            _sudo=True,
        )


def chezmoi_work_data():
    """[data.work] from the machine-local chezmoi.toml (empty if absent)."""
    path = pathlib.Path.home() / '.config/chezmoi/chezmoi.toml'
    if not path.exists():
        return {}
    return tomllib.loads(path.read_text()).get('data', {}).get('work', {})


def chezmoi_infra_hosts(inventory):
    """[[data.infra.<inventory>]] host list from the machine-local chezmoi.toml."""
    path = pathlib.Path.home() / '.config/chezmoi/chezmoi.toml'
    if not path.exists():
        return []
    data = tomllib.loads(path.read_text()).get('data', {})
    return data.get('infra', {}).get(inventory, [])
