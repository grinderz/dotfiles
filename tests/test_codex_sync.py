"""Session-store migration and chezmoi link preflight on temporary directories."""

import io
import json
import runpy
import shutil
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / 'home'


class CodexSyncTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.local = self.home / '.codex'
        self.store = self.home / 'shared'
        self.migrate = runpy.run_path(str(SOURCE / 'dot_local/bin/executable_codex-sync-state'))['migrate']

    def test_failed_link_preserves_original_directory_and_allows_retry(self):
        for initial in ('shared', 'local'):
            with self.subTest(initial=initial):
                home = self.home / initial / '.codex'
                store = self.home / initial / 'store'
                origin = (store if initial == 'shared' else home) / 'sessions'
                origin.mkdir(parents=True)
                transcript = origin / 'example.jsonl'
                transcript.write_text('fixture')
                with (
                    patch.object(Path, 'symlink_to', side_effect=OSError('link failure')),
                    self.assertRaisesRegex(OSError, 'link failure'),
                ):
                    self.migrate(home, store)
                self.assertEqual(transcript.read_text(), 'fixture')
                with redirect_stdout(io.StringIO()):
                    self.migrate(home, store)
                self.assertTrue((home / 'sessions').samefile(store / 'sessions'))
                self.assertEqual((store / 'sessions/example.jsonl').read_text(), 'fixture')

    @unittest.skipUnless(shutil.which('chezmoi'), 'link templates require chezmoi')
    def test_check_both_links_before_rendering_either(self):
        self.local.mkdir()
        for name in ('sessions', 'archived_sessions'):
            (self.store / name).mkdir(parents=True)
        (self.local / 'sessions').symlink_to('../shared/sessions')
        other = self.home / 'previous'
        other.mkdir()
        link = self.local / 'archived_sessions'
        link.symlink_to(other)
        cmd = ['chezmoi', '--config', '/dev/null', '--config-format', 'toml',
               '--source', str(SOURCE), '--persistent-state', str(self.home / 'state.db'),
               '--override-data', json.dumps({'chezmoi': {'homeDir': str(self.home)},
                                              'codex': {'sync': [{'dir': 'shared'}]}}),
               'execute-template', '--file', str(SOURCE / 'dot_codex/symlink_sessions.tmpl')]
        result = subprocess.run(cmd, check=False, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f'{link} points elsewhere', result.stderr)
        link.unlink()
        link.symlink_to(self.store / 'archived_sessions')
        self.assertEqual(subprocess.check_output(cmd, text=True).strip(), str(self.store / 'sessions'))
