from pyinfra.operations import files

# The ESP is vfat, so file modes come from the mount masks. The install
# default 0022 leaves /boot world-readable and bootctl rightly calls the
# world-readable random-seed a security hole; limine.conf and the kernels
# do not need to be readable by anyone but root either. Applies to the
# mirror stick too. Takes effect on the next (re)mount.
files.replace(
    name='fstab: /boot not world-readable (fmask)',
    path='/etc/fstab',
    text=r'^(UUID=\S+\s+/boot\S*\s+vfat\s+.*)fmask=0022,dmask=0022',
    replace=r'\1fmask=0077,dmask=0077',
    # sed defaults to BRE where \S, + and bare groups never match
    extended_regex=True,
    backup=True,
    _sudo=True,
)
