"""Styled row drawing, preflight failures and optional curses implementations."""
import tempfile
import unittest

from test_drawing import drawing_session
import test_features

ROOT = test_features.ROOT


class SpanTests(unittest.TestCase):
    def session(self, mode, modules=None, env=None):
        drawing_session(self, mode, modules, env, 'spans.zsh', b'SPANS PASS')

    def test_wide_spans(self):
        self.session('wide')

    def test_monochrome_spans(self):
        self.session('monochrome', env={'TERM': 'vt100'})

    def test_alternative_builds(self):
        source = (ROOT / 'Src/Modules/curses.c').read_text()
        for mode, definitions in (
            ('narrow', '#undef HAVE_WADD_WCHNSTR'),
            ('unavailable', '#undef HAVE_WADD_WCHNSTR\n#undef HAVE_WADDCHNSTR'),
            ('write_failure', '#define wadd_wchnstr(w, c, n) ((void)(w), (void)(c), (void)(n), ERR)'),
            ('allocation_failure', '#define init_pair(p, f, b) ((p) == 2 ? ERR : init_pair(p, f, b))'),
        ):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(
                    prefix=f'spans-{mode}-', dir=ROOT / '.build') as tmp:
                modules = test_features.FeatureTests().variant(
                    tmp, source.replace('#include <stdio.h>', '#include <stdio.h>\n' + definitions, 1))
                self.session(mode, modules)


if __name__ == '__main__':
    unittest.main(verbosity=2)
