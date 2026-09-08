"""Real RGB SGR output, direct-color capability checks and session opt-in."""
from pathlib import Path
import subprocess
import tempfile
import unittest

import test_features
import test_geometry
from test_drawing import drawing_session

ROOT = test_features.ROOT


class TrueColorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        features = test_features.FeatureTests().run_shell(
            'zmodload zsh/curses || exit 1; print -rl -- "${zcurses_features[@]}"')
        if 'truecolor' not in features.splitlines():
            raise unittest.SkipTest('This build does not provide the optional RGB library interface')
        cls.temp = tempfile.TemporaryDirectory(prefix='truecolor-terminfo-', dir=ROOT / '.build')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.terminfo = str(Path(cls.temp.name) / 'terminfo')
        subprocess.run(['tic', '-x', '-o', cls.terminfo, str(ROOT / 'tests/truecolor.terminfo')],
                       capture_output=True, text=True, check=True)

    def session(self, mode='normal', terminal='zcurses-test-rgb', modules=None):
        return drawing_session(self, mode, modules,
                               {'TERM': terminal, 'TERMINFO': self.terminfo},
                               'truecolor.zsh', b'TRUECOLOR PASS')

    def test_rgb_output_and_pair_readback(self):
        output = self.session('high_pairs')
        for sgr in (b'38;2;17;34;51m', b'48;2;68;85;102m',
                    b'38;2;255;255;255m', b'48;2;0;0;8m',
                    b'38;2;86;120;154m', b'48;2;103;137;171m'):
            self.assertIn(b'\x1b[' + sgr, output)

    def test_opt_in_preserves_input_modes_and_deferred_refresh(self):
        test_geometry.GeometryTests().geometry_session('zcurses-test-rgb', self.terminfo)

    def test_exact_low_rgb_values(self):
        output = self.session('exact', 'zcurses-test-rgb-exact')
        self.assertIn(b'\x1b[38;2;0;0;1m', output)
        self.assertIn(b'\x1b[48;2;0;0;0m', output)

    def test_encoding_and_unsupported_terminals(self):
        for terminal, mode in (
                ('zcurses-test-rgb-number', 'normal'),
                ('zcurses-test-rgb-string', 'normal'),
                ('zcurses-test-rgb-wrong', 'unsupported'),
                ('zcurses-test-rgb-small', 'unsupported'),
                ('xterm-256color', 'unsupported'),
                ('vt100', 'unsupported')):
            with self.subTest(terminal=terminal):
                self.session(mode, terminal)

    def test_optional_library_paths_and_allocation_failure(self):
        source = (ROOT / 'Src/Modules/curses.c').read_text()
        for mode, definitions in (
                ('unavailable', '#undef HAVE_INIT_EXTENDED_PAIR'),
                ('unsupported', '#define extended_color_content(c, r, g, b) ERR'),
                ('unsupported', '#undef start_color\n#define start_color() ERR'),
                ('normal', '#undef HAVE_WADD_WCHNSTR\n#undef HAVE_SETCCHAR\n#undef HAVE_GETCCHAR\n#undef HAVE_WIN_WCH'),
                ('allocation_failure', '#define init_extended_pair(p, f, b) ((p) == 2 ? ERR : init_extended_pair(p, f, b))')):
            with self.subTest(mode=mode, definitions=definitions), tempfile.TemporaryDirectory(
                    prefix='truecolor-variant-', dir=ROOT / '.build') as tmp:
                modules = test_features.FeatureTests().variant(
                    tmp, source.replace('#include <stdio.h>', '#include <stdio.h>\n' + definitions, 1))
                self.session(mode, modules=modules)


if __name__ == '__main__':
    unittest.main(verbosity=2)
