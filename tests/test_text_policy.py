"""Grapheme-safe native widths, capability rejection and real curses storage."""
import json
import os
import shlex
import subprocess
import tempfile
import unittest

import test_features
from test_drawing import drawing_session

ROOT = test_features.ROOT
POLICY = 'unicode-17.0.0-egc-wcwidth-sum-attach-zero'


class TextPolicyTests(unittest.TestCase):
    def shell(self, script, modules=None, locale='C.UTF-8'):
        env = {**os.environ, 'LC_ALL': os.environ.get('ZDRAW_TEST_LOCALE', locale)}
        if locale == 'C':
            env['LC_ALL'] = 'C'
        env.pop('TERM', None)
        result = subprocess.run([test_features.ZSH, '-dfc',
            'module_path=("$1"); zmodload zdraw || exit 90;\n' + script,
            'policy-test', str(modules or ROOT / '.build/modules')],
            env=env, stdin=subprocess.DEVNULL, start_new_session=True,
            text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'PASS\n')

    def test_queries(self):
        lines = [f'policy={POLICY}', 'typeset -A p q saved',
            'zdraw textpolicy p || exit 1',
            '[[ $p[policy] == libc-wcwidth && $p[grapheme_available] == 1 ]] || exit 2',
            'zdraw textpolicy p "$policy" || exit 3',
            '[[ $p[emoji_two_cells] == 0 && $p[intra_grapheme_styles] == 0 && $p[native_storage_checked] == 1 ]] || exit 4',
            'zdraw textinfo p "👩‍💻" 2 || exit 5',
            '[[ $p[text] == "👩‍" && $p[width] == 2 && $p[total_width] == 4 ]] || exit 6']
        for case in json.loads((ROOT / 'tests/unicode/corpus.json').read_text()):
            lines.append('text=' + shlex.quote(case['text']))
            if not case['printable_query'] or case['name'] == 'many-marks':
                status = 2 if case['name'] == 'many-marks' else 1
                lines += ['p=(sentinel yes)', 'zdraw textinfo p "$text" 0 "$policy" 2>/dev/null',
                    f'(( $? == {status} )) && [[ $p[sentinel] == yes ]] || exit 7',
                    'zdraw textpos p "$text" byte 0 "$policy" 2>/dev/null',
                    f'(( $? == {status} )) && [[ $p[sentinel] == yes ]] || exit 8']
                continue
            lines += ['zdraw textinfo q "$text" || exit 9',
                      'zdraw textinfo p "$text" 100 "$policy" || exit 10',
                      '[[ $p[text] == "$text" && $p[width] == $q[width] && $p[policy] == $policy ]] || exit 11']
            start = 0
            ends = [0]
            for unit in case['units']:
                end = start + len(unit.encode())
                lines += [f'for (( i={start}; i<{end}; i++ )); do',
                    'zdraw textpos p "$text" byte "$i" "$policy" || exit 12',
                    f'[[ $p[text] == {shlex.quote(unit)} && $p[byte_start] == {start} && $p[byte_end] == {end} ]] || exit 13', 'done']
                start = end
                ends.append(end)
            lines += ['for (( i=0; i<q[width]; i++ )); do',
                'zdraw textpos p "$text" column "$i" "$policy" || exit 14',
                '(( p[column_start] <= i && p[column_end] > i )) || exit 15', 'done',
                'for (( i=0; i<=q[width]; i++ )); do',
                'zdraw textinfo p "$text" "$i" "$policy" || exit 16',
                '[[ "$p[text]$p[remainder]" == "$text" && $p[width] -le $i ]] || exit 17',
                '() { local LC_ALL=C; [[ ${#p[text]} == (' + '|'.join(map(str, ends)) + ') ]]; } || exit 18', 'done']
        lines += ['print PASS']
        self.shell('\n'.join(lines))

    def test_rejection_and_limits(self):
        self.shell(f'''
            typeset -A info=(sentinel yes)
            typeset -Ar frozen=(sentinel yes)
            policy={POLICY}
            for name in unknown unicode-17.0.0-egc-max-wcwidth-emoji2; do
              zdraw textpolicy info "$name" 2>/dev/null
              (( $? == 2 )) && [[ $info[sentinel] == yes ]] || exit 1
              zdraw textinfo info X 1 "$name" 2>/dev/null
              (( $? == 2 )) && [[ $info[sentinel] == yes ]] || exit 2
              zdraw textpos info X byte 0 "$name" 2>/dev/null
              (( $? == 2 )) && [[ $info[sentinel] == yes ]] || exit 3
            done
            for text in $'X\\n' $'X\\x00' $'X\\xff'; do
              zdraw textinfo info "$text" 0 "$policy" 2>/dev/null
              (( $? == 1 )) && [[ $info[sentinel] == yes ]] || exit 4
            done
            text=${{(pl:1048577::x:)}}
            zdraw textinfo info "$text" 0 "$policy" 2>/dev/null
            (( $? == 1 )) && [[ $info[sentinel] == yes ]] || exit 5
            zdraw textpolicy frozen "$policy" 2>/dev/null
            (( $? == 1 )) || exit 6
            unsetopt multibyte
            zdraw textpolicy info "$policy" 2>/dev/null
            (( $? == 2 )) && [[ $info[sentinel] == yes ]] || exit 7
            zdraw textpolicy info || exit 8
            [[ $info[grapheme_available] == 0 ]] || exit 9
            print PASS
        ''')

    def unavailable(self, modules=None, locale='C.UTF-8'):
        self.shell(f'''
            typeset -A info=(sentinel yes)
            zdraw textpolicy info {POLICY}
            (( $? == 2 )) && [[ $info[sentinel] == yes ]] || exit 1
            zdraw textinfo info X 1 {POLICY}
            (( $? == 2 )) && [[ $info[sentinel] == yes ]] || exit 2
            zdraw textpos info X byte 0 {POLICY}
            (( $? == 2 )) && [[ $info[sentinel] == yes ]] || exit 3
            zdraw textpolicy info || exit 4
            [[ $info[grapheme_available] == 0 ]] || exit 5
            print PASS
        ''', modules, locale)

    def test_locale_rejection(self):
        self.unavailable(locale='C')

    def test_backend_rejection(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        for define in ('HAVE_WADD_WCHNSTR', 'HAVE_WIN_WCH', 'MULTIBYTE_SUPPORT', 'HAVE_NL_LANGINFO', 'NCURSES_VERSION'):
            with self.subTest(define=define), tempfile.TemporaryDirectory(prefix='text-policy-', dir=ROOT / '.build') as tmp:
                modules = test_features.FeatureTests().variant(tmp, source.replace(
                    '#include <stdio.h>', '#include <stdio.h>\n#undef ' + define, 1))
                self.unavailable(modules)
                drawing_session(self, 'unavailable', modules, fixture='text-policy.zsh',
                                marker=b'TEXT POLICY PASS')

    def test_native_drawing(self):
        drawing_session(self, 'wide', fixture='text-policy.zsh', marker=b'TEXT POLICY PASS')
