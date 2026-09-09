"""Opaque copies, aliased storage, optional builds and staged failures."""
import tempfile
import unittest
import test_features
from test_drawing import drawing_session

ROOT = test_features.ROOT


class CopyTests(unittest.TestCase):
    def test_region_copy(self):
        features = test_features.FeatureTests().run_shell(
            'zmodload zdraw || exit 1; print -rl -- "${zdraw_features[@]}"')
        # norefresh_events currently identifies ncurses builds. Native edge
        # readback is evidence for this implementation, not a portable promise.
        env = {'ZDRAW_TEST_NATIVE_EDGES': '1' if 'norefresh_events' in features.splitlines() else '0'}
        output = drawing_session(self, 'wide', env=env, fixture='copy.zsh', marker=b'COPY PASS')
        self.assertNotIn(b'abcdefghij', output, 'copy must not present source content')

    def test_optional_copy_and_failures(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        for mode, definitions in (
            ('narrow', '#undef HAVE_WIN_WCH\n#undef HAVE_GETCCHAR\n#undef HAVE_SETCCHAR\n#undef HAVE_WADD_WCHNSTR'),
            ('unavailable_copy', '#undef HAVE_COPYWIN'),
            ('unavailable_pad', '#undef HAVE_NEWPAD'),
            ('allocation_failure', '#define newpad(r, c) ((WINDOW *)0)'),
            ('read_failure', '#define copywin(s, d, sy, sx, dy, dx, ey, ex, o) ERR'),
            ('write_failure', 'static int copy_calls;\n#define copywin(s, d, sy, sx, dy, dx, ey, ex, o) (++copy_calls == 2 ? (copywin(s, d, sy, sx, dy, dx, dy, ex, o), ERR) : copywin(s, d, sy, sx, dy, dx, ey, ex, o))'),
            ('cell_limit', ''),
        ):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(
                    prefix=f'copy-{mode}-', dir=ROOT / '.build') as tmp:
                variant = source.replace('#include <stdio.h>', '#include <stdio.h>\n' + definitions, 1)
                if mode == 'cell_limit':
                    variant = variant.replace('#define ZDRAW_COPY_CELLS 65536', '#define ZDRAW_COPY_CELLS 8')
                modules = test_features.FeatureTests().variant(tmp, variant)
                drawing_session(self, mode, modules, fixture='copy.zsh', marker=b'COPY PASS')


if __name__ == '__main__':
    unittest.main(verbosity=2)
