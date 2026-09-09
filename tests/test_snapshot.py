"""Window capture, independent data ownership, budgets and partial failures."""
import tempfile
import unittest
import test_features
from test_drawing import drawing_session

ROOT = test_features.ROOT


class SnapshotTests(unittest.TestCase):
    def test_window_snapshot(self):
        drawing_session(self, 'wide', fixture='snapshot.zsh', marker=b'SNAPSHOT PASS')

    def test_optional_readers_and_failures(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        variants = [
            ('narrow', '#undef HAVE_WIN_WCH\n#undef HAVE_GETCCHAR\n#undef HAVE_SETCCHAR\n#undef HAVE_WADD_WCHNSTR'),
            ('copy_failure', '#define dupwin(w) ((WINDOW *)0)'),
            ('read_failure', 'static int snapshot_read_count;\n#define win_wch(w, c) (++snapshot_read_count % 7 == 0 ? ERR : win_wch(w, c))'),
            ('move_failure', ''), ('cell_limit', ''), ('byte_limit', ''),
        ]
        for mode, definitions in variants:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(
                    prefix=f'snapshot-{mode}-', dir=ROOT / '.build') as tmp:
                variant = source.replace('#include <stdio.h>', '#include <stdio.h>\n' + definitions, 1)
                if mode == 'move_failure':
                    variant = variant.replace('wmove(copy, y, x) == ERR', '(x == 3 || wmove(copy, y, x) == ERR)', 1)
                elif mode == 'cell_limit':
                    variant = variant.replace('#define ZDRAW_SNAPSHOT_CELLS 65536', '#define ZDRAW_SNAPSHOT_CELLS 8', 1)
                elif mode == 'byte_limit':
                    variant = variant.replace('#define ZDRAW_SNAPSHOT_BYTES ((size_t)16 * 1024 * 1024)', '#define ZDRAW_SNAPSHOT_BYTES ((size_t)1024)', 1)
                modules = test_features.FeatureTests().variant(tmp, variant)
                drawing_session(self, mode, modules, fixture='snapshot.zsh', marker=b'SNAPSHOT PASS')


if __name__ == '__main__':
    unittest.main(verbosity=2)
