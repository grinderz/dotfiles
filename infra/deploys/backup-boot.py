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

files.put(
    name='render 00-check-boot.hook',
    src='templates/pacman-hooks/00-check-boot.hook',
    dest='/etc/pacman.d/hooks/00-check-boot.hook',
    mode='644',
    _sudo=True,
)

# sync /boot to a second bootable stick after every transaction that touches
# it; opt-in per host via bootmirror_mountpoint (the mount itself lives in
# fstab: noauto + automount, so an absent stick degrades to a warning)
mirror_mountpoint = host.data.get('bootmirror_mountpoint')
if mirror_mountpoint:
    files.template(
        name='render 96-bootmirror.hook',
        src='templates/pacman-hooks/96-bootmirror.hook.j2',
        dest='/etc/pacman.d/hooks/96-bootmirror.hook',
        mirror_mountpoint=mirror_mountpoint,
        mode='644',
        _sudo=True,
    )

    # limine-snapper-sync writes snapshot entries outside pacman
    # transactions; its post.d hooks are the only reliable trigger there
    files.template(
        name='render boot hook 95-bootmirror-snapshots',
        src='templates/boot-hooks/95-bootmirror-snapshots.j2',
        dest='/etc/boot/hooks/post.d/95-bootmirror-snapshots',
        mirror_mountpoint=mirror_mountpoint,
        mode='755',
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
        mode='644',
        _sudo=True,
    )
