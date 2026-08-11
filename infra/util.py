import pathlib
import tomllib

from pyinfra import logger, state
from pyinfra.context import host
from pyinfra.facts.files import Block
from pyinfra.operations import files
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
