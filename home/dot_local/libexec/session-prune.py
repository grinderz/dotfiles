import argparse
import json
import os
import shutil
import subprocess
import sys
import unicodedata
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

AGENT: str
SESSION_DIRS: list[Path]
# Without --check-all only this much of each transcript is parsed, and at
# most SCAN_LIMIT bytes are read while skipping oversized records.
HEADER = 512 * 1024
SCAN_LIMIT = 16 * HEADER


@dataclass
class Session:
    project: str
    sid: str
    title: str
    status: str
    path: Path
    extra: Path | None
    snapshot: tuple

    @property
    def size(self):
        return sum(item[2] for item in self.snapshot)

    @property
    def modified(self):
        return max(item[3] for item in self.snapshot) / 1e9


def clean(text):
    return ' '.join(''.join(' ' if unicodedata.category(c).startswith('C') else c
                            for c in str(text)).split())


def human(size):
    for unit in ('B', 'K', 'M', 'G'):
        if size < 1024 or unit == 'G':
            return f'{size:.0f}{unit}' if unit == 'B' else f'{size:.1f}{unit}'
        size /= 1024


def snapshot(path, extra=None):
    files = [path]
    if path.is_symlink() or (extra and extra.is_symlink()):
        raise ValueError(f'refusing session files linked elsewhere: {path}')
    if extra and extra.is_dir():
        files += sorted(p for p in extra.rglob('*') if p.is_file() or p.is_symlink())
    result = []
    for file in files:
        stat = file.lstat()
        result.append((str(file), stat.st_ino, stat.st_size, stat.st_mtime_ns))
    return tuple(result)


def object_field(record, field):
    value = record.get(field)
    if not isinstance(value, dict):
        raise TypeError(f'{field} must be an object')
    return value


def message_text(content):
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        raise TypeError('message content must be text or a list')
    return ' '.join(block['text'] for block in content
                    if isinstance(block, dict) and isinstance(block.get('text'), str))


def header_lines(stream):
    """Numbered records from the start of a transcript, up to HEADER bytes.

    A single record can span many MiB (an inline image, an attachment). One
    larger than HEADER is skipped unparsed instead of ending the header, so
    the records after it, such as Claude's ai-title, are still seen.
    """
    used = number = 0
    while used < HEADER and stream.tell() < SCAN_LIMIT:
        line = stream.readline(HEADER + 1)
        if not line:
            return
        number += 1
        if len(line) > HEADER:
            while line and not line.endswith(b'\n') and stream.tell() < SCAN_LIMIT:
                line = stream.readline(1024 * 1024)
            continue
        used += len(line)
        yield number, line


def metadata(path, check_all=False):
    project, sid, first, summary, ai_title, custom_title = '', '', '', '', '', ''
    with path.open('rb') as stream:
        lines = enumerate(stream, 1) if check_all else header_lines(stream)
        for number, line in lines:
            try:
                record = json.loads(line)
                if not isinstance(record, dict):
                    raise TypeError('record must be an object')
                kind = record.get('type')
                if not isinstance(kind, str) or not kind:
                    raise ValueError('record is missing a type')
                if kind == 'session_meta':
                    payload = object_field(record, 'payload')
                    project = payload.get('cwd')
                    if not isinstance(project, str) or not project:
                        raise ValueError('session_meta is missing cwd')
                    try:
                        sid = str(UUID(payload.get('id', '')))
                    except (ValueError, TypeError, AttributeError):
                        raise ValueError('session_meta has an invalid UUID') from None
                elif kind == 'event_msg':
                    payload = object_field(record, 'payload')
                    if payload.get('type') == 'user_message':
                        text = message_text(payload.get('message'))
                        first = first or text
                    elif payload.get('type') == 'item_completed':
                        item = object_field(payload, 'item')
                        if item.get('type') in ('UserMessage', 'userMessage'):
                            text = message_text(item.get('content'))
                            first = first or text
                elif kind == 'user':
                    text = message_text(object_field(record, 'message').get('content'))
                    first = first or text
                # Claude's own titles, the newest of each kind: a /rename
                # (custom-title) wins over the generated ai-title.
                elif kind == 'custom-title':
                    custom_title = record.get('customTitle') or custom_title
                elif kind == 'ai-title':
                    ai_title = record.get('aiTitle') or ai_title
                elif kind == 'summary':
                    summary = record.get('summary') or summary
            except (TypeError, ValueError, RecursionError) as error:
                raise ValueError(f'line {number}: {error}') from None
        if not stream.tell():
            raise ValueError('empty transcript')
    if AGENT == 'Codex' and not sid:
        detail = 'missing session_meta' if check_all else 'no session_meta in header; retry with --check-all'
        raise ValueError(detail)
    return clean(project), sid, clean(custom_title or ai_title or summary or first)


