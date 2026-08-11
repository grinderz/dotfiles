from pyinfra.context import host
from pyinfra.operations import files

keep = int(host.data.bootbackup_keep)
# head -n -0 would print (and rm) everything
assert keep >= 1, 'bootbackup_keep must be >= 1'

files.directory(
    name='ensure /etc/pacman.d/hooks',
    path='/etc/pacman.d/hooks',
    _sudo=True,
)

for hook in (
    {
        'file': '55-bootbackup_pre.hook',
        'stage': 'pre',
        'when': 'PreTransaction',
        'abort_on_fail': True,
        'cleanup': False,
    },
    {
        'file': '95-bootbackup_post.hook',
        'stage': 'post',
        'when': 'PostTransaction',
        'abort_on_fail': False,
        'cleanup': True,
    },
):
    files.template(
        name=f'render {hook["file"]}',
        src='templates/pacman-hooks/bootbackup.hook.j2',
        dest=f'/etc/pacman.d/hooks/{hook["file"]}',
        stage=hook['stage'],
        when=hook['when'],
        abort_on_fail=hook['abort_on_fail'],
        cleanup=hook['cleanup'],
        keep=keep,
        _sudo=True,
    )
