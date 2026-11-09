"""Portable project selection without rewriting transcripts or native state."""

import json
import os
import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

WRAPPER = Path(__file__).resolve().parents[1] / 'home/dot_local/bin/executable_codex'
FIRST = '00000000-0000-4000-8000-000000000001'
SECOND = '00000000-0000-4000-8000-000000000002'


class CodexResumeTest(unittest.TestCase):
    def setUp(self):
        self.module = runpy.run_path(str(WRAPPER))
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.codex_home = self.home / '.codex'
        self.project = self.home / 'src/personal/dotfiles'
        self.project.mkdir(parents=True)

    def transcript(self, sid=FIRST, cwd='/Users/test/src/personal/dotfiles', source='cli',
                   title='Fix startup', archived=False, modified=100):
        root = self.codex_home / ('archived_sessions' if archived else 'sessions') / '2026/11/09'
        root.mkdir(parents=True, exist_ok=True)
        path = root / f'rollout-2026-11-09T08-00-00-{sid}.jsonl'
        records = [
            {'type': 'session_meta', 'payload': {'id': sid, 'cwd': cwd, 'source': source}},
            {'type': 'event_msg', 'payload': {'type': 'user_message', 'message': title}},
        ]
        path.write_text(''.join(json.dumps(record) + '\n' for record in records))
        os.utime(path, (modified, modified))
        return path

    def matching(self, **kwargs):
        return self.module['matching_sessions'](self.project, home=self.home,
                                                codex_home=self.codex_home, **kwargs)

    def test_match_full_home_relative_path_across_machines(self):
        key = self.module['project_key']
        self.assertEqual(key('/home/alice/src/personal/dotfiles'),
                         key('/Users/bob/src/personal/dotfiles'))
        self.assertNotEqual(key('/Users/bob/work/dotfiles'), key('/Users/bob/personal/dotfiles'))
        self.assertNotEqual(key('/opt/src/personal/dotfiles'), key('/Users/bob/src/personal/dotfiles'))
        path = self.transcript()
        before = path.read_bytes()
        self.transcript(SECOND, '/home/test/work/dotfiles')
        self.assertEqual([item[1] for item in self.matching()], [FIRST])
        self.assertEqual(path.read_bytes(), before)

    def test_sort_by_last_write_and_skip_archives_conflicts_and_partial_files(self):
        path = self.transcript(modified=100)
        self.transcript(SECOND, '/home/other/src/personal/dotfiles', modified=200)
        self.transcript(archived=True, modified=300)
        path.with_name(path.stem + '.sync-conflict-copy.jsonl').write_bytes(path.read_bytes())
        path.with_name('rollout-incomplete.jsonl').write_text('{"type":')
        self.assertEqual([item[1] for item in self.matching()], [SECOND, FIRST])

    def test_local_directory_aliases_resolve_to_the_same_project(self):
        alias = self.root / 'alias'
        alias.symlink_to(self.project, target_is_directory=True)
        self.transcript(cwd=str(alias))
        self.assertEqual([item[1] for item in self.matching()], [FIRST])

    def test_non_interactive_is_opt_in_and_titles_are_safe_for_terminal_rows(self):
        self.transcript(source='exec', title='Fix\nstartup\t\x1b[31m')
        self.assertEqual(self.matching(), [])
        items = self.matching(include_non_interactive=True)
        self.assertEqual(items[0][2], 'Fix startup [31m')
        self.transcript(source={'subagent': {'thread_spawn': {}}})
        self.assertEqual(self.matching(), [])

    def test_metadata_accepts_current_event_format(self):
        path = self.transcript()
        with path.open('w') as stream:
            stream.write(json.dumps({'type': 'session_meta', 'payload': {
                'id': FIRST, 'cwd': str(self.project), 'source': 'vscode',
            }}) + '\n')
            stream.write(json.dumps({'type': 'event_msg', 'payload': {
                'type': 'item_completed', 'item': {'type': 'UserMessage', 'content': [
                    {'type': 'text', 'text': 'Fix startup'},
                ]},
            }}) + '\n')
        self.assertEqual(self.matching()[0][2], 'Fix startup')

    def test_flags_choose_portable_uuid_and_preserve_user_overrides(self):
        resume = self.module['resume_defaults']
        items = [(200, SECOND, 'Newer'), (100, FIRST, 'Older')]
        with patch.dict(resume.__globals__, matching_sessions=lambda *a, **kw: items,
                        select_session=lambda *a: FIRST):
            self.assertEqual(resume(['resume']), ['-c', 'tui.resume_cwd="current"', 'resume', FIRST])
            self.assertEqual(resume(['resume', '--last']),
                             ['-c', 'tui.resume_cwd="current"', 'resume', SECOND])
            args = ['--cd', str(self.project), 'resume', '-c', 'tui.resume_cwd="session"']
            self.assertEqual(resume(args), ['-c', 'tui.resume_cwd="current"', *args[:3], FIRST, *args[3:]])
            self.assertEqual(resume(['resume', '--last', '--']),
                             ['-c', 'tui.resume_cwd="current"', 'resume', SECOND, '--'])

    def test_cd_forms_and_codex_home(self):
        self.transcript(cwd=str(self.project))
        resume = self.module['resume_defaults']
        with patch.dict(os.environ, CODEX_HOME=str(self.codex_home)):
            for cd in (['-C', str(self.project)], ['--cd=' + str(self.project)], ['-C' + str(self.project)]):
                result = resume([*cd, 'resume', '--last'])
                self.assertIn(FIRST, result)
                self.assertNotIn('--last', result)

    def test_explicit_ids_all_and_native_commands_never_open_fzf(self):
        resume = self.module['resume_defaults']
        with patch.dict(resume.__globals__, matching_sessions=lambda *a, **kw: self.fail('unexpected scan')):
            for args in (['resume', FIRST], ['resume', '--all'], ['resume', '--all', '--last'],
                         ['resume', '--', FIRST], ['resume', '--last', 'prompt']):
                self.assertEqual(resume(args), ['-c', 'tui.resume_cwd="current"', *args])
            for args in (['exec', 'resume'], ['-m', 'resume'], ['--', 'resume'], ['resume', '--help'],
                         ['resume', '--version'], ['resume', '-V'],
                         ['--remote=unix:///tmp/server.sock', 'resume'], ['resume', '--remote', 'server']):
                self.assertEqual(resume(args), args)

    def test_empty_project_does_not_fall_back_to_other_projects(self):
        resume = self.module['resume_defaults']
        with (patch.dict(resume.__globals__, matching_sessions=lambda *a, **kw: []),
              self.assertRaisesRegex(SystemExit, 'no matching sessions')):
            resume(['resume', '--last'])

    def test_cancel_does_not_launch_native_resume(self):
        select = self.module['select_session']
        with (patch('shutil.which', return_value='/usr/bin/fzf'),
              patch('sys.stdin.isatty', return_value=True), patch('subprocess.run') as run):
            run.return_value = subprocess.CompletedProcess([], 130, '')
            with self.assertRaises(SystemExit) as error:
                select([(1, FIRST, 'Test')], self.project)
            self.assertEqual(error.exception.code, 0)

    def test_end_to_end_last_passes_uuid_to_real_binary(self):
        self.transcript(cwd=str(self.project))
        binary_dir = self.root / 'bin'
        binary_dir.mkdir()
        binary = binary_dir / 'codex'
        capture = self.root / 'arguments'
        binary.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$CAPTURE"\n')
        binary.chmod(0o755)
        env = dict(os.environ, PATH=str(binary_dir), CODEX_HOME=str(self.codex_home), CAPTURE=str(capture))
        subprocess.run([sys.executable, str(WRAPPER), '-C', str(self.project), 'resume', '--last'],
                       env=env, check=True, capture_output=True)
        self.assertEqual(capture.read_text().splitlines(),
                         ['-c', 'tui.resume_cwd="current"', '-C', str(self.project), 'resume', FIRST])


if __name__ == '__main__':
    unittest.main()
