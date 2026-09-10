"""Streaming paste, foreground handoff and multiplexed input in a real PTY."""
import errno
import fcntl
import os
import pty
import select
import signal
import struct
import tempfile
import termios
import threading
import time
import unittest
import test_features
import test_clipping
from test_drawing import drawing_session

ROOT, ZSH = test_features.ROOT, test_features.ZSH


class SessionTests(unittest.TestCase):
    def session(self, mode='native', modules=None):
        control_r, control_w = os.pipe()
        report_r, report_w = os.pipe()
        pid, terminal = pty.fork()
        if pid == 0:
            os.close(control_w); os.close(report_r)
            os.set_inheritable(control_r, True); os.set_inheritable(report_w, True)
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
            os.environ.update(TERM='xterm-256color', LC_ALL='C.UTF-8')
            os.environ.pop('LINES', None); os.environ.pop('COLUMNS', None)
            os.execl(ZSH, ZSH, '-df', str(ROOT / 'tests/session.zsh'),
                     str(modules or ROOT / '.build/modules'), mode, str(report_w), str(control_r))
        os.close(control_r); os.close(report_w)
        pending, screen = bytearray(), bytearray()
        reaped = False
        original = None
        timers = []
        payloads = {'enabled': b'\x1b[200~A\x00\xc3\xa9\r\x03\x13\x1b[20',
                    'partial': b'1xB\x1b[20', 'finish': b'1~Z',
                    'large': b'\x1b[200~' + b'x' * 5000 + b'\x1b[201~q',
                    'resumed': b'\x1b[200~unfinished'}

        def read_screen():
            try:
                screen.extend(os.read(terminal, 65536))
            except OSError as exc:
                if exc.errno != errno.EIO:
                    raise

        try:
            while True:
                deadline = time.monotonic() + 15
                while b'\n' not in pending:
                    remaining = deadline - time.monotonic()
                    self.assertGreater(remaining, 0, bytes(screen[-4000:]))
                    for fd in select.select([terminal, report_r], [], [], remaining)[0]:
                        if fd == terminal:
                            read_screen()
                        else:
                            data = os.read(report_r, 4096)
                            self.assertTrue(data, bytes(screen[-4000:]))
                            pending.extend(data)
                step, _, rest = pending.partition(b'\n'); pending[:] = rest
                if step == b'done':
                    break
                while select.select([terminal], [], [], 0)[0]:
                    read_screen()
                step = step.decode()
                if step == 'baseline':
                    original = termios.tcgetattr(terminal)
                elif step == 'pasteoff':
                    mode_flags = termios.tcgetattr(terminal)[3]
                    self.assertTrue(mode_flags & termios.ISIG)
                    self.assertFalse(mode_flags & termios.ICANON)
                elif step == 'suspended':
                    self.assertEqual(termios.tcgetattr(terminal), original)
                    self.assertIn(b'\x1b[?2004l', screen)
                    fcntl.ioctl(terminal, termios.TIOCSWINSZ, struct.pack('HHHH', 32, 100, 0, 0))
                    os.write(terminal, b'foreground\n')
                elif step == 'splitbegin':
                    os.write(terminal, b'\x1b[20')
                    timer = threading.Timer(0.02, os.write, args=(terminal, b'0~fragment\x1b[201~'))
                    timers.append(timer); timer.start()
                else:
                    self.assertIn(step, payloads)
                    if step == 'resumed':
                        self.assertIn(b'QUEUEDFRAME', screen)
                    else:
                        self.assertNotIn(b'QUEUEDFRAME', screen)
                    if step == 'enabled':
                        self.assertIn(b'\x1b[?2004h', screen)
                    os.write(terminal, payloads[step])
                os.write(control_w, b'continue\n')
            _, status = os.waitpid(pid, 0); reaped = True
            self.assertEqual(os.waitstatus_to_exitcode(status), 0, bytes(screen[-4000:]))
            self.assertEqual(termios.tcgetattr(terminal), original)
        finally:
            for timer in timers:
                timer.join()
            if not reaped:
                os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0)
            for fd in (control_w, report_r, terminal):
                os.close(fd)

    def test_streaming_and_session_handoff(self):
        self.session()

    def test_optional_session_features(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text().replace(
            '#include <stdio.h>', '#include <stdio.h>\n#undef HAVE_DEFINE_KEY\n'
            '#undef HAVE_DEF_PROG_MODE\n#undef HAVE_GET_ESCDELAY', 1)
        with tempfile.TemporaryDirectory(prefix='session-optional-', dir=ROOT / '.build') as tmp:
            modules = test_features.FeatureTests().variant(tmp, source)
            self.session('unavailable', modules)

    def test_streaming_sgr_decoder(self):
        test_clipping.ClippingTests().headless(fixture='sgr.zsh', marker='SGR PASS')

    def test_session_failures(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        for mode, before, after in (
            ('paste_failure', 'define_key("\\033[200~", code) == ERR', '1'),
            ('suspend_failure', 'def_prog_mode() == ERR', '1'),
            ('resume_failure', 'reset_prog_mode() == ERR', '1'),
        ):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(prefix='session-fail-', dir=ROOT / '.build') as tmp:
                self.assertIn(before, source)
                modules = test_features.FeatureTests().variant(tmp, source.replace(before, after, 1))
                drawing_session(self, mode, modules, fixture='session-errors.zsh', marker=b'SESSION ERRORS PASS')


if __name__ == '__main__':
    unittest.main(verbosity=2)
