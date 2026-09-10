"""Synchronized frames preserve explicit boundaries, fallback and cleanup."""
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
BEGIN, END = b'\x1b[?2026h', b'\x1b[?2026l'


class SyncTests(unittest.TestCase):
    def session(self, mode='native', modules=None):
        cr, cw = os.pipe()
        rr, rw = os.pipe()
        pid, terminal = pty.fork()
        if pid == 0:
            os.close(cw); os.close(rr)
            os.set_inheritable(cr, True); os.set_inheritable(rw, True)
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
            os.environ.update(TERM='xterm-256color', LC_ALL='C')
            os.environ.pop('LINES', None); os.environ.pop('COLUMNS', None)
            os.execl(ZSH, ZSH, '-df', str(ROOT / 'tests/sync.zsh'),
                     str(modules or ROOT / '.build/modules'), mode, str(rw), str(cr))
        os.close(cr); os.close(rw)
        pending, screen = bytearray(), bytearray()
        reaped, original, offset = False, None, 0

        def drain():
            try:
                screen.extend(os.read(terminal, 65536))
            except OSError as exc:
                if exc.errno != errno.EIO: raise

        try:
            while True:
                deadline = time.monotonic() + 10
                while b'\n' not in pending:
                    remaining = deadline - time.monotonic()
                    self.assertGreater(remaining, 0, bytes(screen[-4000:]))
                    for fd in select.select([terminal, rr], [], [], remaining)[0]:
                        if fd == terminal: drain()
                        else:
                            data = os.read(rr, 4096)
                            self.assertTrue(data, bytes(screen[-4000:]))
                            pending.extend(data)
                step, _, rest = pending.partition(b'\n'); pending[:] = rest
                while select.select([terminal], [], [], 0)[0]:
                    # EOF remains readable after the child exits.
                    before = len(screen); drain()
                    if len(screen) == before: break
                chunk = bytes(screen[offset:]); offset = len(screen)
                if step == b'done': break
                if step == b'baseline': original = termios.tcgetattr(terminal)
                elif step == b'query':
                    report = mode[-1] if mode.startswith('report') else '2'
                    os.write(terminal, b'\x1b[?2026;' + report.encode() + b'$y')
                elif step == b'staged': self.assertNotIn(b'HIDDENFRAME', screen)
                elif step == b'pending-reset':
                    self.assertIn(BEGIN, chunk)
                    self.assertIn(b'HIDDENFRAME', chunk)
                    self.assertNotIn(END, chunk)
                elif step == b'recovered':
                    self.assertNotIn(BEGIN, chunk)
                    self.assertEqual(chunk.count(END), 1, chunk)
                elif step in (b'framed', b'empty', b'retained', b'failed'):
                    self.assertEqual(chunk.count(BEGIN), 1, chunk)
                    self.assertEqual(chunk.count(END), 1, chunk)
                    self.assertLess(chunk.index(BEGIN), chunk.index(END), chunk)
                    marker = {b'framed': b'HIDDENFRAME', b'retained': b'RETAINEDFRAME',
                              b'failed': b'FAILED_UPDATE'}.get(bytes(step))
                    if marker:
                        self.assertIn(marker, chunk[chunk.index(BEGIN):chunk.index(END)])
                    if mode == 'signal':
                        self.assertGreater(chunk.index(b'TRAP_AFTER_FRAME'), chunk.index(END), chunk)
                elif step == b'suspended': self.assertEqual(termios.tcgetattr(terminal), original)
                elif step == b'fallback': self.assertIn(b'FALLBACKFRAME', chunk)
                elif step == b'legacy': self.assertIn(b'LEGACYFRAME', chunk)
                elif step not in (b'ready', b'resumed'): self.fail(step)
                if step not in (b'framed', b'empty', b'retained', b'failed', b'pending-reset', b'recovered'):
                    self.assertNotIn(BEGIN, chunk)
                    self.assertNotIn(END, chunk)
                os.write(cw, b'continue\n')
            _, status = os.waitpid(pid, 0); reaped = True
            self.assertEqual(os.waitstatus_to_exitcode(status), 0, bytes(screen[-4000:]))
            self.assertEqual(termios.tcgetattr(terminal), original)
            self.assertEqual(screen.count(BEGIN), screen.count(END))
        finally:
            if not reaped:
                os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0)
            for fd in (cw, rr, terminal): os.close(fd)

    def test_frame_lifecycle_and_evidence(self):
        for mode in ('native', 'report0', 'report1', 'report3', 'report4'):
            with self.subTest(mode=mode): self.session(mode)

    def test_optional_and_interrupted_updates(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        variants = {
            'unavailable': source.replace('#include <stdio.h>', '#include <stdio.h>\n#undef HAVE_CLOCK_GETTIME', 1),
            'failure': source.replace('result = doupdate() == ERR;', 'result = (fputs("FAILED_UPDATE", stdout), ERR) == ERR;', 1),
            'nested': source.replace('result = doupdate() == ERR;', 'result = zccmd_present(NULL, NULL) != 1 || doupdate() == ERR;', 1),
            'signal': source.replace('result = doupdate() == ERR;', 'result = (kill(getpid(), SIGINT), doupdate()) == ERR;', 1),
        }
        for mode in ('reset-off', 'reset-suspend', 'reset-unload'):
            variants[mode] = source.replace('    if (zdraw_sync_applied) {',
                '    static int injected_reset_failure;\n'
                '    if (zdraw_sync_applied) {\n'
                '        if (!injected_reset_failure++) return 1;', 1)
        for mode, variant in variants.items():
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(prefix='sync-', dir=ROOT / '.build') as tmp:
                modules = test_features.FeatureTests().variant(tmp, variant)
                self.session(mode, modules)
