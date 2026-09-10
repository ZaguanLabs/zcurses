"""Transparency distinguishes plain holes from styled blanks and snapshots aliases."""
import tempfile
import unittest
import test_features
from test_drawing import drawing_session

ROOT = test_features.ROOT


class OverlayTests(unittest.TestCase):
    def test_transparent_copy(self):
        output = drawing_session(self, 'wide', fixture='overlay.zsh', marker=b'OVERLAY PASS')
        self.assertNotIn(b'DDDDD', output, 'overlay must not present')

    def test_optional_overlay_and_failures(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        for mode, definitions in (
            ('narrow', '#undef HAVE_WIN_WCH\n#undef HAVE_GETCCHAR'),
            ('unavailable', '#undef HAVE_COPYWIN'),
            ('allocation_failure', '#define newpad(r,c) ((WINDOW *)0)'),
            ('read_failure', '#define copywin(s,d,sy,sx,dy,dx,ey,ex,o) ERR'),
            ('write_failure', 'static int overlay_calls;\n#define copywin(s,d,sy,sx,dy,dx,ey,ex,o) (++overlay_calls == 2 ? (copywin(s,d,sy,sx,dy,dx,ey,ex,o), ERR) : copywin(s,d,sy,sx,dy,dx,ey,ex,o))'),
            ('cell_limit', ''),
        ):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(prefix='overlay-', dir=ROOT / '.build') as tmp:
                variant = source.replace('#include <stdio.h>', '#include <stdio.h>\n' + definitions, 1)
                if mode == 'cell_limit': variant = variant.replace('#define ZDRAW_COPY_CELLS 65536', '#define ZDRAW_COPY_CELLS 8')
                modules = test_features.FeatureTests().variant(tmp, variant)
                drawing_session(self, mode, modules, fixture='overlay.zsh', marker=b'OVERLAY PASS')
