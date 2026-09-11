"""Readable row identity survives theme changes, pan, scroll and terminal resize."""
import os
import termios
import unittest
from test_compositions import RecipeSession
from test_drawing import drawing_session


class ChangeGutterTests(unittest.TestCase):
    def test_component_contract(self):
        drawing_session(self, 'wide', fixture='ui-change-gutter.zsh', marker=b'CHANGE GUTTER PASS')

    def screen(self, frame):
        return bytes.fromhex(frame[-1]).decode('utf-8')

    def finish(self, session):
        self.assertEqual(session.advance(b'q'), ['done'])
        self.assertEqual(termios.tcgetattr(session.terminal), session.baseline)
        _, result = os.waitpid(session.pid, 0)
        session.reaped = True
        self.assertEqual(os.waitstatus_to_exitcode(result), 0, bytes(session.output[-4000:]))

    def test_navigation_and_resize(self):
        s = RecipeSession(self, 'dark', fixture='change-gutter.zsh')
        try:
            f = s.advance()
            self.assertEqual(f[3:6], ['1', '0', 'both'])
            self.assertIn('43     -', self.screen(f))
            self.assertIn('43 +', self.screen(f))
            self.assertEqual(s.advance(b'j')[3], '2')
            self.assertEqual(s.advance(b'l')[4], '4')
            self.assertEqual(s.advance(b't')[6], 'light')
            self.assertEqual(s.advance(b'v')[9], '1')
            f = s.advance(size=(16, 38))
            self.assertEqual(f[5], 'single')
            self.assertIn('43 -', self.screen(f))
            self.assertEqual(s.advance(b'0')[4], '0')
            f = s.advance(b'\x1bOF')
            self.assertGreater(int(f[3]), 1)
            self.assertIn('A paste remains', self.screen(f))
            f = s.advance(b'e')
            self.assertIn('No changes', self.screen(f))
            self.assertIn('0 changes', self.screen(f))
            self.assertNotIn('Row 1/0', self.screen(f))
            self.assertEqual(s.advance(b'e')[3], '1')
            self.assertEqual(s.advance(size=(4, 12))[5], 'tiny')
            self.assertEqual(s.advance(size=(32, 120))[5], 'both')
            self.finish(s)
        finally:
            s.close()

    def test_fallbacks(self):
        for variant, term in (('mono', 'xterm-256color'), ('16', 'xterm-256color'), ('forced', 'vt100')):
            with self.subTest(variant=variant):
                s = RecipeSession(self, variant, fixture='change-gutter.zsh', term=term)
                try:
                    f = s.advance()
                    self.assertEqual(f[7], '16' if variant == '16' else 'mono')
                    self.assertTrue(self.screen(f).isascii())
                    self.assertIn('43     - |', self.screen(f))
                    self.assertIn('43 + |', self.screen(f))
                    self.finish(s)
                finally:
                    s.close()
