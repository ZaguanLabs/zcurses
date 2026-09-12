"""Region fill equivalence, preflight and partial writer failures."""
import tempfile
import unittest
import test_features
from test_drawing import drawing_session

ROOT = test_features.ROOT


class FillTests(unittest.TestCase):
    def test_region_fill(self):
        drawing_session(self, 'wide', fixture='fill.zsh', marker=b'FILL PASS')

    def test_optional_writers_and_failures(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        for mode, definitions in (
            ('narrow', '#undef HAVE_WADD_WCHNSTR'),
            ('unavailable', '#undef HAVE_WADD_WCHNSTR\n#undef HAVE_WADDCHNSTR'),
            ('allocation_failure', '#define init_pair(p, f, b) ((p) == 2 ? ERR : init_pair(p, f, b))'),
            ('write_failure', 'static int fill_writes;\n#define wadd_wchnstr(w, c, n) (++fill_writes == 2 ? ERR : wadd_wchnstr(w, c, n))'),
            ('move_failure', ''),
        ):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(
                    prefix=f'fill-{mode}-', dir=ROOT / '.build') as tmp:
                variant = source.replace('#include <stdio.h>', '#include <stdio.h>\n' + definitions, 1)
                if mode == 'move_failure':
                    needle = 'if (i && wmove(win, row + i, col) == ERR)'
                    self.assertEqual(variant.count(needle), 1)
                    variant = variant.replace(needle, 'if (i && (i == 1 || wmove(win, row + i, col) == ERR))', 1)
                modules = test_features.FeatureTests().variant(tmp, variant)
                drawing_session(self, mode, modules, fixture='fill.zsh', marker=b'FILL PASS')


if __name__ == '__main__':
    unittest.main(verbosity=2)
