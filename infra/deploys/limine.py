from pyinfra.context import host
from pyinfra.facts.files import FindInFile
from pyinfra.operations import files, server

LIMINE_CONF = '/boot/limine.conf'

conf = host.data.get('limine')
assert conf, 'limine config must be set in host data'

files.template(
    name='render /etc/default/limine',
    src='templates/limine-default.j2',
    dest='/etc/default/limine',
    conf=conf,
    mode='644',
    _sudo=True,
)


def conf_line(name, pattern, line):
    # mirror ansible's insertafter 'CONFIG.md': when the option is missing,
    # insert it right below the header comment instead of appending at EOF
    if host.get_fact(FindInFile, path=LIMINE_CONF, pattern=pattern):
        files.line(
            name=name,
            path=LIMINE_CONF,
            line=pattern,
            replace=line,
            _sudo=True,
        )
    else:
        server.shell(
            name=name,
            commands=[f"sed -i '/CONFIG.md/a {line}' {LIMINE_CONF}"],
            _sudo=True,
        )


conf_line(
    'limine.conf: timeout',
    '^timeout:',
    f'timeout: {conf.get("conf_timeout", 30)}',
)

conf_line(
    'limine.conf: remember_last_entry',
    '^remember_last_entry:',
    f'remember_last_entry: {conf.get("conf_remember_last_entry", "yes")}',
)
