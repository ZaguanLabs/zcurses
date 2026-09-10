"""Canonical snapshots, fixed visual baselines, and safe readable reports."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

from test_drawing import drawing_session
import test_features

ROOT = test_features.ROOT
spec = importlib.util.spec_from_file_location('visual_diff', ROOT / 'scripts/visual_diff.py')
visual = importlib.util.module_from_spec(spec)
spec.loader.exec_module(visual)


class VisualTests(unittest.TestCase):
    def test_portable_snapshots_and_baselines(self):
        with tempfile.TemporaryDirectory(dir=ROOT / '.build', prefix='visual-') as directory:
            drawing_session(self, 'wide', fixture='visual.zsh', marker=b'VISUAL PASS', env={'ZDRAW_VISUAL_DIR': directory})
            for path in Path(directory).glob('*.json'):
                actual = visual.load(path)
                self.assertTrue(any(cell[4] == '' for cell in actual['cells']))
                if path.name == 'quoted.json':
                    self.assertEqual([c[2] for c in actual['cells'][:5]], ['"', '\\', 'e\u0301', '界', '界'])
                    self.assertNotIn('pair', path.read_text())
                    continue
                baseline = ROOT / 'tests/fixtures/ui' / path.name
                if os.environ.get('ZDRAW_UPDATE_VISUALS') == '1':
                    baseline.parent.mkdir(parents=True, exist_ok=True)
                    baseline.write_bytes(path.read_bytes())
                expected = visual.load(baseline)
                diffs = visual.changes(expected, actual)
                self.assertEqual(diffs, [], f'{path.name}: ' + '\n'.join(diffs[:20]))

    def test_diff_and_html_escaping(self):
        sample = {'format': 'zdraw-ui-fixture-1', 'layout': 'readback', 'rows': 1, 'columns': 1,
                  'cursor': [0, 0], 'cells': [[0, 0, '<script>', '1/0', 'bold', 'multibyte']]}
        changed = json.loads(json.dumps(sample))
        changed['cells'][0][3] = '2/0'
        self.assertEqual(len(visual.changes(sample, changed)), 1)
        report = visual.html_report(sample, changed)
        self.assertNotIn('<script>', report)
        self.assertIn('&lt;script&gt;', report)
        self.assertIn('cell changed', report)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'bad.json'
            for invalid in ([], {}, {**sample, 'cells': []}, {**sample, 'cursor': [True, 0]}):
                path.write_text(json.dumps(invalid))
                with self.assertRaises(ValueError):
                    visual.load(path)
