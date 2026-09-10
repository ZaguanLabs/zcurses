"""Retained canvas geometry, marker encodings, clipping and native drawing."""
import unittest
import tempfile
import test_features
import test_clipping
from test_drawing import drawing_session


class CanvasTests(unittest.TestCase):
    def test_headless_canvas(self):
        test_clipping.ClippingTests().headless(fixture='ui-canvas.zsh', marker='UI CANVAS PASS', timeout=30)

    def test_canvas_rendering(self):
        drawing_session(self, 'wide', fixture='ui-canvas-draw.zsh', marker=b'UI CANVAS DRAW PASS')

    def test_ascii_only_build(self):
        source = (test_features.ROOT / 'Src/Modules/zdraw.c').read_text().replace(
            '#include <stdio.h>', '#include <stdio.h>\n#undef MULTIBYTE_SUPPORT\n#undef HAVE_SETCCHAR\n#undef HAVE_GETCCHAR\n#undef HAVE_WIN_WCH\n#undef HAVE_WADD_WCHNSTR', 1)
        with tempfile.TemporaryDirectory(prefix='canvas-ascii-', dir=test_features.ROOT / '.build') as directory:
            modules = test_features.FeatureTests().variant(directory, source)
            drawing_session(self, 'ascii', modules, fixture='ui-canvas-draw.zsh', marker=b'UI CANVAS DRAW PASS')
