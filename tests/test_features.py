"""Headless discovery, feature lifecycle, and real alternative module builds."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build/zsh'
ZSH = shutil.which(os.environ.get('ZSH_TEST_SHELL', str(BUILD / 'Src/zsh')))


class FeatureTests(unittest.TestCase):
    def run_shell(self, script, modules=None, terminal=None):
        env = os.environ.copy()
        if terminal is None:
            env.pop('TERM', None)
        else:
            env['TERM'] = terminal
        result = subprocess.run(
            [ZSH, '-dfc', 'module_path=("$1"); shift\n' + script,
             'features-test', str(modules or ROOT / '.build/modules')],
            env=env, stdin=subprocess.DEVNULL, start_new_session=True,
            capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        return result.stdout

    def test_headless_discovery(self):
        script = '''
            zmodload zsh/curses || exit 1
            zmodload -F -e zsh/curses +p:zcurses_features || exit 2
            [[ ${(t)zcurses_features} == array-readonly-* ]] || exit 3
            (( ${#zcurses_windows} == 0 )) || exit 4
            typeset -a snapshot=("${zcurses_features[@]}")
            typeset -a unique=("${(@u)snapshot}")
            (( ${#snapshot} == ${#unique} )) || exit 5
            (( ! ${zcurses_features[(Ie)unrecognised_feature]} )) || exit 6
            [[ ${zcurses_features[(Ie)default_colors]} -gt 0 ]] && has_default=1 || has_default=0
            [[ ${zcurses_colors[(Ie)default]} -gt 0 ]] && color_default=1 || color_default=0
            (( has_default == color_default )) || exit 7
            # Changing an ordinary copy must not change the module's array.
            snapshot+=(application_value)
            (( ! ${zcurses_features[(Ie)application_value]} )) || exit 8
            typeset -a dimensions=(sentinel)
            expected=2
            (( ${zcurses_features[(Ie)geometry]} )) && expected=1
            # A compiled query can fail at runtime without losing its feature.
            zcurses geometry dimensions
            (( $? == expected )) || exit 9
            [[ $dimensions == sentinel ]] || exit 10
            (( ${#zcurses_windows} == 0 )) || exit 11
            print -rl -- "${zcurses_features[@]}"
        '''
        without_term = self.run_shell(script)
        invalid_term = self.run_shell(script, terminal='zcurses-nonexistent-terminal')
        self.assertEqual(without_term, invalid_term)
        self.assertNotIn('\x1b', without_term)

    def test_read_is_silent_and_does_not_consume_input(self):
        self.assertEqual(self.run_shell('''
            zmodload zsh/curses || exit 1
            inspect() {
                local -a snapshot=("${zcurses_features[@]}")
                read -r line || return 2
                [[ $line == 'input stays data' ]] || return 3
            }
            inspect <<<'input stays data' || exit 4
            (( ${#zcurses_windows} == 0 )) || exit 5
        '''), '')

    def test_readonly_and_feature_lifecycle(self):
        self.assertEqual(self.run_shell('''
            zmodload -F -e zsh/curses +p:zcurses_features && exit 1
            # Discovery can be loaded alone, without the builtin.
            zmodload -F zsh/curses p:zcurses_features || exit 2
            zmodload -F -e zsh/curses +b:zcurses && exit 3
            typeset -a snapshot=("${zcurses_features[@]}")
            ( zcurses_features=(replacement) ) 2>/dev/null && exit 4
            ( zcurses_features[1]=replacement ) 2>/dev/null && exit 5
            ( unset zcurses_features ) 2>/dev/null && exit 6
            [[ "${(j: :)snapshot}" == "${(j: :)zcurses_features}" ]] || exit 7
            zmodload -F zsh/curses -p:zcurses_features || exit 8
            zmodload -F -e zsh/curses +p:zcurses_features && exit 9
            zmodload -F -e zsh/curses p:zcurses_features || exit 10
            (( ! ${+zcurses_features} )) || exit 11
            zmodload -F zsh/curses +p:zcurses_features || exit 12
            [[ "${(j: :)snapshot}" == "${(j: :)zcurses_features}" ]] || exit 13
            zmodload -u zsh/curses || exit 14
            (( ! ${+zcurses_features} )) || exit 15
            zmodload zsh/curses || exit 16
            [[ "${(j: :)snapshot}" == "${(j: :)zcurses_features}" ]] || exit 17
        '''), '')

    def variant(self, directory, source):
        # All source edits and builds are confined to a disposable copied tree.
        tree = Path(directory) / 'zsh'
        shutil.copytree(BUILD, tree, symlinks=True)
        (tree / 'Src/Modules/curses.c').write_text(source)
        suffix = re.search(r'^DL_EXT\s*=\s*(\S+)',
                           (tree / 'Src/Makefile').read_text(), re.M).group(1)
        result = subprocess.run(
            [os.environ.get('ZCURSES_MAKE', 'make'), '-C', str(tree / 'Src/Modules'),
             f'curses.{suffix}'], capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        modules = Path(directory) / 'modules'
        (modules / 'zsh').mkdir(parents=True)
        shutil.copy2(tree / f'Src/Modules/curses.{suffix}', modules / 'zsh')
        return modules

    def test_build_without_optional_features(self):
        source = (ROOT / 'Src/Modules/curses.c').read_text()
        # Undefine after headers so system headers cannot re-enable a feature.
        source = source.replace('#include <stdio.h>', '''#include <stdio.h>
#undef TIOCGWINSZ
#undef HAVE_RESIZE_TERM
#undef NCURSES_MOUSE_VERSION
#undef HAVE_USE_DEFAULT_COLORS''', 1)
        with tempfile.TemporaryDirectory(prefix='features-disabled-', dir=ROOT / '.build') as tmp:
            modules = self.variant(tmp, source)
            self.assertEqual(self.run_shell('''
                zmodload zsh/curses || exit 1
                zmodload -F -e zsh/curses +p:zcurses_features || exit 2
                (( ${#zcurses_features} == 0 )) || exit 3
                (( ! ${zcurses_colors[(Ie)default]} )) || exit 4
                typeset -a dimensions=(sentinel)
                zcurses geometry dimensions
                (( $? == 2 )) || exit 5
                [[ $dimensions == sentinel ]] || exit 6
                (( ${#zcurses_windows} == 0 )) || exit 7
            ''', modules), '')

    def test_stock_module_discovery_fallback(self):
        with tempfile.TemporaryDirectory(prefix='features-stock-', dir=ROOT / '.build') as tmp:
            modules = self.variant(tmp, (ROOT / 'upstream/curses.c').read_text())
            self.assertEqual(self.run_shell('''
                zmodload zsh/curses || exit 1
                zmodload -F -e zsh/curses +p:zcurses_features
                (( $? == 1 )) || exit 2
                (( ! ${+zcurses_features} )) || exit 3
                (( ${#zcurses_windows} == 0 )) || exit 4
            ''', modules), '')


if __name__ == '__main__':
    unittest.main(verbosity=2)
