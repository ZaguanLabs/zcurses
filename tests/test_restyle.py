"""Attribute replacement with text/cursor preservation and optional support."""
import tempfile
import unittest
import test_features
from test_drawing import drawing_session

ROOT = test_features.ROOT


class RestyleTests(unittest.TestCase):
    def test_region_restyle(self):
        features = test_features.FeatureTests().run_shell(
            'zmodload zdraw || exit 1; print -rl -- "${zdraw_features[@]}"')
        env = {'ZDRAW_TEST_NATIVE_EDGES': '1' if 'norefresh_events' in features.splitlines() else '0'}
        output = drawing_session(self, 'wide', env=env, fixture='restyle.zsh', marker=b'RESTYLE PASS')
        self.assertNotIn(b'ABCDEFGHI', output, 'restyle must not present pending text')

    def test_optional_restyle_and_failures(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        for mode, definitions in (
            ('narrow', '#undef HAVE_WIN_WCH\n#undef HAVE_GETCCHAR\n#undef HAVE_SETCCHAR\n#undef HAVE_WADD_WCHNSTR'),
            ('no_array_writers', '#undef HAVE_WADD_WCHNSTR\n#undef HAVE_WADDCHNSTR'),
            ('unavailable', '#undef HAVE_WCHGAT'),
            ('packed_pairs', '#undef NCURSES_EXT_COLORS'),
            ('allocation_failure', '#define init_pair(p, f, b) ((p) == 3 ? ERR : init_pair(p, f, b))'),
            ('write_failure', 'static int restyle_calls;\n#define wchgat(w, n, a, p, o) (++restyle_calls == 2 ? ERR : wchgat(w, n, a, p, o))'),
            ('move_failure', ''),
        ):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(
                    prefix=f'restyle-{mode}-', dir=ROOT / '.build') as tmp:
                variant = source.replace('#include <stdio.h>', '#include <stdio.h>\n' + definitions, 1)
                if mode == 'move_failure':
                    variant = variant.replace('wmove(win, row + i, col) == ERR', '(i == 1 || wmove(win, row + i, col) == ERR)', 1)
                modules = test_features.FeatureTests().variant(tmp, variant)
                drawing_session(self, mode, modules, fixture='restyle.zsh', marker=b'RESTYLE PASS')


if __name__ == '__main__':
    unittest.main(verbosity=2)
