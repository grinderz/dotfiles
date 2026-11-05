"""Deletion regressions using temporary transcripts only; run with python3."""

import json
import os
import runpy
import subprocess
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
        mod['delete_session'](item)
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
            mod['delete_session'](item)
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
        path = self.claude()
        mod = self.module('Claude')
        item = next(mod['sessions']([self.root]))
        mod = self.module('Codex')
        with (
            patch('subprocess.run', side_effect=subprocess.CalledProcessError(1, 'codex')),
            self.assertRaises(subprocess.CalledProcessError),
        ):
            mod['delete_session'](item)
        self.assertTrue(path.exists())

    def test_terminal_controls_are_not_rendered(self):
        self.assertEqual(self.module('Claude')['clean']('hello\x1b[31m\nworld\t!'), 'hello [31m world !')


if __name__ == '__main__':
    unittest.main()
