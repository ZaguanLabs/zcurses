"""Real module tests with kernel PTY resizing; no interactive terminal needed."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import subprocess
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULES = ROOT / '.build/modules'
ZSH = shutil.which(os.environ.get('ZSH_TEST_SHELL', str(ROOT / '.build/zsh/Src/zsh')))
if ZSH is None:
    raise RuntimeError('Build Zsh first with make build, or set ZSH_TEST_SHELL to a matching shell')


class GeometryTests(unittest.TestCase):
    def test_geometry_and_legacy_operations(self):
        self.geometry_session()

    def geometry_session(self, terminal_type='xterm-256color', terminfo=None):
        control_r, control_w = os.pipe()
        report_r, report_w = os.pipe()
        pid, terminal = pty.fork()
        if pid == 0:
            os.close(control_w)
            os.close(report_r)
            os.set_inheritable(control_r, True)
            os.set_inheritable(report_w, True)
            # Set the initial size before the shell initializes.
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
            os.environ['TERM'] = terminal_type
            if terminfo:
                os.environ['TERMINFO'] = terminfo
            os.environ.pop('LINES', None)
            os.environ.pop('COLUMNS', None)
            os.execl(ZSH, ZSH, '-df', str(ROOT / 'tests/geometry.zsh'),
                     str(MODULES), str(control_r), str(report_w))

        os.close(control_r)
        os.close(report_w)
        pending = bytearray()
        screen = bytearray()
        reaped = False

        def line():
            deadline = time.monotonic() + 10
            while b'\n' not in pending:
                remaining = deadline - time.monotonic()
                self.assertGreater(remaining, 0, 'Timed out waiting for fixture')
                ready, _, _ = select.select([report_r, terminal], [], [], remaining)
                for fd in ready:
                    try:
                        data = os.read(fd, 65536)
                    except OSError as exc:
                        if fd == terminal and exc.errno == errno.EIO:
                            continue
                        raise
                    if fd == report_r:
                        self.assertTrue(data, f'Fixture exited early: {pending!r}')
                        pending.extend(data)
                    else:
                        screen.extend(data)
            result, _, rest = pending.partition(b'\n')
            pending[:] = rest
            return result.decode()

        def advance(rows=None, columns=None):
            if rows is not None:
                fcntl.ioctl(terminal, termios.TIOCSWINSZ,
                            struct.pack('HHHH', rows, columns, 0, 0))
            os.write(control_w, b'continue\n')

        def drain_screen():
            while select.select([terminal], [], [], 0)[0]:
                try:
                    data = os.read(terminal, 65536)
                except OSError as exc:
                    if exc.errno == errno.EIO:
                        break
                    raise
                if not data:
                    break
                screen.extend(data)

        try:
            self.assertEqual(line(), 'before 24 80')
            drain_screen()
            self.assertEqual(screen, b'', 'Geometry must not emit terminal output')
            original_mode = termios.tcgetattr(terminal)
            advance()
            self.assertEqual(line(), 'ready 24 80')
            drain_screen()
            screen.clear()
            curses_mode = termios.tcgetattr(terminal)
            os.write(terminal, b'Z')
            advance(40, 120)
            self.assertEqual(line(), 'resized 40 120 cached 24 80')
            self.assertEqual(termios.tcgetattr(terminal), curses_mode)
            drain_screen()
            self.assertEqual(screen, b'', 'Geometry must not refresh the screen')
            advance(0, 0)
            self.assertEqual(line(), 'zero 1 sentinel')
            advance(32, 100)
            self.assertEqual(line(), 'input Z')
            self.assertEqual(line(), 'local 32 100')
            self.assertEqual(line(), 'readonly 1')
            self.assertEqual(line(), 'missing 1')
            self.assertEqual(line(), 'extra 1')
            self.assertEqual(line(), 'after 32 100')
            self.assertEqual(termios.tcgetattr(terminal), original_mode)
            _, result = os.waitpid(pid, 0)
            reaped = True
            self.assertEqual(os.waitstatus_to_exitcode(result), 0)
        finally:
            if not reaped:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                os.waitpid(pid, 0)
            for fd in (control_w, report_r, terminal):
                os.close(fd)

    def test_no_controlling_terminal(self):
        result = subprocess.run(
            [ZSH, '-dfc', '''
                module_path=("$1")
                zmodload zdraw || exit 99
                typeset -a dimensions=(sentinel)
                zdraw geometry dimensions
                print -r -- "$? ${(j: :)dimensions}"
            ''', 'geometry-test', str(MODULES)],
            start_new_session=True, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '1 sentinel\n')
        self.assertEqual(result.stderr, '')


if __name__ == '__main__':
    unittest.main(verbosity=2)
