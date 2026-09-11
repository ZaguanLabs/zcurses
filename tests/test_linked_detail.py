"""A reusable treatment retains navigation, theme choice and terminal ownership."""
import os
import termios
import unittest

from test_compositions import RecipeSession
from test_drawing import drawing_session


class LinkedDetailTests(unittest.TestCase):
    def test_component_contract(self):
        drawing_session(self, 'wide', fixture='ui-linked-detail.zsh', marker=b'LINKED DETAIL PASS')

    def screen(self, frame):
        return bytes.fromhex(frame[-1]).decode('utf-8')

    def finish(self, session):
        self.assertEqual(session.advance(b'q'), ['done'])
        self.assertEqual(termios.tcgetattr(session.terminal), session.baseline)
        _, result = os.waitpid(session.pid, 0)
        session.reaped = True
        self.assertEqual(os.waitstatus_to_exitcode(result), 0, bytes(session.output[-4000:]))

    def test_navigation_resize_reuse_and_empty(self):
        session = RecipeSession(self, 'dark', fixture='linked-detail.zsh')
        try:
            frame = session.advance()
            self.assertEqual(frame[3:7], ['list', '3', '1', 'split'])
            self.assertIn('Terminal cleanup', self.screen(frame))
            self.assertIn('READING ROOM', self.screen(frame))
            compact = session.advance(b'g')
            self.assertEqual(compact[4], '3')
            self.assertIn('gap 0', self.screen(compact))
            self.assertIn('Theme inheritance', self.screen(compact))
            session.advance(b'g')
            self.assertEqual(session.advance(b'j')[4], '4')
            last = session.advance(b'\x1bOF')
            self.assertEqual(last[4], '6')
            self.assertGreater(int(last[5]), 1)
            self.assertEqual(session.advance(b't')[7], 'light')
            self.assertEqual(session.advance(b'v')[11], '1')
            catalog = session.advance(b'd')
            self.assertEqual(catalog[9], 'catalog')
            self.assertIn('Open questions', self.screen(catalog))
            narrow = session.advance(size=(13, 38))
            self.assertEqual(narrow[6], 'single')
            self.assertNotIn('READING ROOM', self.screen(narrow))
            detail = session.advance(b'\t')
            self.assertEqual(detail[3], 'detail')
            self.assertIn('READING ROOM', self.screen(detail))
            self.assertGreater(int(session.advance(b'\x1b[6~')[12]), 1)
            empty = session.advance(b'e')
            self.assertEqual(empty[4], '0')
            self.assertIn('Nothing selected', self.screen(empty))
            self.assertIn('No items', self.screen(session.advance(b'\x1b')))
            self.assertEqual(session.advance(b'e')[4], '1')
            self.assertEqual(session.advance(size=(4, 12))[6], 'tiny')
            self.assertEqual(session.advance(size=(32, 120))[6], 'split')
            self.finish(session)
        finally:
            session.close()

    def test_color_fallbacks(self):
        for variant, term in (('mono', 'xterm-256color'), ('16', 'xterm-256color'), ('auto', 'vt100'), ('forced', 'vt100')):
            with self.subTest(variant=variant):
                session = RecipeSession(self, variant, fixture='linked-detail.zsh', term=term)
                try:
                    frame = session.advance()
                    self.assertEqual(frame[8], 'mono' if variant in ('auto', 'forced') else variant)
                    if variant != 'auto':
                        self.assertTrue(self.screen(frame).isascii())
                        self.assertIn('> Terminal', self.screen(frame))
                    self.finish(session)
                finally:
                    session.close()
