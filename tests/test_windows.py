"""Independent window geometry, retained state and resize failure isolation."""
import tempfile
import unittest
import test_features
from test_drawing import drawing_session

ROOT = test_features.ROOT


class WindowTests(unittest.TestCase):
    def test_window_geometry(self):
        features = test_features.FeatureTests().run_shell(
            'zmodload zdraw || exit 1; print -rl -- "${zdraw_features[@]}"')
        env = {'ZDRAW_TEST_NATIVE_EDGES': '1' if 'norefresh_events' in features.splitlines() else '0'}
        drawing_session(self, 'wide', env=env, fixture='windows.zsh', marker=b'WINDOWS PASS')

    def test_optional_geometry_and_failures(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        for mode, definitions in (
            ('narrow', '#undef HAVE_WIN_WCH\n#undef HAVE_GETCCHAR\n#undef HAVE_SETCCHAR\n#undef HAVE_WADD_WCHNSTR'),
            ('unavailable_move', '#undef HAVE_MVWIN'),
            ('unavailable_resize', '#undef HAVE_WRESIZE'),
            ('unavailable_attrs', '#undef HAVE_WATTR_GET'),
            ('copy_failure', ''), ('resize_failure', ''), ('move_failure', ''),
            ('attrs_failure', ''), ('cursor_failure', ''), ('deletion_failure', ''),
            ('copy_limit', ''),
        ):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(
                    prefix=f'windows-{mode}-', dir=ROOT / '.build') as tmp:
                variant = source.replace('#include <stdio.h>', '#include <stdio.h>\n' + definitions, 1)
                replacements = {
                    'copy_failure': ('replacement = dupwin(w->win);', 'replacement = NULL;'),
                    # Mutate the private copy before failing, to check isolation.
                    'resize_failure': ('wresize(replacement, rows, cols) == ERR', '(wresize(replacement, rows, cols), 1)'),
                    'move_failure': ('mvwin(replacement, row, col) == ERR', '(mvwin(replacement, row, col), 1)'),
                    'attrs_failure': ('wattr_set(replacement, attrs, pair, NULL) == ERR', '1'),
                    'cursor_failure': ('wmove(replacement, y, x) == ERR', '1'),
                    'deletion_failure': ('if (delwin(w->win) == ERR) {', 'if (1) {'),
                    'copy_limit': ('#define ZDRAW_RESIZE_CELLS 262144', '#define ZDRAW_RESIZE_CELLS 8'),
                }
                if mode in replacements:
                    variant = variant.replace(*replacements[mode], 1)
                modules = test_features.FeatureTests().variant(tmp, variant)
                drawing_session(self, mode, modules, fixture='windows.zsh', marker=b'WINDOWS PASS')


if __name__ == '__main__':
    unittest.main(verbosity=2)
