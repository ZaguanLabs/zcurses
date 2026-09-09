"""Prepared row equivalence, clipping, ownership, limits and optional builds."""
import tempfile
import unittest
from test_drawing import drawing_session
import test_features

ROOT = test_features.ROOT


class PreparedTests(unittest.TestCase):
    def test_prepared_rows(self):
        drawing_session(self, 'wide', fixture='prepared.zsh', marker=b'PREPARED PASS')

    def test_alternative_builds(self):
        original = (ROOT / 'Src/Modules/zdraw.c').read_text()
        for mode, definitions in (
            ('narrow', '#undef HAVE_WADD_WCHNSTR'),
            ('unavailable', '#undef HAVE_WADD_WCHNSTR\n#undef HAVE_WADDCHNSTR'),
            ('allocation_failure', '#define init_pair(p, f, b) ((p) == 2 ? ERR : init_pair(p, f, b))'),
            ('write_failure', '#define wadd_wchnstr(w, c, n) ((void)(w), (void)(c), (void)(n), ERR)'),
            ('limit', ''),
        ):
            source = original.replace('#include <stdio.h>', '#include <stdio.h>\n' + definitions, 1)
            if mode == 'limit':
                source = source.replace('((size_t)16 * 1024 * 1024)', '((size_t)1024)')
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(
                    prefix=f'prepared-{mode}-', dir=ROOT / '.build') as tmp:
                modules = test_features.FeatureTests().variant(tmp, source)
                drawing_session(self, mode, modules, fixture='prepared.zsh', marker=b'PREPARED PASS')


if __name__ == '__main__':
    unittest.main(verbosity=2)
