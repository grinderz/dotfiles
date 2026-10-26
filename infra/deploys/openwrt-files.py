"""Device files for an OpenWrt host: scripts, hotplug hooks, sysctl, nftables.

The host's `deploy` string in [[data.openwrt_hosts]] keeps the format of the
retired deploy.sh of openwrt-scripts, one entry per pattern:
`<file|glob>[:mode[:user[:group]]][@boot][@keep]`, globs relative to
files/openwrt/ (openwrt_files_dir in the group data). Top-level files land in
/usr/bin, files in a subdirectory mirror the device root
(etc/sysctl.d/x -> /etc/sysctl.d/x). Without :mode the local executable bit
decides (755, else 644); user and group, as in chown, are left alone when
empty or absent (`etc/x:640::nutmon` sets the group only). @boot puts the
remote path into /etc/rc.local before the final `exit 0`, @keep into
/etc/sysupgrade.conf so sysupgrade keeps the file.

Whole private files (never in a repo) come from a second tree,
<openwrt_private_dir>/<host>/, mirrored onto the device root with
@keep implied: wireless configs, VPN profiles, certificates.

A host with neither a `deploy` map nor a private tree is an error, not a
no-op: an entry that lost its map in a move must not pass as deployed while
a sysupgrade quietly drops the files it used to carry.

A changed sysctl.d file is applied with /etc/init.d/sysctl restart. Scripts
and hotplug hooks run on their own events, nothing else is restarted.
"""

import pathlib
import shlex

from pyinfra.context import host
from pyinfra.facts.files import FindInFile
from pyinfra.operations import files, server

RC_LOCAL = '/etc/rc.local'
SYSUPGRADE_CONF = '/etc/sysupgrade.conf'


def parse_entry(entry):
    """'<pattern>[:mode[:user[:group]]][@boot][@keep]' ->
    (pattern, mode, user, group, boot, keep), absent fields None."""
    boot = keep = False
    while True:
        if entry.endswith('@boot'):
            entry, boot = entry[: -len('@boot')], True
        elif entry.endswith('@keep'):
            entry, keep = entry[: -len('@keep')], True
        else:
            break
    pattern, *fields = entry.split(':')
    if len(fields) > 3:
        raise ValueError(f'too many fields in pattern {entry!r}')
    mode, user, group = (fields + [''] * 3)[:3]
    if mode and not (len(mode) in (3, 4) and all(c in '01234567' for c in mode)):
        raise ValueError(f'invalid mode {mode!r} in pattern {entry!r}')
    return pattern, (mode or None), (user or None), (group or None), boot, keep


def file_mode(path, mode):
    if mode:
        return mode
    return '755' if path.stat().st_mode & 0o111 else '644'


def dest_for(rel, dest_dir):
    """Top-level files go to dest_dir, the rest mirrors the device root."""
    return f'/{rel}' if '/' in rel else f'{dest_dir}/{rel}'


def ensure_startup(dest):
    """rc.local line before the final `exit 0`, appended when there is none."""
    present = host.get_fact(FindInFile, path=RC_LOCAL, pattern=f'^{dest}$')
    if present:
        host.noop(f'rc.local: {dest} already registered')
        return
    cmd = shlex.quote(dest)
    server.shell(
        name=f'rc.local: start {dest}',
        commands=[
            (
                f'if grep -q "^exit 0" {RC_LOCAL} 2>/dev/null; then '
                f"awk -v c={cmd} '!d && /^exit 0/ {{ print c; d=1 }} {{ print }}' "
                f'{RC_LOCAL} > {RC_LOCAL}.tmp && cat {RC_LOCAL}.tmp > {RC_LOCAL} '
                f'&& rm -f {RC_LOCAL}.tmp; '
                f'else echo {cmd} >> {RC_LOCAL}; fi'
            )
        ],
    )


def ensure_keep(dest):
    files.line(
        name=f'sysupgrade.conf: keep {dest}',
        path=SYSUPGRADE_CONF,
        line=dest,
        escape_regex_characters=True,
    )


deploy_dir = pathlib.Path(host.data.openwrt_files_dir).expanduser()
dest_dir = host.data.openwrt_dest_dir
private_dir = pathlib.Path(host.data.openwrt_private_dir).expanduser() / host.name

# (src path, dest, mode, user, group, boot, keep), the deploy map first, the
# private tree after
planned = []
for entry in host.data.deploy.split():
    pattern, mode, user, group, boot, keep = parse_entry(entry)
    matched = sorted(p for p in deploy_dir.glob(pattern) if p.is_file())
    if not matched:
        raise ValueError(f'{host.name}: no files match {pattern!r} in {deploy_dir}')
    for src in matched:
        rel = src.relative_to(deploy_dir).as_posix()
        dest = dest_for(rel, dest_dir)
        planned.append((src, dest, file_mode(src, mode), user, group, boot, keep))

if private_dir.is_dir():
    for src in sorted(p for p in private_dir.rglob('*') if p.is_file()):
        rel = src.relative_to(private_dir).as_posix()
        planned.append((src, f'/{rel}', file_mode(src, None), None, None, False, True))

if not planned:
    raise ValueError(
        f'{host.name}: nothing to deploy, no `deploy` in [[data.openwrt_hosts]] '
        f'and no {private_dir}'
    )

sysctl_changed = []
for src, dest, mode, user, group, boot, keep in planned:
    put = files.put(
        name=f'file: {dest}',
        src=str(src),
        dest=dest,
        user=user,
        group=group,
        mode=mode,
    )
    if dest.startswith('/etc/sysctl.d/'):
        sysctl_changed.append(put)
    if boot:
        ensure_startup(dest)
    if keep:
        ensure_keep(dest)

if sysctl_changed:
    server.shell(
        name='sysctl: apply changed settings',
        commands=['/etc/init.d/sysctl restart'],
        _if=lambda: any(op.changed for op in sysctl_changed),
    )
