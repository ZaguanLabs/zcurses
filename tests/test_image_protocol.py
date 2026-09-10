"""Check native placeholder storage and owned protocol cleanup in a PTY.

Visual support is measured separately by the optional private-terminal matrix.
"""
import errno
import fcntl
import importlib.util
import os
import pty
import select
import signal
import struct
import tempfile
import termios
import time
import unittest
from pathlib import Path

import test_features

SPEC = importlib.util.spec_from_file_location('image_matrix', test_features.ROOT / 'scripts/portability/image-matrix.py')
matrix = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(matrix)


class ImageProtocolTests(unittest.TestCase):
    def probe(self, interrupt=False):
        with tempfile.TemporaryDirectory(prefix='image-probe-test-', dir=test_features.ROOT / '.build') as directory:
            root = Path(directory).resolve()
            matrix.setup(root)
            ack = os.open(root / 'ack', os.O_RDWR | os.O_NONBLOCK)
            go_r, go_w = os.pipe()
            pid, terminal = pty.fork()
            if not pid:
                os.close(go_w)
                os.read(go_r, 1)
                os.close(go_r)
                fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
                os.environ.update(TERM='xterm-256color', LC_ALL='C.UTF-8', NO_COLOR='')
                os.execl(test_features.ZSH, test_features.ZSH, '-df',
                         str(test_features.ROOT / 'scripts/portability/image-source.zsh'), str(root))
            os.close(go_r)
            baseline = termios.tcgetattr(terminal)
            os.write(go_w, b'x')
            os.close(go_w)
            output, phases = bytearray(), set()
            reaped = False
            try:
                deadline = time.monotonic() + 15
                while True:
                    self.assertLess(time.monotonic(), deadline, bytes(output[-2000:]))
                    if select.select([terminal], [], [], .01)[0]:
                        try:
                            output.extend(os.read(terminal, 65536))
                        except OSError as error:
                            if error.errno != errno.EIO:
                                raise
                    phase = (root / 'phase').read_text().strip() if (root / 'phase').exists() else ''
                    if phase and phase not in phases:
                        phases.add(phase)
                        if phase == 'before-resize':
                            fcntl.ioctl(terminal, termios.TIOCSWINSZ, struct.pack('HHHH', 20, 60, 0, 0))
                        if interrupt:
                            os.kill(pid, signal.SIGTERM)
                        os.write(ack, b'x')
                    done, status = os.waitpid(pid, os.WNOHANG)
                    if done:
                        reaped = True
                        break
                self.assertEqual(os.waitstatus_to_exitcode(status), 143 if interrupt else 0,
                                 (root / 'error').read_text() + repr(bytes(output[-2000:])))
                self.assertEqual(termios.tcgetattr(terminal), baseline)
                self.assertIn((root / 'delete').read_bytes(), output)
                self.assertNotIn(b'a=d,d=A', output)
                if not interrupt:
                    self.assertEqual(phases, matrix.PHASES)
                    self.assertIn('full_coordinate_roundtrip=1', (root / 'storage').read_text())
                    sequence = b''.join((root / name).read_bytes() for name in ('interrupted', 'abort', 'delete'))
                    self.assertIn(sequence, output)
                    self.assertTrue((root / 'done').exists())
            finally:
                if not reaped:
                    os.kill(pid, signal.SIGKILL)
                    os.waitpid(pid, 0)
                os.close(terminal)
                os.close(ack)

    def test_lifecycle_and_interrupted_transmission(self):
        self.probe()

    def test_signal_cleanup(self):
        self.probe(interrupt=True)
