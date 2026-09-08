"""Runtime color metadata, session lifecycle, and capability failure paths."""
import tempfile
import unittest

import test_features
from test_drawing import drawing_session

ROOT = test_features.ROOT


class ColorInfoTests(unittest.TestCase):
    def run_shell(self, script, **kwargs):
        return test_features.FeatureTests().run_shell(script, **kwargs)

    def session(self, mode='normal', modules=None, terminal='xterm-256color'):
        drawing_session(self, mode, modules, {'TERM': terminal},
                        fixture='colorinfo.zsh', marker=b'COLORINFO PASS')

    def test_headless_and_assignment(self):
        script = '''
            zmodload zsh/curses || exit 1
            (( ${zcurses_features[(Ie)colorinfo]} )) || exit 2
            inspect() {
                local -A info=(stale value)
                zcurses colorinfo info || exit 3
                [[ $info[initialized] == 0 && ${+info[stale]} == 0 ]] || exit 4
                local key
                for key in has_colors color_started default_colors can_change_color \\
                    colors color_pairs color_limit pair_limit bg_pair_limit query_pair_limit spans_pair_limit pairs_used pairs_free \
                    truecolor_supported truecolor_enabled rgb_min rgb_max; do
                    [[ $info[$key] == unknown ]] || exit 5
                done
                # Assignment must find the caller's local association.
                nested() { zcurses colorinfo info; }
                nested || exit 6
                [[ $info[initialized] == 0 ]] || exit 7
                read -r line || exit 8
                [[ $line == 'input stays data' ]] || exit 9
            }
            inspect <<<'input stays data' || exit 10
            (( ! ${+info} && ${#zcurses_windows} == 0 )) || exit 11
            zcurses colorinfo fresh || exit 12
            [[ ${(t)fresh} == association && $fresh[initialized] == 0 ]] || exit 13
            typeset -A output=(keep value)
            zcurses colorinfo output extra 2>/dev/null && exit 14
            [[ $output[keep] == value && ${#output} == 1 ]] || exit 15
            zcurses colorinfo 2>/dev/null && exit 16
            zcurses colorinfo 'output[key]' 2>/dev/null && exit 17
            zcurses colorinfo 'bad name' 2>/dev/null && exit 18
            typeset -Ar frozen=(keep value)
            zcurses colorinfo frozen 2>/dev/null && exit 19
            [[ $frozen[keep] == value ]] || exit 20
            typeset scalar=keep
            zcurses colorinfo scalar 2>/dev/null && exit 21
            [[ $scalar == keep ]] || exit 22
            zcurses colorinfo functions 2>/dev/null && exit 23
            print -r -- 'headless assignment passed'
        '''
        self.assertEqual(self.run_shell(script), 'headless assignment passed\n')
        self.assertEqual(self.run_shell(script, terminal='zcurses-nonexistent-terminal'),
                         'headless assignment passed\n')

    def test_runtime_lifecycle_and_pair_counts(self):
        self.session()

    def test_monochrome_terminal(self):
        self.session('monochrome', terminal='vt100')

    def test_initialization_failure_and_optional_support(self):
        source = (ROOT / 'Src/Modules/curses.c').read_text()
        variants = {
            'failed_start': '#undef start_color\n#define start_color() ERR',
            'defaults_failed': '#undef use_default_colors\n#define use_default_colors() ERR',
            'no_defaults': '#undef HAVE_USE_DEFAULT_COLORS',
            'narrow': '#undef HAVE_SETCCHAR\n#undef HAVE_GETCCHAR\n#undef HAVE_WIN_WCH',
        }
        for mode, definitions in variants.items():
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(
                    prefix='colorinfo-', dir=ROOT / '.build') as tmp:
                modules = test_features.FeatureTests().variant(
                    tmp, source.replace('#include <stdio.h>', '#include <stdio.h>\n' + definitions, 1))
                self.session(mode, modules)


if __name__ == '__main__':
    unittest.main(verbosity=2)
