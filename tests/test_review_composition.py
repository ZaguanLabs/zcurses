"""Components share selection/theme while the application owns input and layout."""
import unittest
import os
import termios
from test_compositions import RecipeSession


class ReviewCompositionTests(unittest.TestCase):
    def screen(self, frame):
        return bytes.fromhex(frame[-1]).decode('utf-8')

    def test_selection_layout_and_state(self):
        s = RecipeSession(self, 'dark', fixture='review-composition.zsh')
        try:
            f = s.advance()
            self.assertEqual(f[3:6], ['2', 'working', 'list'])
            self.assertIn('58%', self.screen(f))
            f = s.advance(b'j')
            self.assertEqual(f[3:5], ['3', 'failed'])
            self.assertIn('! Failed', self.screen(f))
            self.assertIn('draft+=', self.screen(f))
            f = s.advance(b'j')
            self.assertEqual(f[3:5], ['4', 'waiting'])
            self.assertNotIn('%', self.screen(f))
            for _ in range(3):
                f = s.advance(b'k')
            self.assertEqual(f[3:5], ['1', 'done'])
            self.assertIn('100%', self.screen(f))
            s.advance(b'j')
            s.advance(b'\t')
            f = s.advance(size=(14, 38))
            self.assertEqual(f[5], 'detail')
            self.assertEqual(f[8], 'single')
            f = s.advance(b'j')
            self.assertEqual(f[6], '2')
            f = s.advance(b'l')
            self.assertEqual(f[7], '4')
            f = s.advance(b't')
            self.assertEqual(f[3:8], ['2', 'working', 'detail', '2', '4'])
            self.assertEqual(f[9], 'light')
            self.assertEqual(s.advance(b'v')[11], '1')
            self.assertEqual(s.advance(size=(4, 12))[8], 'tiny')
            f = s.advance(size=(14, 38))
            self.assertEqual(f[3:8], ['2', 'working', 'detail', '2', '4'])
            s.advance(b'\t')
            f = s.advance(b'j')
            self.assertEqual(f[3:8], ['3', 'failed', 'list', '1', '0'])
            f = s.advance(size=(24, 100))
            self.assertEqual(f[8], 'split')
            self.assertIn('! Failed', self.screen(f))
            f = s.advance(b'e')
            self.assertEqual(f[3:5], ['0', 'empty'])
            self.assertIn('No changes to review', self.screen(f))
            self.assertNotIn('! Failed', self.screen(f))
            self.assertNotIn('draft+=', self.screen(f))
            f = s.advance(b'e')
            self.assertEqual(f[3:5], ['1', 'done'])
            s.finish()
        finally:
            s.close()

    def test_fallbacks(self):
        for variant, term in (('mono', 'xterm-256color'), ('16', 'xterm-256color'), ('forced', 'vt100')):
            with self.subTest(variant=variant):
                s = RecipeSession(self, variant, fixture='review-composition.zsh', term=term)
                try:
                    f = s.advance()
                    self.assertEqual(f[10], '16' if variant == '16' else 'mono')
                    self.assertTrue(self.screen(f).isascii())
                    self.assertIn('* Working', self.screen(f))
                    self.assertIn('! Failed', self.screen(s.advance(b'j')))
                    f = s.advance(b'c')
                    self.assertEqual(f[12:14], ['1', '0'])
                    self.assertTrue(self.screen(f).isascii())
                    self.assertIn('! Failed', self.screen(f))
                    self.assertIn('25%', self.screen(f))
                    s.finish()
                finally:
                    s.close()

    def test_density_recovers_rows_and_preserves_position(self):
        s = RecipeSession(self, 'compact', fixture='review-composition.zsh')
        try:
            f = s.advance()
            self.assertEqual(f[12:14], ['1', '0'])
            self.assertIn('58%', self.screen(f))
            self.assertNotIn('Checking terminal cleanup', self.screen(f))
            s.advance(b'c')  # Restore two rows when the terminal has enough height.
            s.advance(b'\t')
            f = s.advance(size=(18, 38))
            self.assertEqual(f[12:14], ['2', '1'])
            self.assertIn('Checking terminal cleanup', self.screen(f))
            f = s.advance(b'j')
            self.assertEqual(f[6], '2')
            f = s.advance(b'l')
            before = f
            f = s.advance(b'c')
            self.assertEqual(f[3:8], before[3:8])
            self.assertEqual(int(f[14]), int(before[14]) + 2)
            self.assertNotIn('Checking terminal cleanup', self.screen(f))
            self.assertEqual(s.advance(b'c')[12:14], ['2', '1'])
            f = s.advance(size=(11, 26))
            self.assertEqual(f[8], 'single')
            self.assertEqual(f[12:15], ['1', '0', '2'])
            self.assertIn('* Working', self.screen(f))
            self.assertIn('58%', self.screen(f))
            # A short terminal keeps compact status even with the preference off.
            s.advance(b'c')
            f = s.advance(b'c')
            self.assertEqual(f[12:14], ['1', '0'])
            self.assertEqual(s.advance(size=(10, 26))[8], 'tiny')
            f = s.advance(size=(18, 38))
            self.assertEqual(f[12:14], ['2', '1'])
            self.assertEqual(f[3:8], before[3:8])
            s.finish()
        finally:
            s.close()

    def test_key_reference_preserves_review_and_reaches_every_key(self):
        s = RecipeSession(self, 'dark', fixture='review-composition.zsh')
        try:
            s.advance()
            s.advance(b'\t')
            s.advance(size=(18, 38))
            s.advance(b'j')
            s.advance(b'l')
            before = s.advance(b't')
            f = s.advance(b'?')
            self.assertEqual(f[15], '1')
            self.assertIn('KEYS / review', self.screen(f))
            self.assertEqual(f[3:15], before[3:15])
            f = s.advance(size=(11, 26))
            seen = self.screen(f)
            for _ in range(5):
                f = s.advance(b'j')
                seen += self.screen(f)
                self.assertEqual(f[3:15], before[3:15])
            for word in ('Switch pane', 'Move file or row', 'Pan change text',
                         'Leftmost text', 'Compact status', 'Switch theme',
                         'Status emphasis', 'Monochrome', 'Empty sample',
                         'Quit review', 'Show these keys'):
                self.assertIn(word, seen)
            self.assertEqual(f[16], '6')
            self.assertEqual(s.advance(b'j')[16], '6')
            self.assertEqual(s.advance(b'\x1bOA')[16], '5')
            f = s.advance(size=(1, 12))
            self.assertEqual(f[15], '1')
            s.advance(size=(18, 38))
            f = s.advance(b'\x1b')
            self.assertEqual(f[15], '0')
            self.assertEqual(f[3:15], before[3:15])
            self.assertNotIn('KEYS / review', self.screen(f))
            s.advance(b'?')
            # Review controls are ignored while the reference owns input.
            f = s.advance(b'etc?')
            self.assertEqual(f[3:15], before[3:15])
            s.finish()
        finally:
            s.close()

    def test_quit_from_initial_key_reference(self):
        s = RecipeSession(self, 'keys', fixture='review-composition.zsh', term='vt100')
        try:
            f = s.advance()
            self.assertEqual(f[15], '1')
            self.assertEqual(f[10], 'mono')
            self.assertTrue(self.screen(f).isascii())
            self.assertIn('Show these keys', self.screen(f))
            self.assertEqual(s.advance(b'q'), ['done'])
            self.assertEqual(termios.tcgetattr(s.terminal), s.baseline)
            _, result = os.waitpid(s.pid, 0)
            s.reaped = True
            self.assertEqual(os.waitstatus_to_exitcode(result), 0)
        finally:
            s.close()
