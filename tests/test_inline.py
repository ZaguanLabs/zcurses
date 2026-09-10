"""Inline ZLE selection, async framing and restoration in an isolated shell."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import shlex
import signal
import struct
import tempfile
import termios
import time
import unittest

import test_features


class InlineSession:
    def __init__(self, case, async_source=False):
        self.case = case
        self.dotdir = tempfile.TemporaryDirectory(prefix='inline-', dir=test_features.ROOT / '.build')
        report_r, report_w = os.pipe()
        source_r, self.source = os.pipe()
        Path(self.dotdir.name, '.zshrc').write_text('source ' + shlex.quote(str(test_features.ROOT / 'tests/inline.zsh')) + '\n')
        self.pid, self.terminal = pty.fork()
        if not self.pid:
            os.close(report_r)
            os.close(self.source)
            os.set_inheritable(report_w, True)
            os.set_inheritable(source_r, True)
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
            os.environ.update(TERM='xterm-256color', LC_ALL='C.UTF-8', ZDOTDIR=self.dotdir.name,
                              ZDRAW_INLINE_ROOT=str(test_features.ROOT), ZDRAW_INLINE_REPORT=str(report_w),
                              ZDRAW_INLINE_SOURCE_FD=str(source_r) if async_source else '')
            os.execl(test_features.ZSH, test_features.ZSH, '-di')
        os.close(report_w)
        os.close(source_r)
        self.report = report_r
        self.pending = bytearray()
        self.output = bytearray()
        self.reaped = False
        self.case.assertEqual(self.read(), ['ready'])
        self.baseline = termios.tcgetattr(self.terminal)

    def read(self):
        deadline = time.monotonic() + 10
        watched = [self.report, self.terminal]
        while b'\n' not in self.pending:
            remaining = deadline - time.monotonic()
            self.case.assertGreater(remaining, 0, bytes(self.output[-4000:]))
            for fd in select.select(watched, [], [], remaining)[0]:
                try:
                    data = os.read(fd, 65536)
                except OSError as error:
                    if fd != self.terminal or error.errno != errno.EIO:
                        raise
                    data = b''
                if fd == self.terminal and not data:
                    watched.remove(fd)
                    continue
                self.case.assertTrue(data, bytes(self.output[-4000:]))
                (self.pending if fd == self.report else self.output).extend(data)
        line, _, rest = self.pending.partition(b'\n')
        self.pending[:] = rest
        packet = line.decode('ascii').split()
        if packet == ['clean']:
            self.case.assertEqual(termios.tcgetattr(self.terminal), self.baseline)
        return packet

    def send(self, data):
        os.write(self.terminal, data)
        return self.read()

    def finish(self):
        os.write(self.terminal, b'\x15exit\r')
        deadline = time.monotonic() + 5
        while True:
            pid, status = os.waitpid(self.pid, os.WNOHANG)
            if pid:
                self.reaped = True
                self.case.assertEqual(os.waitstatus_to_exitcode(status), 0)
                return
            self.case.assertLess(time.monotonic(), deadline)
            if select.select([self.terminal], [], [], 0.05)[0]:
                try:
                    self.output.extend(os.read(self.terminal, 65536))
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise

    def close(self):
        if not self.reaped:
            os.kill(self.pid, signal.SIGKILL)
            os.waitpid(self.pid, 0)
        for fd in (self.terminal, self.report, self.source):
            os.close(fd)
        self.dotdir.cleanup()


class InlineTests(unittest.TestCase):
    def test_disposable_launcher(self):
        root = test_features.ROOT
        before = set((root / '.build').glob('inline-shell.*'))
        pid, terminal = pty.fork()
        if not pid:
            os.environ.update(TERM='xterm-256color', LC_ALL='C.UTF-8')
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
            os.execl(test_features.ZSH, test_features.ZSH, '-df', str(root / 'scripts/inline-shell.zsh'))
        output = bytearray()
        reaped = False

        def until(marker):
            deadline = time.monotonic() + 10
            while marker not in output:
                remaining = deadline - time.monotonic()
                self.assertGreater(remaining, 0, bytes(output[-3000:]))
                self.assertTrue(select.select([terminal], [], [], remaining)[0], bytes(output[-3000:]))
                output.extend(os.read(terminal, 65536))
            output.clear()

        try:
            until(b'inline% ')
            os.write(terminal, b'print -r -- draft\x18\x09')
            until(b'Place the cursor after whitespace')
            os.write(terminal, b'\x15print -r -- \x18\x09')
            until(b'Enter select / Esc cancel')
            os.write(terminal, b'\r\r')
            until(b'local cache\r\n')
            os.write(terminal, b'exit 7\r')
            deadline = time.monotonic() + 10
            while True:
                done, status = os.waitpid(pid, os.WNOHANG)
                if done:
                    reaped = True
                    self.assertEqual(os.waitstatus_to_exitcode(status), 7)
                    break
                self.assertLess(time.monotonic(), deadline)
                if select.select([terminal], [], [], 0.05)[0]:
                    try:
                        output.extend(os.read(terminal, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
            self.assertEqual(set((root / '.build').glob('inline-shell.*')), before)
        finally:
            if not reaped:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(terminal)

    def test_selection_and_cancel_restore_editor(self):
        session = InlineSession(self)
        try:
            self.assertEqual(session.send(b'echo draft\x18\x09')[:3], ['frame', '1', '3'])
            self.assertEqual(session.send(b'\x0e')[:3], ['frame', '2', '3'])
            result = session.send(b'\r')
            self.assertEqual(result, ['result', '0', '$(not-executed)'.encode().hex(), 'echo draft'.encode().hex(), '10', 'main', 'inactive'])
            self.assertEqual(session.read(), ['clean'])
            self.assertEqual(session.send(b'\x18\x09')[0], 'frame')
            self.assertEqual(session.send(b'\x07')[1], '1')
            self.assertEqual(session.read(), ['clean'])
            self.assertEqual(session.send(b'\x15print -r -- editing-resumed\r'), ['ready'])
            session.finish()
            self.assertNotIn(b'\x1b[?1049h', session.output)
        finally:
            session.close()

    def test_fragmented_async_input_and_descriptor_cleanup(self):
        session = InlineSession(self, async_source=True)
        try:
            first = session.send(b'echo preserved\x18\x09')
            fd = int(first[3])
            self.assertGreaterEqual(fd, 3)
            os.write(session.source, b'item\tpartial')
            # An incomplete producer frame must not hold up keyboard navigation.
            self.assertEqual(session.send(b'\x0e')[1], '2')
            os.write(session.source, b' value\nitem\t\xe7')
            self.assertEqual(session.read()[2], '4')
            os.write(session.source, b'\x95\x8c\ndone\n')
            packet = session.read()
            self.assertEqual(packet[2:4], ['5', '-1'])
            self.assertIn('Source complete', bytes.fromhex(packet[4]).decode())
            self.assertEqual(session.send(b'\x07')[1], '1')
            self.assertEqual(session.read(), ['clean'])
            # The duplicate watcher is gone. A new request can reuse descriptors;
            # queued data belongs only to the newly registered generation.
            self.assertEqual(session.send(b'\x18\x09')[2], '3')
            os.write(session.source, b'item\tsecond request\ndone\n')
            self.assertEqual(session.read()[2:4], ['4', '-1'])
            self.assertEqual(session.send(b'\x1a')[1], '1')
            self.assertEqual(session.read(), ['clean'])
            self.assertEqual(session.send(b'\x15false; print -r -u "$ZDRAW_INLINE_REPORT" -- command:$?\r'), ['command:1'])
            self.assertEqual(session.read(), ['ready'])
            self.assertEqual(session.send(b'\x18\x09')[0], 'frame')
            self.assertEqual(session.send(b'\x07')[1], '1')
            self.assertEqual(session.read(), ['clean'])
            session.finish()
        finally:
            session.close()

    def test_resize_and_invalid_source(self):
        session = InlineSession(self, async_source=True)
        try:
            session.send(b'echo \xe7\x95\x8c\x18\x09')
            fcntl.ioctl(session.terminal, termios.TIOCSWINSZ, struct.pack('HHHH', 5, 20, 0, 0))
            os.kill(session.pid, signal.SIGWINCH)
            # ZLE handles immediate reflow; the next widget dispatch remeasures.
            frame = session.send(b'\x0e')
            self.assertEqual(frame[:3], ['frame', '2', '3'])
            for line in bytes.fromhex(frame[4]).decode().splitlines():
                self.assertLessEqual(len(line), 19)
            os.write(session.source, b'item\tbad\x1b[2J\n')
            packet = session.read()
            self.assertEqual(packet[2:4], ['3', '-1'])
            self.assertIn('Invalid source', bytes.fromhex(packet[4]).decode())
            result = session.send(b'\x07')
            self.assertEqual(result[3], 'echo 界'.encode().hex())
            self.assertEqual(session.read(), ['clean'])
            session.finish()
        finally:
            session.close()

    def test_stream_limits_and_eof(self):
        for payload, message in ((b'item\t' + b'x' * 257 + b'\n', 'Invalid source'),
                                 (b'x' * 16385, 'Source exceeded'),
                                 (b'item\textra\n' * 30, 'Invalid source'),
                                 (b'item\tpartial', 'Source closed')):
            with self.subTest(message=message):
                session = InlineSession(self, async_source=True)
                try:
                    session.send(b'\x18\x09')
                    os.write(session.source, payload)
                    os.close(session.source)
                    session.source = os.open(os.devnull, os.O_WRONLY)
                    while True:
                        frame = session.read()
                        if frame[3] == '-1':
                            break
                    self.assertIn(message, bytes.fromhex(frame[4]).decode())
                    self.assertEqual(session.send(b'\x07')[1], '1')
                    self.assertEqual(session.read(), ['clean'])
                    session.finish()
                finally:
                    session.close()

    def test_cancel_before_job_control(self):
        session = InlineSession(self)
        job_pid = None
        try:
            session.send(b'\x18\x09')
            self.assertEqual(session.send(b'\x1a')[1], '1')
            self.assertEqual(session.read(), ['clean'])
            # The ordinary shell owns the job after picker cleanup. The child
            # identifies itself, stops, then waits for a second stop in bg.
            script = ('module_path=("$ZDRAW_INLINE_ROOT/.build/modules"); zmodload zsh/system; '
                      'print -r -u "$ZDRAW_INLINE_REPORT" -- job:$sysparams[pid]; '
                      'kill -STOP $sysparams[pid]; '
                      'print -r -u "$ZDRAW_INLINE_REPORT" -- background; '
                      'kill -STOP $sysparams[pid]; '
                      'print -r -u "$ZDRAW_INLINE_REPORT" -- foreground')
            command = shlex.quote(test_features.ZSH) + ' -dfc ' + shlex.quote(script) + '\r'
            packet = session.send(command.encode())
            job_pid = int(packet[0].split(':')[1])
            self.assertEqual(session.read(), ['ready'])
            packets = [session.send(b'bg\r'), session.read()]
            self.assertEqual(sorted(packets), [['background'], ['ready']])
            # Wait until the shell observes the second stop before fg.
            deadline = time.monotonic() + 5
            while session.output.count(b'suspended (signal)') < 2:
                self.assertLess(time.monotonic(), deadline, bytes(session.output[-1500:]))
                if select.select([session.terminal], [], [], 0.05)[0]:
                    session.output.extend(os.read(session.terminal, 65536))
            self.assertEqual(session.send(b'fg\r'), ['foreground'])
            self.assertEqual(session.read(), ['ready'])
            job_pid = None
            self.assertEqual(session.send(b'echo resumed\x18\x09')[0], 'frame')
            self.assertEqual(session.send(b'\x07')[1], '1')
            self.assertEqual(session.read(), ['clean'])
            session.finish()
        finally:
            if job_pid:
                try:
                    os.kill(job_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            session.close()

    def test_existing_display_vi_mode_and_paste(self):
        session = InlineSession(self)
        try:
            self.assertEqual(session.send(b"INLINE_TEST_DECORATE=1; bindkey -v; bindkey -M viins '^X^I' inline-test-pick\r"), ['ready'])
            self.assertEqual(session.send(b'echo original\x18\x09')[0], 'frame')
            self.assertEqual(session.send(b'\x1b[200~not a command\n$(false)\x1b[201~')[:3], ['frame', '1', '3'])
            self.assertEqual(session.send(b'\x0e')[:3], ['frame', '2', '3'])
            result = session.send(b'\r')
            self.assertEqual(result[1], '0')
            self.assertEqual(result[3], 'echo original'.encode().hex())
            self.assertEqual(session.read(), ['clean'])
            session.finish()
        finally:
            session.close()
