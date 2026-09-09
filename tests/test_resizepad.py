"""Public pad resizing, preserved state, quotas and failure isolation."""
import tempfile
import unittest
import test_features
from test_drawing import drawing_session

ROOT = test_features.ROOT


def resize_variant(source, mode):
    start = source.index('zccmd_resizepad(')
    end = source.index('zccmd_viewport(', start)
    body = source[start:end]
    replacements = {
        'allocation_failure': ('replacement = newpad(oldrows, oldcols);', 'replacement = NULL;'),
        'copy_failure': ('oldrows - 1, oldcols - 1, 0) == ERR', 'oldrows - 1, oldcols - 1, 0) != ERR'),
        # Exercise mutation of the private surface before failure.
        'resize_failure': ('wresize(replacement, rows, cols) == ERR', '(wresize(replacement, rows, cols), 1)'),
        'attrs_failure': ('wattr_set(replacement, attrs, pair, NULL) == ERR', '1'),
        'cursor_failure': ('wmove(replacement, y, x) == ERR', '1'),
        'scroll_failure': ('scrollok(replacement, (w->flags & ZCWF_SCROLL) != 0) == ERR', '1'),
        'deletion_failure': ('if (delwin(w->win) == ERR) {', 'if (1) {'),
    }
    if mode in replacements:
        old, new = replacements[mode]
        assert body.count(old) == 1
        body = body.replace(old, new)
    source = source[:start] + body + source[end:]
    if mode == 'budgets':
        source = source.replace('#define ZDRAW_PAD_CELLS 262144', '#define ZDRAW_PAD_CELLS 16').replace(
            '#define ZDRAW_PAD_TOTAL_CELLS 1048576', '#define ZDRAW_PAD_TOTAL_CELLS 32').replace(
            '#define ZDRAW_PAD_DIMENSION 32767', '#define ZDRAW_PAD_DIMENSION 12')
    elif mode.endswith('_failure'):
        source = source.replace('#define ZDRAW_PAD_TOTAL_CELLS 1048576', '#define ZDRAW_PAD_TOTAL_CELLS 80')
    return source


class ResizePadTests(unittest.TestCase):
    def test_resize_pad(self):
        features = test_features.FeatureTests().run_shell(
            'zmodload zdraw || exit 1; print -rl -- "${zdraw_features[@]}"')
        env = {'ZDRAW_TEST_NATIVE_EDGES': '1' if 'norefresh_events' in features.splitlines() else '0'}
        drawing_session(self, 'wide', env=env, fixture='resizepad.zsh', marker=b'RESIZEPAD PASS')

    def test_optional_resize_and_failures(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        for mode, definitions in (
            ('narrow', '#undef HAVE_WIN_WCH\n#undef HAVE_GETCCHAR\n#undef HAVE_SETCCHAR\n#undef HAVE_WADD_WCHNSTR'),
            ('unavailable_resize', '#undef HAVE_WRESIZE'),
            ('unavailable_copy', '#undef HAVE_COPYWIN'),
            ('unavailable_background_get', '#undef HAVE_WGETBKGRND'),
            ('unavailable_background_set', '#undef HAVE_WBKGRNDSET'),
            ('unavailable_attrs', '#undef HAVE_WATTR_SET'),
            ('allocation_failure', ''), ('copy_failure', ''),
            ('resize_failure', ''), ('attrs_failure', ''), ('cursor_failure', ''),
            ('scroll_failure', ''), ('deletion_failure', ''), ('budgets', ''),
        ):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(
                    prefix=f'resizepad-{mode}-', dir=ROOT / '.build') as tmp:
                variant = resize_variant(source, mode).replace(
                    '#include <stdio.h>', '#include <stdio.h>\n' + definitions, 1)
                modules = test_features.FeatureTests().variant(tmp, variant)
                drawing_session(self, mode, modules, fixture='resizepad.zsh', marker=b'RESIZEPAD PASS')


if __name__ == '__main__':
    unittest.main(verbosity=2)
