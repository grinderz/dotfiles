from pyinfra.context import host
from pyinfra.facts.files import FindInFile
from pyinfra.operations import files, server

from util import block_with_diff

PACMAN_CONF = "/etc/pacman.conf"


def conf_line(name, pattern, line):
    # mirror ansible's insertafter '[options]': when no (commented) line is
    # present files.line would append at EOF, i.e. inside the last repo
    # section, so insert under [options] instead
    if host.get_fact(FindInFile, path=PACMAN_CONF, pattern=pattern, extended_regex=True):
        files.line(
            name=name,
            path=PACMAN_CONF,
            line=pattern,
            replace=line,
            extended_regex=True,
            _sudo=True,
        )
    else:
        server.shell(
            name=name,
            commands=[f"sed -i '/^\\[options\\]/a {line}' {PACMAN_CONF}"],
            _sudo=True,
        )


conf_line("pacman.conf: Color", "^#?Color$", "Color")

conf_line(
    "pacman.conf: ParallelDownloads",
    "^#?ParallelDownloads",
    f"ParallelDownloads = {host.data.pacman_conf_parallel_downloads}",
)

block_with_diff(
    name="pacman.conf: NoExtract",
    path=PACMAN_CONF,
    content=[f"NoExtract = {item}" for item in host.data.pacman_conf_no_extract],
    marker="# {mark} PYINFRA BLOCK NoExtract",
    # keep the block inside [options]: append after the commented example,
    # otherwise it lands at EOF inside the last repo section
    line="^#NoExtract",
    after=True,
    _sudo=True,
)
