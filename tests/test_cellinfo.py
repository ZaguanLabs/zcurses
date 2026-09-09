"""Complete complex-cell readback and cursor-preserving error paths."""
import tempfile
import unittest
import test_features
from test_drawing import drawing_session

ROOT = test_features.ROOT


class CellInfoTests(unittest.TestCase):
    def test_complete_cell_readback(self):
        drawing_session(self, 'wide', fixture='cellinfo.zsh', marker=b'CELLINFO PASS')

    def test_monochrome_readback(self):
        drawing_session(self, 'monochrome', env={'TERM': 'vt100'},
                        fixture='cellinfo.zsh', marker=b'CELLINFO PASS')

    def test_optional_readers_and_failures(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        for mode, definitions in (
            ('narrow', '#undef HAVE_WIN_WCH\n#undef HAVE_GETCCHAR\n#undef HAVE_SETCCHAR\n#undef HAVE_WADD_WCHNSTR'),
            ('read_failure', '#define win_wch(w, c) ((void)(w), (void)(c), ERR)'),
            ('count_failure', ''),
            ('uncached', ''),
            ('output_failure', '#define getcchar(c, w, a, p, o) ((w) ? ERR : getcchar(c, w, a, p, o))'),
            ('decode_failure', '#define wcstombs(s, w, n) ((size_t)-1)'),
        ):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(
                    prefix=f'cellinfo-{mode}-', dir=ROOT / '.build') as tmp:
                variant = source.replace('#include <stdio.h>', '#include <stdio.h>\n' + definitions, 1)
                # The count failure also prevents preparing cells with setcchar;
                # inject only at the query call, leaving drawing operational.
                if mode == 'count_failure':
                    variant = source.replace('count = getcchar(&cell, NULL, NULL, NULL, NULL);', 'count = ERR;', 1)
                if mode == 'uncached':
                    variant = source.replace('color = zdraw_colorget_reverse(pair);', 'color = NULL;', 1)
                modules = test_features.FeatureTests().variant(tmp, variant)
                drawing_session(self, mode, modules, fixture='cellinfo.zsh', marker=b'CELLINFO PASS')


if __name__ == '__main__':
    unittest.main(verbosity=2)
