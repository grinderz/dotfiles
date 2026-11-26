"""The fan popup queries once; ordinary Waybar updates never query the EC."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'home/dot_local/bin/executable_system-stats'


@unittest.skipUnless(shutil.which('jq'), 'requires jq')
class SystemStatsTest(unittest.TestCase):
    def invoke(self, *, popup, installed=True, sudo_fails=False):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            capture = root / 'capture'
            capture.mkdir()
            for command, content in {
                'foot': 'printf "opened\\n" >> "$CAPTURE/foot"\n'
                        'while [ "$1" != sh ]; do shift; done\nexec "$@"\n',
                'sudo': 'printf "%s\\n" "$@" > "$CAPTURE/sudo"\n'
                        '[ "$SUDO_FAIL" = 1 ] && { echo "authentication failed" >&2; exit 1; }\n'
                        '[ "$1" = -- ] && shift\nexec "$@"\n',
            }.items():
                path = root / command
                path.write_text('#!/bin/sh\n' + content)
                path.chmod(0o755)
            home = root / 'test home'
            prefix = home / '.local/bin'
            prefix.mkdir(parents=True)
            # A different executable at the front of PATH must never be selected.
            shadow = root / 'thinkbook-fanctl'
            shadow.write_text('#!/bin/sh\nexit 99\n')
            shadow.chmod(0o755)
            if installed:
                path = prefix / 'thinkbook-fanctl'
                path.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CAPTURE/queries"\n'
                                'printf \'%s\\n\' \'{"control_mode":"auto","fans":[{"id":1,"rpm":2200,"target_rpm":2200},'
                                '{"id":2,"rpm":1900,"target_rpm":1900}]}\'\n')
                path.chmod(0o755)
            result = subprocess.run(
                ['sh', str(SCRIPT), *(['fans'] if popup else [])],
                input='\n', text=True, capture_output=True, timeout=5, check=False,
                env=dict(os.environ, HOME=str(home), PATH=str(root) + ':/usr/bin:/bin', CAPTURE=str(capture),
                         SUDO_FAIL='1' if sudo_fails else '0'),
            )
            captures = {path.name: path.read_text() for path in capture.iterdir()
                        if path.name in ('queries', 'sudo')}
            return result, captures

    def test_popup_requests_read_only_telemetry_once(self):
        result, captures = self.invoke(popup=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(captures['queries'], 'status --json --brief\n')
        self.assertEqual(captures['sudo'].splitlines()[-3:], ['status', '--json', '--brief'])
        self.assertIn('Control: auto', result.stdout)
        self.assertIn('Fan 1: 2200 RPM (target 2200 RPM)', result.stdout)
        self.assertIn('Fan 2: 1900 RPM (target 1900 RPM)', result.stdout)
        self.assertIn('Enter or Escape to close', result.stdout)

    def test_regular_updates_do_not_query_fans(self):
        result, captures = self.invoke(popup=False)
        self.assertEqual(result.returncode, 0)
        self.assertIn('tooltip', json.loads(result.stdout))
        self.assertEqual(captures, {})

    def test_missing_utility_and_authentication_failure_stay_visible(self):
        result, captures = self.invoke(popup=True, installed=False)
        self.assertIn('not installed', result.stdout)
        self.assertEqual(captures, {})
        result, captures = self.invoke(popup=True, sudo_fails=True)
        self.assertIn('authentication failed', result.stderr)
        self.assertIn('Enter or Escape to close', result.stdout)
        self.assertNotIn('queries', captures)


if __name__ == '__main__':
    unittest.main()
