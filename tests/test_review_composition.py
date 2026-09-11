"""Components share selection/theme while the application owns input and layout."""
import unittest
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
                    s.finish()
                finally:
                    s.close()
