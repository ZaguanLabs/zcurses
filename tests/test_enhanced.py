"""Enhanced input uses the curses queue and restores owned terminal modes."""
import errno
import fcntl
import os
import pty
import select
import signal
import struct
import tempfile
import termios
import time
import unittest
import test_features

ROOT, ZSH = test_features.ROOT, test_features.ZSH


class EnhancedTests(unittest.TestCase):
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
            os.execl(ZSH, ZSH, '-df', str(ROOT / 'tests/enhanced.zsh'),
                     str(modules or ROOT / '.build/modules'), mode, str(report_w), str(control_r))
        os.close(control_r); os.close(report_w)
        payloads = {
            b'focus-query': b'\x1b[?1004;2$y', b'keyboard-query': b'\x1b[?0u',
            b'active': b'\x1b[I\x1b[O\x1b[97;5u\x1b[97;5:2u\x1b[97;5:3u\x1b[97;1;97u\x1b[13u',
            b'coexist': b'\x1b[?0u\x1bOA', b'mouse': b'\x1b[<0;5;3M',
            b'partial': b'\x1b[97;6:', b'finish': b'1;65u',
            b'more': b'\x1b[1;2:3D\x1b[233;1;233:30028u\x1b[97;256u\x1b[60000u',
            b'invalid': b'\x1b[1114112u\x1b[55296u\x1b[97;257u\x1b[97;1:4u\x1b[;1u\x1b[97;1;1::2u\x1b[97;1;1;1u\x1b[97:1:2:3u',
            b'scalars': b'\x1b[97:65:97;1;0:1114111u',
            b'ambiguous': b'\x1bx\x1b[97;\x1b[98;1;98u',
            b'text-limit': b'\x1b[97;1;' + b'97:' * 16 + b'97u',
            b'timeout': b'\x1b[97;', b'overflow': b'\x1b[' + b'1' * 300 + b'uZ',
            b'paste': b'\x1b[200~\x1b[I\x1b[97;5u\x1b[201~',
            b'resumed': b'\x1b[I', b'legacy': b'L',
        }
        pending, screen = bytearray(), bytearray()
        reaped, original = False, None
        try:
            while True:
                deadline = time.monotonic() + 10
                while b'\n' not in pending:
                    remaining = deadline - time.monotonic()
                    self.assertGreater(remaining, 0, bytes(screen[-4000:]))
                    for fd in select.select([terminal, report_r], [], [], remaining)[0]:
                        try:
                            data = os.read(fd, 65536)
                        except OSError as exc:
                            if fd != terminal or exc.errno != errno.EIO:
                                raise
                            data = b''
                        if fd == report_r:
                            self.assertTrue(data, bytes(screen[-4000:]))
                            pending.extend(data)
                        else:
                            screen.extend(data)
                step, _, rest = pending.partition(b'\n'); pending[:] = rest
                step = bytes(step)
                if step == b'done':
                    break
                if step == b'baseline':
                    original = termios.tcgetattr(terminal)
                elif step == b'suspended':
                    self.assertEqual(termios.tcgetattr(terminal), original)
                    self.assertIn(b'\x1b[<u', screen)
                    self.assertIn(b'\x1b[?1004l', screen)
                else:
                    self.assertIn(step, payloads)
                    os.write(terminal, payloads[step])
                if step not in (b'resumed', b'legacy'):
                    self.assertNotIn(b'UNPRESENTED_ENHANCED', screen)
                os.write(control_w, b'continue\n')
            _, status = os.waitpid(pid, 0); reaped = True
            self.assertEqual(os.waitstatus_to_exitcode(status), 0, bytes(screen[-4000:]))
            self.assertEqual(termios.tcgetattr(terminal), original)
            while select.select([terminal], [], [], 0)[0]:
                try:
                    data = os.read(terminal, 65536)
                    if not data: break
                    screen.extend(data)
                except OSError as exc:
                    if exc.errno != errno.EIO: raise
                    break
            if mode != 'unavailable':
                self.assertEqual(screen.count(b'\x1b[>27u'), 3)
                self.assertEqual(screen.count(b'\x1b[<u'), 3)
                self.assertEqual(screen.count(b'\x1b[?1004h'), 3)
                self.assertEqual(screen.count(b'\x1b[?1004l'), 3)
        finally:
            if not reaped:
                os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0)
            for fd in (control_w, report_r, terminal):
                os.close(fd)

    def test_enhanced_lifecycle(self):
        self.session()

    def test_optional_enhanced_builds(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        for mode, undefine in [('unavailable', 'HAVE_CLOCK_GETTIME'), ('narrow', 'HAVE_WGET_WCH')]:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(prefix='enhanced-', dir=ROOT / '.build') as tmp:
                modules = test_features.FeatureTests().variant(tmp, source.replace(
                    '#include <stdio.h>', '#include <stdio.h>\n#undef ' + undefine, 1))
                self.session(mode, modules)
