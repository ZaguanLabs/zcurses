"""Pad lifecycle, budgets, composition and explicit presentation."""
import tempfile
import unittest
import test_features
from test_drawing import drawing_session

ROOT = test_features.ROOT


class PadTests(unittest.TestCase):
    def test_retained_pad(self):
        drawing_session(self, 'wide', fixture='pads.zsh', marker=b'PADS PASS')

    def test_optional_pads_and_failures(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        for mode, definitions in (
            ('narrow', '#undef HAVE_WIN_WCH\n#undef HAVE_GETCCHAR\n#undef HAVE_SETCCHAR\n#undef HAVE_WADD_WCHNSTR'),
            ('unavailable_pad', '#undef HAVE_NEWPAD'),
            ('unavailable_viewport', '#undef HAVE_PNOUTREFRESH'),
            ('allocation_failure', '#define newpad(r, c) ((WINDOW *)0)'),
            ('budgets', ''), ('deletion_failure', ''), ('touch_failure', ''),
            ('viewport_failure', '#define pnoutrefresh(p, pr, pc, sr, sc, er, ec) ERR'),
            ('stage_failure', ''),
            ('present_failure', '#define doupdate() ERR'),
            ('virtual_screen', ''),
        ):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(
                    prefix=f'pads-{mode}-', dir=ROOT / '.build') as tmp:
                variant = source.replace('#include <stdio.h>', '#include <stdio.h>\n' + definitions, 1)
                if mode in ('budgets', 'deletion_failure'):
                    variant = variant.replace('#define ZDRAW_PAD_CELLS 262144', '#define ZDRAW_PAD_CELLS 16').replace(
                        '#define ZDRAW_PAD_TOTAL_CELLS 1048576', '#define ZDRAW_PAD_TOTAL_CELLS 32').replace(
                        '#define ZDRAW_PAD_DIMENSION 32767', '#define ZDRAW_PAD_DIMENSION 12')
                if mode == 'deletion_failure':
                    variant = variant.replace('if (delwin(w->win)!=OK) {', 'if ((w->flags & ZCWF_PAD) || delwin(w->win)!=OK) {', 1)
                elif mode == 'touch_failure':
                    variant = variant.replace('touchline(w->win, pr, rows) == ERR', '1', 1)
                elif mode == 'stage_failure':
                    variant = variant.replace('touchwin(w->win) == ERR || wnoutrefresh(w->win) == ERR', '1', 1)
                elif mode == 'virtual_screen':
                    offset = variant.index('zccmd_snapshot(')
                    variant = variant[:offset] + variant[offset:].replace(
                        'win = ((ZCWin)getdata(node))->win;',
                        'win = !strcmp(args[0], "vscreen") ? newscr : ((ZCWin)getdata(node))->win;', 1)
                modules = test_features.FeatureTests().variant(tmp, variant)
                drawing_session(self, mode, modules, fixture='pads.zsh', marker=b'PADS PASS')


if __name__ == '__main__':
    unittest.main(verbosity=2)
