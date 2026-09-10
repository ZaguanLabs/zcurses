"""Cell-width analysis without a terminal and clipped styled rows with curses."""
import os
import subprocess
import tempfile
import unittest

import test_features
from test_drawing import drawing_session

ROOT, ZSH = test_features.ROOT, test_features.ZSH


class ClippingTests(unittest.TestCase):
    def headless(self, mode='wide', modules=None, fixture='textinfo.zsh', marker='TEXTINFO PASS', timeout=10):
        locales = subprocess.check_output(['locale', '-a'], text=True).splitlines()
        utf8 = os.environ.get('ZDRAW_TEST_LOCALE') or next(
            (x for x in locales if 'utf8' in x.lower().replace('-', '')), None)
        self.assertIsNotNone(utf8, 'A UTF-8 locale is required')
        env = {**os.environ, 'LC_ALL': utf8}
        env.pop('TERM', None)
        result = subprocess.run([ZSH, '-df', str(ROOT / 'tests' / fixture),
                                 str(modules or ROOT / '.build/modules'), mode],
                                env=env, start_new_session=True, stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, timeout=timeout)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, marker + '\n')
        self.assertEqual(result.stderr, '')

    def test_headless_measurement_and_clipping(self):
        self.headless()

    def test_text_positions(self):
        self.headless(fixture='textpos.zsh', marker='TEXTPOS PASS')

    def test_clipped_styled_rows(self):
        output = drawing_session(self, 'wide', fixture='clipping.zsh', marker=b'CLIPPING PASS')
        self.assertIn('e\u0301'.encode(), output)

    def test_optional_implementations(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        for mode, definitions in (
                ('allocation_failure', '#define init_pair(p, f, b) ((p) == 2 ? ERR : init_pair(p, f, b))'),
                ('narrow', '#undef HAVE_WADD_WCHNSTR'),
                ('unavailable', '#undef HAVE_WADD_WCHNSTR\n#undef HAVE_WADDCHNSTR'),
                ('ascii', '#undef MULTIBYTE_SUPPORT\n#undef HAVE_SETCCHAR\n#undef HAVE_GETCCHAR\n#undef HAVE_WIN_WCH\n#undef HAVE_WADD_WCHNSTR')):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(
                    prefix='clipping-variant-', dir=ROOT / '.build') as tmp:
                modules = test_features.FeatureTests().variant(
                    tmp, source.replace('#include <stdio.h>', '#include <stdio.h>\n' + definitions, 1))
                self.headless('ascii' if mode == 'ascii' else 'wide', modules)
                self.headless('ascii' if mode == 'ascii' else 'wide', modules,
                              'textpos.zsh', 'TEXTPOS PASS')
                drawing_session(self, mode, modules, fixture='clipping.zsh', marker=b'CLIPPING PASS')


if __name__ == '__main__':
    unittest.main(verbosity=2)
