"""Deletion regressions using temporary transcripts only; run with python3."""

import json
import os
import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / 'home/dot_local/libexec/session-prune.py'


class SessionPruneTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def module(self, agent):
        return runpy.run_path(str(SOURCE), init_globals={'Path': Path, 'AGENT': agent})

    def claude(self, name='one', text='Test conversation'):
        path = self.root / 'project' / f'{name}.jsonl'
        path.parent.mkdir(exist_ok=True)
        path.write_text(json.dumps({'type': 'user', 'message': {'content': text}}) + '\n')
        return path

    def test_all_ages_and_duplicate_roots(self):
        recent = self.claude('recent')
        old = self.claude('old')
        os.utime(old, (0, 0))
        mod = self.module('Claude')
        items = list(mod['sessions']([self.root, self.root]))
        self.assertEqual({item.path for item in items}, {recent, old})

    def test_delete_selected_claude_only_and_keep_memory(self):
        selected = self.claude('selected')
        kept = self.claude('kept')
        memory = selected.parent / 'memory' / 'MEMORY.md'
        memory.parent.mkdir()
        memory.write_text('remember')
        extra = selected.with_suffix('')
        extra.mkdir()
        (extra / 'child.jsonl').write_text('subagent')
        (extra / 'memory-link').symlink_to(memory)
        mod = self.module('Claude')
        item = next(item for item in mod['sessions']([self.root]) if item.path == selected)
        mod['delete_session'](item, [self.root])
        self.assertFalse(selected.exists())
        self.assertFalse(extra.exists())
        self.assertTrue(kept.exists())
        self.assertEqual(memory.read_text(), 'remember')

    def test_changed_session_is_not_deleted(self):
        path = self.claude()
        mod = self.module('Claude')
        item = next(mod['sessions']([self.root]))
        with path.open('a') as stream:
            stream.write('new activity\n')
        with self.assertRaisesRegex(ValueError, 'changed while selecting'):
            mod['delete_session'](item, [self.root])
        self.assertTrue(path.exists())

    def test_codex_active_archived_and_conflict_copy(self):
        sid = '00000000-0000-4000-8000-000000000001'
        roots = [self.root / 'sessions', self.root / 'archived_sessions']
        for root in roots:
            root.mkdir()
            path = root / f'rollout-test-{sid}.jsonl'
            data = {'type': 'session_meta', 'payload': {'id': sid, 'cwd': '/Users/test/src/project'}}
            message = {'type': 'event_msg', 'payload': {'type': 'item_completed', 'item': {
                'type': 'UserMessage', 'content': [{'type': 'text', 'text': 'Fix service startup'}]}}}
            path.write_text(json.dumps(data) + '\n' + json.dumps(message) + '\n')
            (root / f'rollout-test-{sid}.sync-conflict-other.jsonl').write_text(path.read_text())
        mod = self.module('Codex')
        items = list(mod['sessions'](roots, 'PROJECT'))
        self.assertEqual({item.status for item in items}, {'active', 'archived'})
        self.assertEqual(len(items), 2)
        self.assertTrue(all(item.title == 'Fix service startup' for item in items))

    def test_codex_failure_never_falls_back_to_unlink(self):
        roots = [self.root / 'sessions', self.root / 'archived_sessions']
        roots[0].mkdir()
        sid = '00000000-0000-4000-8000-000000000001'
        path = roots[0] / f'rollout-test-{sid}.jsonl'
        data = {'type': 'session_meta', 'payload': {'id': sid, 'cwd': '/project'}}
        path.write_text(json.dumps(data))
        mod = self.module('Codex')
        item = next(mod['sessions'](roots))
        with (
            patch.dict(os.environ, CODEX_HOME=str(self.root / 'other')),
            patch('subprocess.run') as delete,
        ):
            with self.assertRaisesRegex(ValueError, 'selected transcript store'):
                mod['delete_session'](item, roots)
            delete.assert_not_called()
        with (
            patch.dict(os.environ, CODEX_HOME=str(self.root)),
            patch('subprocess.run', side_effect=subprocess.CalledProcessError(1, 'codex')) as delete,
        ):
            with self.assertRaises(subprocess.CalledProcessError):
                mod['delete_session'](item, roots)
            delete.assert_called_once_with(['codex', 'delete', sid, '--force'], check=True)
            roots[1].mkdir()
            (roots[1] / path.name).write_text('incomplete copy')
            with self.assertRaisesRegex(ValueError, 'single transcript'):
                mod['delete_session'](item, roots)
            self.assertEqual(delete.call_count, 1)
        self.assertTrue(path.exists())

    def test_damaged_records_are_reported_separately_from_json(self):
        good = self.claude('good')
        bad = self.claude('bad')
        bad.write_text('{"type":"user","message":null}\n')
        late = self.claude('large', text='a' * (512 * 1024))
        with late.open('a') as stream:
            stream.write('{broken\n')
        args = [sys.executable, str(SOURCE), '--agent', 'Claude', '--dir', str(self.root), '--json']
        quick = subprocess.run(args, text=True, capture_output=True, check=True)
        self.assertEqual({row['path'] for row in json.loads(quick.stdout)}, {str(good), str(late)})
        full = subprocess.run([*args, '--check-all'], text=True, capture_output=True, check=True)
        self.assertEqual([row['path'] for row in json.loads(full.stdout)], [str(good)])
        self.assertIn(f'{bad}: line 1: message must be an object', full.stderr)
        self.assertIn(f'{late}: line 2:', full.stderr)

    def test_null_codex_payload_does_not_abort_listing(self):
        path = self.root / 'rollout-bad.jsonl'
        path.write_text('{"type":"session_meta","payload":null}')
        result = subprocess.run([sys.executable, str(SOURCE), '--agent', 'Codex', '--dir',
                                 str(self.root), '--json'], text=True, capture_output=True, check=True)
        self.assertEqual(json.loads(result.stdout), [])
        self.assertIn(f'{path}: line 1: payload must be an object', result.stderr)

    def test_terminal_controls_are_not_rendered(self):
        self.assertEqual(self.module('Claude')['clean']('hello\x1b[31m\nworld\t!'), 'hello [31m world !')


if __name__ == '__main__':
    unittest.main()
