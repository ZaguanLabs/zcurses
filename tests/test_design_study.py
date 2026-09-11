"""Designs retain real navigation, readable states and terminal cleanup."""
import os
import termios
import unittest

from test_compositions import RecipeSession


class DesignStudyTests(unittest.TestCase):
    def screen(self, frame):
        return bytes.fromhex(frame[-1]).decode('utf-8')

    def finish(self, session):
        self.assertEqual(session.advance(b'q'), ['done'])
        self.assertEqual(termios.tcgetattr(session.terminal), session.baseline)
        _, result = os.waitpid(session.pid, 0)
        session.reaped = True
        self.assertEqual(os.waitstatus_to_exitcode(result), 0, bytes(session.output[-4000:]))

    def test_designs_states_navigation_and_resize(self):
        for design in ('quiet', 'workbench', 'expressive'):
            with self.subTest(design=design):
                session = RecipeSession(self, design, fixture='design-study.zsh')
                try:
                    first = session.advance()
                    self.assertEqual(first[3:7], [design, 'ready', 'list', '1'])
                    wide = session.advance(size=(32, 120))
                    self.assertIn('Keep pasted text in the draft', self.screen(wide))
                    self.assertIn('REVIEW NOTES', self.screen(wide))
                    self.assertIn('Simulated', self.screen(wide))
                    self.assertEqual(wide[9], 'triple' if design == 'workbench' else 'split')
                    self.assertEqual(session.advance(b'j')[6], '2')
                    for key, name in ((b'1', 'quiet'), (b'2', 'workbench'), (b'3', 'expressive')):
                        changed = session.advance(key)
                        self.assertEqual(changed[3], name)
                        self.assertEqual(changed[6], '2')
                    narrow = session.advance(size=(18, 44))
                    self.assertEqual(narrow[9], 'single')
                    self.assertNotIn('REVIEW NOTES', self.screen(narrow))
                    detail = session.advance(b'\t')
                    self.assertEqual(detail[5], 'detail')
                    self.assertIn('REVIEW NOTES', self.screen(detail))
                    self.assertGreater(int(session.advance(b'\x1b[6~')[8]), 0)
                    self.assertEqual(session.advance(b'\x1b')[5], 'list')
                    last = session.advance(b'\x1bOF')
                    self.assertEqual(last[6], '9')
                    self.assertGreater(int(last[7]), 1)  # Actual list viewport scrolled.
                    long_title = session.advance(b'\t')
                    self.assertIn('deliberately long', self.screen(long_title))
                    self.assertIn('complete meaning', self.screen(long_title))
                    self.assertEqual(session.advance(size=(4, 12))[9], 'tiny')
                    restored = session.advance(size=(32, 120))
                    self.assertEqual(restored[6], '9')
                    empty = session.advance(b's')
                    self.assertEqual(empty[4], 'empty')
                    self.assertEqual(empty[6], '0')
                    self.assertIn('No changes.', self.screen(empty))
                    self.assertIn('next change', self.screen(empty))
                    busy = session.advance(b's')
                    self.assertEqual(busy[4], 'busy')
                    self.assertEqual(busy[6], '9')
                    self.assertIn('60%', self.screen(busy))
                    failed = session.advance(b's')
                    self.assertEqual(failed[4], 'error')
                    self.assertIn('could not be read', self.screen(failed))
                    self.assertIn('r to retry', self.screen(failed))
                    self.assertEqual(session.advance(b'r')[4], 'busy')
                    self.assertEqual(session.advance(b' ')[11], '4')
                    self.assertEqual(session.advance(b' ')[4], 'ready')
                    self.assertEqual(session.advance(b'm')[10], 'mono')
                    self.finish(session)
                finally:
                    session.close()

    def test_low_color_and_ascii(self):
        for variant, profile in (('mono', 'mono'), ('basic', '16'), ('vt100', 'mono')):
            with self.subTest(variant=variant):
                session = RecipeSession(self, variant, fixture='design-study.zsh',
                                        term='vt100' if variant == 'vt100' else 'xterm-256color')
                try:
                    frame = session.advance()
                    self.assertEqual(frame[10], profile)
                    wide = session.advance(size=(24, 100))
                    text = self.screen(wide)
                    self.assertTrue(text.isascii())
                    self.assertIn('> Paste stays', text)
                    self.assertIn('REVIEW NOTES', text)
                    self.finish(session)
                finally:
                    session.close()
