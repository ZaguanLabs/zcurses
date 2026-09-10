"""Shared-window backing, bounded reconstruction and coherent failure states."""
import tempfile
import unittest
import test_features
from test_drawing import drawing_session

ROOT = test_features.ROOT


class TreeTests(unittest.TestCase):
    def test_shared_tree_geometry(self):
        output = drawing_session(self, 'wide', fixture='trees.zsh', marker=b'TREES PASS')
        self.assertNotIn(b'CHILD', output, 'tree geometry must not present')

    def test_optional_tree_and_failures(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        begin, end = source.index('static int\nzccmd_treewin('), source.index('static int\nzccmd_addpad(')
        for mode, old, new in (
            ('unavailable', '# define ZDRAW_WINDOW_TREE 1', '/* unavailable tree */'),
            ('allocation_failure', 'replacement = dupwin(w->win);', 'replacement = NULL;'),
            ('view_failure', 'replacement = subwin(', 'replacement = (i == 2 ? NULL : subwin('),
            ('resize_failure', 'wresize(replacement, entries[i].rows, entries[i].cols) == ERR', '(wresize(replacement, entries[i].rows, entries[i].cols), 1)'),
            ('attrs_failure', 'wattr_set(replacement, attrs, pair, NULL) == ERR', '1'),
            ('cell_limit', '#define ZDRAW_RESIZE_CELLS 262144', '#define ZDRAW_RESIZE_CELLS 8'),
            ('tree_limit', '#define ZDRAW_TREE_WINDOWS 64', '#define ZDRAW_TREE_WINDOWS 3'),
            ('retire', 'delwin(zdraw_tree_retired[i]) != ERR', '(retire_calls++ == 0 ? ERR : delwin(zdraw_tree_retired[i])) != ERR'),
        ):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(prefix='trees-', dir=ROOT / '.build') as tmp:
                if mode.endswith('_failure'):
                    body = source[begin:end].replace(old, new, 1)
                    if mode == 'view_failure':
                        body = body.replace('entries[i].rows, entries[i].cols, entries[i].row, entries[i].col);',
                                            'entries[i].rows, entries[i].cols, entries[i].row, entries[i].col));', 1)
                    variant = source[:begin] + body + source[end:]
                else: variant = source.replace(old, new, 1)
                if mode == 'retire': variant = variant.replace('#include <stdio.h>', '#include <stdio.h>\nstatic int retire_calls;', 1)
                modules = test_features.FeatureTests().variant(tmp, variant)
                drawing_session(self, mode, modules, fixture='trees.zsh', marker=b'TREES PASS')
