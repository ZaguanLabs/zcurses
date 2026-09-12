#!/usr/bin/env python3
"""Compare query statuses and complete associations against a matching baseline."""
import argparse
import os
from pathlib import Path
import random
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-modules', type=Path, required=True)
    parser.add_argument('--modules', type=Path, default=ROOT / '.build/modules')
    parser.add_argument('--shell', type=Path, default=ROOT / '.build/zsh/Src/zsh')
    args = parser.parse_args()
    rng = random.Random(731)
    policies = ('cell', 'grapheme', 'unicode-17.0.0-egc-wcwidth-sum-attach-zero')
    texts = ['', 'A' * 96, 'AŁ' * 24, 'eeeeee' + '\u0301' * 6,
             'A\x1b', '\u0301A', '👩\u200d💻', '🇳🇴🇸🇪', 'का']
    for _ in range(91):
        texts.append(''.join(rng.choice(['a', 'Z', ' ', '界', 'e\u0301', '\u0301',
                                        'Ł', '\x01', '\u200d', '🇳'])
                             for _ in range(rng.randrange(0, 35))))
    lines = ['emulate -R zsh', 'module_path=("$1")', 'zmodload zdraw || exit 1',
             'typeset -A r', 'typeset key rc',
             '''dump() {
               print -rn -- "$rc"$'\\0'
               for key in "${(@ok)r}"; do
                 print -rn -- "$key"$'\\0'"$r[$key]"$'\\0'
               done
             }''']
    count = 0
    for text in texts:
        lines.append('text=' + shlex.quote(text))
        for policy in policies:
            for offset in (0, 1, 2, 4, 8, 32):
                operations = (f'textinfo r "$text" {offset} {policy}',
                              f'textpos r "$text" byte {offset} {policy}',
                              f'textpos r "$text" column {offset} {policy}')
                for operation in operations:
                    lines += ['r=(sentinel unchanged)', f'zdraw {operation} 2>/dev/null',
                              'rc=$?', 'dump']
                    count += 1
    env = {**os.environ, 'LC_ALL': os.environ.get('ZDRAW_TEST_LOCALE', 'C.UTF-8')}
    with tempfile.TemporaryDirectory(prefix='text-differential-', dir=ROOT / '.build') as tmp:
        script = Path(tmp) / 'queries.zsh'
        script.write_text('\n'.join(lines), encoding='utf-8')
        outputs = []
        for modules in (args.baseline_modules, args.modules):
            result = subprocess.run([args.shell, '-df', script, modules.resolve()],
                                    env=env, capture_output=True, timeout=60, check=True)
            outputs.append(result.stdout)
        if outputs[0] != outputs[1]:
            raise RuntimeError('query status/output differs from baseline')
    print(f'{count} query cases: identical statuses and complete associations (seed 731).')


if __name__ == '__main__':
    main()