def sessions(dirs, project=None, check_all=False):
    seen = set()
    for root in dirs:
        if not root.is_dir():
            continue
        paths = root.glob('*/*.jsonl') if AGENT == 'Claude' else root.rglob('rollout-*.jsonl')
        for path in paths:
            if AGENT == 'Codex' and '.sync-conflict-' in path.name:
                continue
            try:
                if path.is_symlink():
                    raise ValueError('transcript is a symlink')
                resolved = path.resolve()
                if resolved in seen:
                    continue
                seen.add(resolved)
                cwd, sid, title = metadata(path, check_all)
                if AGENT == 'Claude':
                    cwd, sid = path.parent.name, path.stem
                    extra = path.with_suffix('')
                    status = 'session'
                else:
                    if not path.name.endswith(f'-{sid}.jsonl'):
                        raise ValueError('filename does not match session UUID')
                    extra = None
                    status = 'archived' if root.name == 'archived_sessions' else 'active'
                if project and project.casefold() not in cwd.casefold():
                    continue
                yield Session(cwd, sid, title, status, path, extra, snapshot(path, extra))
            except (OSError, ValueError, TypeError) as error:
                print(f'skipping {clean(path)}: {clean(error)}', file=sys.stderr)


def select_sessions(items):
    if not shutil.which('fzf'):
        raise ValueError('fzf is required for interactive selection')
    rows = []
    for index, item in enumerate(items):
        date = datetime.fromtimestamp(item.modified).strftime('%Y-%m-%d')
        label = (f'{clean(item.project)[-34:]:34}  {item.status:8}  {date}  '
                 f'{human(item.size):>7}  {clean(item.sid)[:8]}  {item.title[:180]}')
        rows.append(f'{index}\t{label}')
    # fzf normally accepts the highlighted row when no rows are marked.
    # Guard every accept key: Enter/double-click with zero marks must cancel.
    guard = 'if [ "$FZF_SELECT_COUNT" -gt 0 ]; then printf accept; else printf abort; fi'
    env = {key: value for key, value in os.environ.items()
           if key not in ('FZF_DEFAULT_OPTS', 'FZF_DEFAULT_OPTS_FILE', 'FZF_DEFAULT_COMMAND')}
    env['SHELL'] = '/bin/sh'
    command = ['fzf', '--multi', '--sync', '--no-sort', '--layout=reverse',
               '--delimiter=\t', '--with-nth=2..', '--prompt=delete> ',
               '--header', (f'{AGENT}: nothing selected by default\n'
               'Tab mark/unmark | Ctrl-A mark all | Ctrl-D clear | Enter review | Esc cancel'),
               '--bind=start:clear-multi,ctrl-a:select-all,ctrl-d:clear-multi',
               '--bind', f'enter:transform:{guard}',
               '--bind', f'double-click:transform:{guard}']
    result = subprocess.run(command, input='\n'.join(rows) + '\n', text=True,
                            stdout=subprocess.PIPE, env=env, check=False)
    if result.returncode in (1, 130):
        return []
    if result.returncode:
        raise ValueError(f'fzf exited with status {result.returncode}')
    indices = list(dict.fromkeys(int(line.split('\t', 1)[0]) for line in result.stdout.splitlines()))
    if any(index < 0 or index >= len(items) for index in indices):
        raise ValueError('invalid selection returned by fzf')
    return [items[index] for index in indices]


