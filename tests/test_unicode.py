"""Pinned grapheme conformance, terminal text profile and editor integration."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest
import test_features
import test_clipping
from test_drawing import drawing_session

ROOT = test_features.ROOT


class UnicodeTests(unittest.TestCase):
    def test_unicode_17_conformance(self):
        manifest = json.loads((ROOT / 'tests/unicode/sources.json').read_text())
        path = ROOT / 'tests/unicode/GraphemeBreakTest.txt'
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), manifest[path.name]['sha256'])
        rows = []
        count = 0
        for line in path.read_text().splitlines():
            tokens = line.split('#', 1)[0].split()
            if not tokens:
                continue
            count += 1
            for n in range(1, len(tokens), 2):
                rows.append(f'{tokens[n]} {int(tokens[n - 1] == "÷")}')
            rows.append('ffffffff 0')
        self.assertEqual(count, 766)
        with tempfile.TemporaryDirectory(prefix='unicode-', dir=ROOT / '.build') as tmp:
            executable = str(Path(tmp) / 'graphemes')
            subprocess.run([*shlex.split(os.environ.get('CC', 'cc')), '-std=c99', '-Wall', '-Wextra',
                            str(ROOT / 'tests/unicode/grapheme-driver.c'), '-o', executable], check=True, capture_output=True)
            result = subprocess.run([executable], input='\n'.join(rows), text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_corpus_queries(self):
        lines = ['zmodload zdraw || exit 1', 'typeset -A p q info', 'typeset -i start end offset budget']
        for case in json.loads((ROOT / 'tests/unicode/corpus.json').read_text()):
            lines.append('text=' + shlex.quote(case['text']))
            if not case['printable_query']:
                lines += ['zdraw textpos p "$text" byte 0 grapheme 2>/dev/null && exit 2']
                continue
            lines += ['zdraw textinfo info "$text" || exit 3']
            start = 0
            ends = [0]
            for unit in case['units']:
                end = start + len(unit.encode())
                lines += [f'for (( offset={start}; offset<{end}; offset++ )); do',
                          'zdraw textpos p "$text" byte "$offset" grapheme || exit 4',
                          f'[[ $p[byte_start] == {start} && $p[byte_end] == {end} && $p[text] == {shlex.quote(unit)} ]] || exit 5',
                          '[[ $p[unicode_version] == 17.0.0 && $p[policy] == grapheme ]] || exit 6', 'done']
                start = end
                ends.append(end)
            lines += [f'zdraw textpos p "$text" byte {start} grapheme || exit 7',
                      '[[ $p[at_end] == 1 && $p[total_width] == $info[width] ]] || exit 8',
                      'for (( offset=0; offset<info[width]; offset++ )); do',
                      'zdraw textpos p "$text" column "$offset" grapheme || exit 9',
                      'zdraw textpos q "$text" byte "$p[byte_start]" grapheme || exit 10',
                      '[[ $q[text] == "$p[text]" ]] || exit 11', 'done',
                      'for (( budget=0; budget<=info[width]; budget++ )); do',
                      'zdraw textinfo p "$text" "$budget" grapheme || exit 12',
                      '[[ "$p[text]$p[remainder]" == "$text" && $p[width] -le $budget ]] || exit 13',
                      '() { local LC_ALL=C; [[ ${#p[text]} == (' + '|'.join(str(v) for v in ends) + ') ]] || exit 14; } || exit 14',
                      'done']
        lines += ['print PASS']
        env = {**os.environ, 'LC_ALL': os.environ.get('ZDRAW_TEST_LOCALE', 'C.UTF-8')}
        env.pop('TERM', None)
        result = subprocess.run([test_features.ZSH, '-dfc', 'module_path=("$1");\n' + '\n'.join(lines),
                                 'unicode-test', str(ROOT / '.build/modules')],
                                env=env, stdin=subprocess.DEVNULL, start_new_session=True,
                                text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'PASS\n')

    def test_editing_and_reflow(self):
        test_clipping.ClippingTests().headless(fixture='unicode-edit.zsh', marker='UNICODE EDIT PASS')

    def test_optional_builds(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        for defines in ('#undef MULTIBYTE_SUPPORT', '#undef HAVE_NL_LANGINFO'):
            with self.subTest(defines=defines), tempfile.TemporaryDirectory(prefix='unicode-', dir=ROOT / '.build') as tmp:
                modules = test_features.FeatureTests().variant(tmp, source.replace('#include <stdio.h>', '#include <stdio.h>\n' + defines, 1))
                test_clipping.ClippingTests().headless('unavailable', modules, 'unicode-edit.zsh', 'UNICODE EDIT PASS')

    def test_field_rendering(self):
        drawing_session(self, 'wide', fixture='unicode-draw.zsh', marker=b'UNICODE DRAW PASS')
