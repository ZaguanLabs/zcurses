"""Observe actual terminal bytes across explicit input/presentation barriers."""
import errno
import fcntl
import os
import pty
import select
import signal
import struct
import termios
import time
import unittest
import test_features

ROOT, ZSH = test_features.ROOT, test_features.ZSH


class PresentationTests(unittest.TestCase):
    def test_input_does_not_present_dirty_windows(self):
        features = test_features.FeatureTests().run_shell(
            'zmodload zdraw || exit 1; print -rl -- "${zdraw_features[@]}"')
        if 'norefresh_events' not in features.splitlines():
            self.skipTest('No no-refresh input support in this curses build')
        control_r, control_w = os.pipe()
        report_r, report_w = os.pipe()
        pid, terminal = pty.fork()
        if pid == 0:
            os.close(control_w)
            os.close(report_r)
            os.set_inheritable(control_r, True)
            os.set_inheritable(report_w, True)
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
            os.environ.update(TERM='xterm-256color', LC_ALL='C')
            os.environ.pop('LINES', None)
            os.environ.pop('COLUMNS', None)
            os.execl(ZSH, ZSH, '-df', str(ROOT / 'tests/presentation.zsh'),
                     str(ROOT / '.build/modules'), str(report_w), str(control_r))
        os.close(control_r)
        os.close(report_w)
        pending, screen = bytearray(), bytearray()
        reaped = False
        original_mode = started = None
        steps = []

        def read_terminal():
            try:
                screen.extend(os.read(terminal, 65536))
            except OSError as exc:
                if exc.errno != errno.EIO:
                    raise

        try:
            while True:
                deadline = time.monotonic() + 10
                while b'\n' not in pending:
                    remaining = deadline - time.monotonic()
                    self.assertGreater(remaining, 0, bytes(screen))
                    for fd in select.select([report_r, terminal], [], [], remaining)[0]:
                        if fd == terminal:
                            read_terminal()
                        else:
                            data = os.read(report_r, 4096)
                            self.assertTrue(data, bytes(screen))
                            pending.extend(data)
                step, _, rest = pending.partition(b'\n')
                pending[:] = rest
                if step == b'done':
                    break
                steps.append(step)
                # The child is blocked on the control pipe. Drain all output
                # written before its report; no sleep or assumed PTY ordering.
                while select.select([terminal], [], [], 0)[0]:
                    read_terminal()
                if step == b'baseline':
                    original_mode = termios.tcgetattr(terminal)
                elif step == b'ready':
                    self.assertIn(b'BEFORE', screen)
                    started = time.monotonic()
                elif step in (b'hidden', b'stillhidden'):
                    self.assertNotIn(b'SECRETFRAME', screen)
                    self.assertNotIn(b'HIDDENCHILD', screen)
                    if step == b'hidden':
                        self.assertGreaterEqual(time.monotonic() - started, 0.10)
                        os.write(terminal, b'X\x1bOA')
                elif step == b'presented':
                    self.assertIn(b'SECRETFRAME', screen)
                    self.assertIn(b'HIDDENCHILD', screen)
                elif step == b'legacyvisible':
                    self.assertIn(b'LEGACYVISIBLE', screen)
                else:
                    self.fail(f'Unexpected step: {step!r}')
                os.write(control_w, b'continue\n')
            _, status = os.waitpid(pid, 0)
            reaped = True
            self.assertEqual(os.waitstatus_to_exitcode(status), 0, bytes(screen))
            self.assertEqual(termios.tcgetattr(terminal), original_mode)
            self.assertEqual(steps, [b'baseline', b'ready', b'hidden',
                                     b'stillhidden', b'presented', b'legacyvisible'])
        finally:
            if not reaped:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                os.waitpid(pid, 0)
            for fd in (control_w, report_r, terminal):
                os.close(fd)


if __name__ == '__main__':
    unittest.main(verbosity=2)
