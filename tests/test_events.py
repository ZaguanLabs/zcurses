"""Structured input from real PTY bytes, shared legacy decoding and cleanup."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time
import unittest
import test_features

ROOT, ZSH = test_features.ROOT, test_features.ZSH


class EventTests(unittest.TestCase):
    def session(self, mode='wide', modules=None, norefresh=False):
        locales = subprocess.run(['locale', '-a'], capture_output=True, text=True, check=True).stdout.splitlines()
        locale = os.environ.get('ZDRAW_TEST_LOCALE') or next(
            (name for name in locales if 'utf8' in name.lower().replace('-', '')), None)
        self.assertIsNotNone(locale, 'Events tests require a UTF-8 locale')
        control_r, control_w = os.pipe()
        report_r, report_w = os.pipe()
        pid, terminal = pty.fork()
        if pid == 0:
            os.close(control_w)
            os.close(report_r)
            os.set_inheritable(control_r, True)
            os.set_inheritable(report_w, True)
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
            os.environ.update(TERM='xterm-256color', LC_ALL=locale)
            os.environ.pop('LINES', None)
            os.environ.pop('COLUMNS', None)
            os.execl(ZSH, ZSH, '-df', str(ROOT / 'tests/events.zsh'),
                     str(modules or ROOT / '.build/modules'), mode, str(report_w), str(control_r),
                     'norefresh' if norefresh else '')
        os.close(control_r)
        os.close(report_w)
        pending, screen = bytearray(), bytearray()
        original_mode = None
        reaped = False
        steps = []
        payloads = {'ascii': b'a', 'encoded': b'\xff' if mode == 'narrow' else 'é'.encode(),
                    'nul': b'\x00', 'up': b'\x1bOA', 'function': b'\x1b[15~',
                    'legacy': b'L', 'local': b'E', 'create': b'C',
                    'mouseoff': b'N',
                    'mouseagain': b'\x1b[<0;5;3M\x1b[<0;5;3m',
                    'mouse': b'\x1b[<0;5;3M\x1b[<0;5;3m'}

        def line():
            deadline = time.monotonic() + 10
            while b'\n' not in pending:
                remaining = deadline - time.monotonic()
                self.assertGreater(remaining, 0, screen.decode(errors='replace'))
                for fd in select.select([report_r, terminal], [], [], remaining)[0]:
                    try:
                        data = os.read(fd, 65536)
                    except OSError as exc:
                        if fd != terminal or exc.errno != errno.EIO:
                            raise
                        data = b''
                    if fd == report_r:
                        self.assertTrue(data, f'{steps}: ' + screen.decode(errors='replace'))
                        pending.extend(data)
                    else:
                        screen.extend(data)
            result, _, rest = pending.partition(b'\n')
            pending[:] = rest
            return result.decode()

        try:
            while True:
                step = line()
                if step == 'done':
                    break
                if step == 'baseline':
                    original_mode = termios.tcgetattr(terminal)
                    os.write(control_w, b'continue\n')
                    continue
                steps.append(step)
                if step == 'resize':
                    fcntl.ioctl(terminal, termios.TIOCSWINSZ, struct.pack('HHHH', 32, 100, 0, 0))
                    os.write(terminal, b'R')
                else:
                    self.assertIn(step, payloads)
                    os.write(terminal, payloads[step])
                os.write(control_w, b'continue\n')
            _, result = os.waitpid(pid, 0)
            reaped = True
            self.assertEqual(os.waitstatus_to_exitcode(result), 0, screen.decode(errors='replace'))
            self.assertEqual(termios.tcgetattr(terminal), original_mode)
            self.assertEqual(steps[:8], ['ascii', 'encoded', 'nul', 'up', 'function', 'legacy', 'local', 'create'])
        finally:
            if not reaped:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                os.waitpid(pid, 0)
            for fd in (control_w, report_r, terminal):
                os.close(fd)

    def test_structured_events(self):
        self.session()

    def test_norefresh_events(self):
        features = test_features.FeatureTests().run_shell(
            'zmodload zdraw || exit 1; print -rl -- "${zdraw_features[@]}"')
        if 'norefresh_events' not in features.splitlines():
            self.skipTest('No no-refresh input support in this curses build')
        self.session(norefresh=True)

    def test_optional_input_paths(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        features = test_features.FeatureTests().run_shell(
            'zmodload zdraw || exit 1; print -rl -- "${zdraw_features[@]}"')
        has_norefresh = 'norefresh_events' in features.splitlines()
        variants = [('narrow', '#undef HAVE_WGET_WCH'),
                    ('nomouse', '#undef NCURSES_MOUSE_VERSION'),
                    ('noncurses', '#undef NCURSES_VERSION')]
        if has_norefresh:
            variants.append(('pad_failure', '#define newpad(y, x) ((WINDOW *)0)'))
        for mode, definition in variants:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(
                    prefix=f'events-{mode}-', dir=ROOT / '.build') as tmp:
                modules = test_features.FeatureTests().variant(
                    tmp, source.replace('#include <stdio.h>', '#include <stdio.h>\n' + definition, 1))
                self.session(mode, modules)
                if has_norefresh and mode in ('narrow', 'nomouse'):
                    self.session(mode, modules, norefresh=True)


if __name__ == '__main__':
    unittest.main(verbosity=2)
