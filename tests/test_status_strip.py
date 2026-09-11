"""Status words survive narrow layouts, unknown totals and theme changes."""
import os
import termios
import unittest
from test_compositions import RecipeSession
from test_drawing import drawing_session


class StatusStripTests(unittest.TestCase):
    def test_component_contract(self):
        drawing_session(self, 'wide', fixture='ui-status-strip.zsh', marker=b'STATUS STRIP PASS')

    def screen(self, frame):
        return bytes.fromhex(frame[-1]).decode('utf-8')

    def finish(self, session):
        self.assertEqual(session.advance(b'q'), ['done'])
        self.assertEqual(termios.tcgetattr(session.terminal), session.baseline)
        _, result = os.waitpid(session.pid, 0)
        session.reaped = True
        self.assertEqual(os.waitstatus_to_exitcode(result), 0, bytes(session.output[-4000:]))

    def test_states_progress_and_resize(self):
        s = RecipeSession(self, 'dark', fixture='status-strip.zsh')
        try:
            f = s.advance()
            self.assertEqual(f[3:7], ['working', '7', '1', 'detail'])
            for word in ('Working', 'Waiting', 'Done', 'Failed', '58%'):
                self.assertIn(word, self.screen(f))
            self.assertNotIn('%', self.screen(s.advance(b'p')))
            self.assertEqual(s.advance(b'2')[3], 'waiting')
            self.assertEqual(s.advance(b' ')[4], '7')  # Waiting owns no advancing work.
            self.assertEqual(s.advance(b'4')[3], 'failed')
            self.assertEqual(s.advance(b' ')[4], '7')
            self.assertEqual(s.advance(b'3')[3], 'done')
            self.assertNotIn('%', self.screen(s.advance(b't')))
            self.assertIn('100%', self.screen(s.advance(b'p')))
            self.assertEqual(s.advance(b'v')[9], '1')
            f = s.advance(size=(16, 38))
            self.assertEqual(f[6], 'compact')
            self.assertIn('! Failed', self.screen(f))
            self.assertEqual(s.advance(size=(4, 12))[6], 'tiny')
            self.assertEqual(s.advance(size=(24, 100))[6], 'detail')
            self.assertEqual(s.advance(b'c')[6], 'compact')
            s.advance(b'1')
            for _ in range(5):
                f = s.advance(b' ')
            self.assertEqual(f[3:5], ['done', '12'])
            self.finish(s)
        finally:
            s.close()

    def test_fallbacks(self):
        for variant, term in (('mono', 'xterm-256color'), ('16', 'xterm-256color'), ('forced', 'vt100')):
            with self.subTest(variant=variant):
                s = RecipeSession(self, variant, fixture='status-strip.zsh', term=term)
                try:
                    f = s.advance()
                    self.assertEqual(f[8], '16' if variant == '16' else 'mono')
                    self.assertTrue(self.screen(f).isascii())
                    for word in ('* Working', '? Waiting', '+ Done', '! Failed'):
                        self.assertIn(word, self.screen(f))
                    self.finish(s)
                finally:
                    s.close()
