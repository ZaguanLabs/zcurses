"""Real recipe input, resize, submission and terminal cleanup through a PTY."""
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


class RecipeSession:
    def __init__(self, case, example):
        self.case = case
        self.control_r, self.control = os.pipe()
        self.report, report_w = os.pipe()
        self.pid, self.terminal = pty.fork()
        if self.pid == 0:
            os.close(self.control)
            os.close(self.report)
            os.set_inheritable(self.control_r, True)
            os.set_inheritable(report_w, True)
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
            os.environ.update(TERM='xterm-256color', LC_ALL='C.UTF-8')
            for name in ('LINES', 'COLUMNS', 'NO_COLOR'):
                os.environ.pop(name, None)
            os.execl(test_features.ZSH, test_features.ZSH, '-df',
                     str(test_features.ROOT / 'tests/composition.zsh'),
                     str(report_w), str(self.control_r), example)
        os.close(self.control_r)
        os.close(report_w)
        self.pending = bytearray()
        self.output = bytearray()
        self.reaped = False
        self.case.assertEqual(self.read(), ['baseline'])
        self.baseline = termios.tcgetattr(self.terminal)

    def read(self):
        deadline = time.monotonic() + 10
        watched = [self.terminal, self.report]
        while b'\n' not in self.pending:
            remaining = deadline - time.monotonic()
            self.case.assertGreater(remaining, 0, bytes(self.output[-4000:]))
            for fd in select.select(watched, [], [], remaining)[0]:
                try:
                    data = os.read(fd, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    data = b''
                if fd == self.terminal and not data:
                    watched.remove(fd)
                    continue
                self.case.assertTrue(data, bytes(self.output[-4000:]))
                (self.pending if fd == self.report else self.output).extend(data)
        line, _, rest = self.pending.partition(b'\n')
        self.pending[:] = rest
        return line.decode().split()

    def advance(self, key=b'', size=None):
        if key:
            os.write(self.terminal, key)
        if size:
            fcntl.ioctl(self.terminal, termios.TIOCSWINSZ, struct.pack('HHHH', *size, 0, 0))
            os.kill(self.pid, signal.SIGWINCH)
        os.write(self.control, b'continue\n')
        return self.read()

    def finish(self):
        self.case.assertEqual(self.advance(b'\x1b'), ['done'])
        self.case.assertEqual(termios.tcgetattr(self.terminal), self.baseline)
        _, result = os.waitpid(self.pid, 0)
        self.reaped = True
        self.case.assertEqual(os.waitstatus_to_exitcode(result), 0, bytes(self.output[-4000:]))

    def close(self):
        if not self.reaped:
            try:
                os.kill(self.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(self.pid, 0)
        for fd in (self.control, self.report, self.terminal):
            os.close(fd)


class CompositionTests(unittest.TestCase):
    def test_form_recipe(self):
        session = RecipeSession(self, 'form')
        try:
            self.assertEqual(session.advance(), ['frame', '24', '80', '1', '0', '0', '0', '0'])
            self.assertEqual(session.advance(b'\r')[6], '23')  # Required error.
            # Native streaming protocol, including a character split across chunks.
            self.assertEqual(session.advance(b'\x1b[200~')[-1], '1')
            self.assertEqual(session.advance(b'\xe7')[-1], '1')
            self.assertEqual(session.advance(b'\x95\x8c')[-1], '1')
            self.assertEqual(session.advance(b'\x1b[201~')[5:], ['1', '0', '0'])
            self.assertEqual(session.advance(b'\t')[3], '2')
            self.assertEqual(session.advance(b'\r')[4], '1')
            self.assertEqual(session.advance(size=(6, 20))[1:3], ['6', '20'])
            self.assertEqual(session.advance(size=(24, 80))[4], '1')
            session.finish()
        finally:
            session.close()

    def test_document_recipe(self):
        session = RecipeSession(self, 'document')
        try:
            initial = session.advance()
            self.assertEqual(initial[:4], ['frame', '24', '80', '1'])
            self.assertEqual(session.advance(b'n')[5], '4')  # First subheading.
            chapter = session.advance(b'2')
            self.assertEqual(chapter[5:7], ['10', '0'])
            narrow = session.advance(size=(24, 50))
            self.assertEqual(narrow[5:7], ['10', '0'])
            self.assertLess(int(narrow[4]), int(chapter[4]))
            self.assertEqual(session.advance(b't')[-1], 'light')
            self.assertEqual(session.advance(b'p')[5], '4')
            self.assertEqual(session.advance(size=(24, 110))[5], '4')
            self.assertEqual(session.advance(size=(6, 20))[1:3], ['6', '20'])
            self.assertEqual(session.advance(size=(24, 80))[5], '4')
            self.assertEqual(session.advance(b'1')[3], '1')
            session.finish()
        finally:
            session.close()

    def test_canvas_recipe(self):
        session = RecipeSession(self, 'canvas')
        try:
            initial = session.advance()
            self.assertEqual(initial[:9], ['frame', '24', '80', 'line', 'auto', '0', 'dark', '256', '32'])
            self.assertGreater(int(initial[9]), 33)
            ascii_frame = session.advance(b'g')
            self.assertEqual(ascii_frame[4], 'ascii')
            self.assertEqual(ascii_frame[9], initial[9])  # Marker selection doesn't change geometry.
            self.assertEqual(session.advance(b'g')[4], 'block')
            self.assertEqual(session.advance(b'p')[3], 'point')
            self.assertEqual(session.advance(b'm')[7], 'mono')
            self.assertEqual(session.advance(b't')[6], 'light')
            self.assertEqual(session.advance(b'e')[8:], ['0', '0'])
            self.assertEqual(session.advance(b'e')[8], '33')
            self.assertEqual(session.advance(size=(12, 32))[8], '33')
            self.assertEqual(session.advance(size=(6, 20))[1:3], ['6', '20'])
            self.assertEqual(session.advance(size=(24, 80))[8], '33')
            session.finish()
        finally:
            session.close()

    def test_capability_inspector(self):
        session = RecipeSession(self, 'capabilities')
        try:
            self.assertEqual(session.advance(), ['frame', '24', '80', '1', 'no', 'unknown', 'none', 'unknown', 'no'])
            self.assertEqual(session.advance(b'o')[5:7], ['yes', 'override'])
            self.assertEqual(session.advance(b'o')[5:7], ['no', 'override'])
            self.assertEqual(session.advance(b'o')[5:7], ['unknown', 'override'])
            self.assertEqual(session.advance(b'o')[5:7], ['unknown', 'none'])
            self.assertEqual(session.advance(b'p')[3:5], ['2', 'yes'])
            self.assertEqual(session.advance(b'\x1b[?2004;2$y')[7:], ['yes', 'no'])
            self.assertEqual(session.advance(size=(1, 20))[1:3], ['1', '20'])
            self.assertEqual(session.advance(size=(24, 80))[1:3], ['24', '80'])
            session.finish()
        finally:
            session.close()

    def test_enhanced_form_recipe(self):
        session = RecipeSession(self, 'form-enhanced')
        try:
            self.assertEqual(session.advance(), ['frame', '1', '1', '0', '0', 'focus_events', '0'])
            self.assertEqual(session.advance(b'\x1b[?1004;2$y')[-2:], ['keyboard_events', '0'])
            self.assertEqual(session.advance(b'\x1b[?0u')[-2:], ['done', '1'])
            self.assertEqual(session.advance(b'\x1b[97;1;97u')[4], '1')
            # Release must not insert a second character; the following focus event draws.
            self.assertEqual(session.advance(b'\x1b[97;1:3;97u\x1b[O')[1:5], ['0', '1', '0', '1'], bytes(session.output[-4000:]))
            self.assertEqual(session.advance(b'\x1b[I')[1], '1')
            self.assertEqual(session.advance(b'\x1b[115;6u')[3], '1')
            self.assertEqual(session.advance(b'\x1b[9u')[2], '2')
            self.assertEqual(session.advance(b'\x1b[9;2u')[2], '1')
            self.assertEqual(session.advance(b'\x1b[97;5u')[4], '1')
            self.assertEqual(session.advance(b'\x1b[127u')[4], '0')
            session.finish()
        finally:
            session.close()

    def test_enhanced_event_inspector(self):
        session = RecipeSession(self, 'events-enhanced')
        try:
            self.assertEqual(session.advance()[1], 'ready')
            self.assertEqual(session.advance(b'\x1b[?1004;2$y')[-2], 'keyboard_events')
            self.assertEqual(session.advance(b'\x1b[?0u')[-1], '1')
            self.assertEqual(session.advance(b'\x1b[97;5:3u')[1:4], ['key', 'kitty', 'release'])
            self.assertEqual(session.advance(b'\x1b[O')[1:3], ['focus', 'focus-report'])
            self.assertEqual(session.advance(b'\x1b[113;1;113u'), ['done'])
            _, status = os.waitpid(session.pid, 0)
            session.reaped = True
            self.assertEqual(os.waitstatus_to_exitcode(status), 0)
            self.assertEqual(termios.tcgetattr(session.terminal), session.baseline)
        finally:
            session.close()
