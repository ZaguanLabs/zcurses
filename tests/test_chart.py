"""Bounded series, safe numeric projection and retained chart geometry."""
import unittest
import tempfile
import test_features
import test_clipping
from test_drawing import drawing_session


class ChartTests(unittest.TestCase):
    def test_headless_series(self):
        test_clipping.ClippingTests().headless(fixture='ui-chart.zsh', marker='UI CHART PASS')

    def test_chart_rendering(self):
        drawing_session(self, 'wide', fixture='ui-chart-draw.zsh', marker=b'UI CHART DRAW PASS')

    def test_ascii_only_build(self):
        source = (test_features.ROOT / 'Src/Modules/zdraw.c').read_text().replace(
            '#include <stdio.h>', '#include <stdio.h>\n#undef MULTIBYTE_SUPPORT\n#undef HAVE_SETCCHAR\n#undef HAVE_GETCCHAR\n#undef HAVE_WIN_WCH\n#undef HAVE_WADD_WCHNSTR', 1)
        with tempfile.TemporaryDirectory(prefix='chart-ascii-', dir=test_features.ROOT / '.build') as directory:
            modules = test_features.FeatureTests().variant(directory, source)
            drawing_session(self, 'ascii', modules, fixture='ui-chart-draw.zsh', marker=b'UI CHART DRAW PASS')
