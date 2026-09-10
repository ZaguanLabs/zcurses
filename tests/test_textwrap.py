"""Headless wrapped source ranges, bounds and ASCII fallback."""
import tempfile
import unittest
import test_clipping
import test_features

ROOT = test_features.ROOT


class TextWrapTests(unittest.TestCase):
    def test_wrapped_source_ranges(self):
        test_clipping.ClippingTests().headless(fixture='textwrap.zsh', marker='TEXTWRAP PASS')

    def test_optional_wrapping_and_limits(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        for mode in ('ascii', 'limits'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(
                    prefix=f'textwrap-{mode}-', dir=ROOT / '.build') as tmp:
                variant = source
                if mode == 'ascii':
                    variant = variant.replace('#include <stdio.h>', '#include <stdio.h>\n'
                        '#undef MULTIBYTE_SUPPORT\n#undef HAVE_SETCCHAR\n#undef HAVE_GETCCHAR\n'
                        '#undef HAVE_WIN_WCH\n#undef HAVE_WADD_WCHNSTR', 1)
                else:
                    variant = variant.replace('#define ZDRAW_WRAP_BYTES 1048576', '#define ZDRAW_WRAP_BYTES 16').replace(
                        '#define ZDRAW_WRAP_LINES 4096', '#define ZDRAW_WRAP_LINES 3')
                modules = test_features.FeatureTests().variant(tmp, variant)
                test_clipping.ClippingTests().headless(mode, modules, 'textwrap.zsh', 'TEXTWRAP PASS')


if __name__ == '__main__':
    unittest.main(verbosity=2)
