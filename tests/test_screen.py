"""Safe serialization, conservative occupancy and restore failure cleanup."""
import tempfile
import unittest
import test_features
from test_drawing import drawing_session


class ScreenTests(unittest.TestCase):
    def test_roundtrip_and_invalid_data(self):
        drawing_session(self, 'normal', fixture='screen.zsh', marker=b'SCREEN PASS')

    def test_native_failures_release_prepared_rows(self):
        source = (test_features.ROOT / 'Src/Modules/zdraw.c').read_text()
        for mode, definition in (
            ('allocation_failure', '#define init_pair(a,b,c) ERR'),
            ('write_failure', '#define wadd_wchnstr(a,b,c) ERR'),
        ):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(dir=test_features.ROOT / '.build') as tmp:
                variant = source.replace('#include <stdio.h>', '#include <stdio.h>\n' + definition, 1)
                modules = test_features.FeatureTests().variant(tmp, variant)
                drawing_session(self, mode, modules, fixture='screen.zsh', marker=b'SCREEN PASS')