def check_codex_store(item, dirs):
    home = Path(os.environ.get('CODEX_HOME') or Path.home() / '.codex').expanduser()
    roots = [home / name for name in ('sessions', 'archived_sessions')]
    if {root.resolve() for root in roots} != {path.resolve() for path in dirs}:
        raise ValueError(f'{home} does not point to the selected transcript store')
    # The native delete command acts on a UUID across both trees. Count files
    # even if metadata parsing or the project filter hid them from the picker.
    matches = [path.resolve() for root in roots
               for path in root.rglob(f'rollout-*{item.sid}*.jsonl')]
    if matches != [item.path.resolve()]:
        raise ValueError(f'{item.sid} does not identify a single transcript in {home}')


def delete_session(item, dirs):
    if snapshot(item.path, item.extra) != item.snapshot:
        raise ValueError(f'{item.sid} changed while selecting; select it again')
    if AGENT == 'Codex':
        # Let Codex maintain its SQLite history/indexes and enforce its own
        # checks for loaded sessions. Never silently fall back to unlink().
        check_codex_store(item, dirs)
        subprocess.run(['codex', 'delete', item.sid, '--force'], check=True)
        if item.path.exists():
            raise ValueError(f'Codex did not remove the selected transcript: {item.path}')
    else:
        if item.extra and item.extra.is_dir():
            shutil.rmtree(item.extra)
        item.path.unlink()


def main():
    global AGENT, SESSION_DIRS
    parser = argparse.ArgumentParser(description='Interactively delete selected sessions; no age filter.')
    parser.add_argument('--agent', required=True, choices=('Claude', 'Codex'), help=argparse.SUPPRESS)
    parser.add_argument('--dir', required=True, action='append', type=Path, help=argparse.SUPPRESS)
    parser.add_argument('--project', help='only projects whose name/path contains this')
    parser.add_argument('--json', action='store_true', help='list all matching sessions as JSON; never delete')
    parser.add_argument('--dry-run', action='store_true', help='select and report without deleting')
    parser.add_argument('--check-all', action='store_true',
                        help='check every JSONL record for damage instead of just the header')
    args = parser.parse_args()
    AGENT, SESSION_DIRS = args.agent, args.dir
    items = sorted(sessions(SESSION_DIRS, args.project, args.check_all), key=lambda item: (-item.size, str(item.path)))
    if args.json:
        print(json.dumps([{'project': item.project, 'session': item.sid, 'title': item.title,
                           'status': item.status, 'bytes': item.size,
                           'last_used': datetime.fromtimestamp(item.modified, UTC).isoformat(),
                           'path': str(item.path)} for item in items], indent=2))
        return 0
    if not items:
        print('No matching sessions.')
        return 0
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        parser.error('interactive selection requires a terminal; use --json to list sessions')
    selected = select_sessions(items)
    if not selected:
        print('Nothing selected; nothing deleted.')
        return 0
    total = sum(item.size for item in selected)
    for item in selected:
        print(f'{clean(item.project)}  {item.sid}  {human(item.size)}  {item.title[:120]}')
    if args.dry_run:
        print(f'Would delete {len(selected)} sessions, {human(total)}; nothing deleted.')
        return 0
    try:
        answer = input(f'Delete {len(selected)} sessions, {human(total)}? [y/N] ')
    except EOFError:
        answer = ''
    if answer.strip().lower() not in ('y', 'yes'):
        print('Cancelled; nothing deleted.')
        return 0
    deleted, failed = 0, 0
    for item in selected:
        try:
            delete_session(item, SESSION_DIRS)
            deleted += 1
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            failed += 1
            print(f'not deleted: {item.sid}: {error}', file=sys.stderr)
    print(f'Deleted {deleted} sessions; failed/skipped {failed}.')
    return int(bool(failed))


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print('\nCancelled.', file=sys.stderr)
        sys.exit(130)
    except (OSError, ValueError) as error:
        sys.exit(str(error))
