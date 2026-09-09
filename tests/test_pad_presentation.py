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


class PadPresentationTests(unittest.TestCase):
    def test_pad_staging_and_input_ownership(self):
        features = test_features.FeatureTests().run_shell(
            'zmodload zdraw || exit 1; print -rl -- "${zdraw_features[@]}"')
        if not {'norefresh_events', 'offscreen_pads'}.issubset(features.splitlines()):
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
            os.execl(ZSH, ZSH, '-df', str(ROOT / 'tests/pad-presentation.zsh'),
                     str(ROOT / '.build/modules'), str(report_w), str(control_r))
        os.close(control_r)
        os.close(report_w)
        pending, screen = bytearray(), bytearray()
        reaped = False
        original_mode = None
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
                elif step in (b'staged', b'input'):
                    self.assertIn(b'BASELINE', screen)
                    self.assertNotIn(b'FRAMEHEADER', screen)
                    self.assertNotIn(b'PADSECRET', screen)
                    if step == b'staged':
                        os.write(terminal, b'X')
                elif step == b'presented':
                    self.assertIn(b'FRAMEHEADER', screen)
                    self.assertIn(b'PADSECRET', screen)
                elif step == b'moved':
                    self.assertNotIn(b'SCROLLEDVIEW', screen)
                elif step == b'movedpresented':
                    self.assertIn(b'SCROLLEDVIEW', screen)
                elif step == b'resized':
                    self.assertNotIn(b'QUEUEDOLD', screen)
                    self.assertNotIn(b'NEWRESIZED', screen)
                elif step in (b'resizedqueuedold', b'restaged'):
                    self.assertIn(b'QUEUEDOLD', screen)
                    self.assertNotIn(b'NEWRESIZED', screen)
                elif step == b'resizedpresented':
                    self.assertIn(b'NEWRESIZED', screen)
                else:
                    self.fail(f'Unexpected step: {step!r}')
                os.write(control_w, b'continue\n')
            _, status = os.waitpid(pid, 0)
            reaped = True
            self.assertEqual(os.waitstatus_to_exitcode(status), 0, bytes(screen))
            self.assertEqual(termios.tcgetattr(terminal), original_mode)
            expected = [b'baseline', b'staged', b'input',
                        b'presented', b'moved', b'movedpresented']
            if 'pad_resize' in features.splitlines():
                expected += [b'resized', b'resizedqueuedold', b'restaged', b'resizedpresented']
            self.assertEqual(steps, expected)
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
