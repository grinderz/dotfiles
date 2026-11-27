"""Exercise both launchers in a terminal with stand-ins for the native CLIs."""

import os
import pty
import select
import shutil
import subprocess
import sys
import tempfile
import termios
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / 'home'


@unittest.skipUnless(shutil.which('chezmoi'), 'Claude launcher is a chezmoi template')
class SessionLaunchTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        claude = root / 'wrapper.sh'
        with claude.open('w') as script:
            subprocess.run([
                'chezmoi', '--config', '/dev/null', '--config-format', 'toml', '--source', SOURCE,
                '--override-data', '{"claude":{"sync":[]}}', 'execute-template', '--file',
                SOURCE / 'dot_local/bin/executable_claude.tmpl',
            ], stdout=script, check=True)
        self.wrappers = {
            'claude': ['sh', claude],
            'codex': [sys.executable, SOURCE / 'dot_local/bin/executable_codex'],
        }
        for name in self.wrappers:
            binary = root / name
            binary.write_text('#!/bin/sh\nprintf "launched <%s>\\n" "$@"\n[ -t 0 ] || cat\n')
            binary.chmod(0o755)
        self.env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'])

    def terminal(self, name, args, answer):
        master, slave = pty.openpty()
        with os.fdopen(master, 'r+b', buffering=0) as screen, os.fdopen(slave, 'rb') as terminal:
            termios.tcsetwinsize(terminal, (24, 80))
            screen.write(answer)
            subprocess.run([*self.wrappers[name], *args], stdin=terminal, stdout=terminal,
                           stderr=terminal, env=self.env, timeout=5, check=True)
            output = bytearray()
            while select.select([screen], [], [], 0)[0]:
                output.extend(screen.read(4096))
            return output.decode()

    def test_only_y_launches_the_session(self):
        for name in self.wrappers:
            for answer in (b'\n', b'n\n', b'other\n', b'\x04', b'y\n', b'Y\n'):
                with self.subTest(name=name, answer=answer):
                    output = self.terminal(name, [], answer)
                    self.assertIn('[y/N]', output)
                    self.assertEqual('launched' in output, answer.lower() == b'y\n')

    def test_enter_cancels_before_running_any_command(self):
        for name, args in (
            ('claude', ['--resume']), ('claude', ['-p', 'question']), ('claude', ['--version']),
            ('codex', ['resume']), ('codex', ['exec', 'question']), ('codex', ['--help']),
        ):
            with self.subTest(name=name, args=args):
                output = self.terminal(name, args, b'\n')
                self.assertIn('[y/N]', output)
                self.assertNotIn('launched', output)

    def test_confirmation_preserves_command_arguments(self):
        for name, args in (
            ('claude', ['-p', 'a question']), ('codex', ['exec', 'a question']),
        ):
            with self.subTest(name=name, args=args):
                output = self.terminal(name, args, b'y\n')
                self.assertIn('[y/N]', output)
                expected = ''.join(f'launched <{arg}>\n' for arg in args)
                self.assertTrue(output.replace('\r\n', '\n').endswith(expected))

    def test_piped_input_is_preserved(self):
        for command in self.wrappers.values():
            result = subprocess.run(command, input='payload\n', text=True, capture_output=True,
                                    env=self.env, timeout=5, check=True)
            self.assertEqual(result.stdout, 'launched <>\npayload\n')

    def test_redirecting_either_stream_skips_confirmation(self):
        master, slave = pty.openpty()
        with os.fdopen(master, 'rb', buffering=0) as screen, os.fdopen(slave, 'r+b', buffering=0) as terminal:
            termios.tcsetwinsize(terminal, (24, 80))
            for name, command in self.wrappers.items():
                with self.subTest(name=name):
                    result = subprocess.run([*command, '--version'], stdin=terminal, capture_output=True,
                                            env=self.env, timeout=5, check=True)
                    self.assertEqual(result.stdout, b'launched <--version>\n')
                    subprocess.run(command, input=b'payload\n', stdout=terminal, env=self.env, timeout=5, check=True)
                    output = bytearray()
                    while select.select([screen], [], [], 0)[0]:
                        output.extend(screen.read(4096))
                    self.assertEqual(output.splitlines(), [b'launched <>', b'payload'])
