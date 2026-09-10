"""Record real input/resize barriers, replay them, and retain readable failures."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import test_features

sys.path.insert(0, str(test_features.ROOT / 'scripts'))
import replay


class ReplayTests(unittest.TestCase):
    def test_form_paste_resize_and_saved_failure(self):
        actions = replay.read_json(test_features.ROOT / 'tests/recordings/form-resize.actions.json')
        expected = replay.capture('form', [16, 40], actions)
        actual = replay.capture('form', [16, 40], actions)
        self.assertEqual(replay.differences(expected, actual), [])
        events = [event for item in expected['observations'] for event in item['events']]
        self.assertIn('e7', [event.get('text') for event in events])
        self.assertIn('958c', [event.get('text') for event in events])
        self.assertIn('', [event.get('text') for event in events])
        final_frame = expected['observations'][-2]['frame']
        self.assertIn('界', [cell[2] for cell in final_frame['cells']])
        # A deliberately wrong expected cell demonstrates a saved input/resize
        # failure; it is not presented as a newly discovered application defect.
        broken = copy.deepcopy(expected)
        cell = next(c for c in broken['observations'][-2]['frame']['cells'] if c[2] == '界')
        cell[2] = '?'
        with tempfile.TemporaryDirectory(dir=test_features.ROOT / '.build') as tmp:
            recording, report = Path(tmp) / 'failure.json', Path(tmp) / 'failure.diff'
            recording.write_text(json.dumps(broken), encoding='ascii')
            result = subprocess.run([sys.executable, str(test_features.ROOT / 'scripts/replay.py'),
                                     'replay', str(recording), '--diff', str(report)],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn(f'barrier 9 cell {cell[0]},{cell[1]}', report.read_text())
            self.assertIn('?', report.read_text())
            self.assertIn('界', report.read_text())
            self.assertEqual(replay.validate(replay.read_json(recording)), broken)

    def test_other_recipes(self):
        for recipe in ('document', 'canvas'):
            with self.subTest(recipe=recipe):
                actions = [{'input_hex': '74'}, {'resize': [6, 20]},
                           {'resize': [24, 80]}, {'input_hex': '1b'}]
                expected = replay.capture(recipe, [24, 80], actions)
                self.assertEqual(replay.differences(expected, replay.capture(recipe, [24, 80], actions)), [])

    def test_saturated_input_queue_has_deadline_and_cleanup(self):
        session = replay.Session('form', [16, 40])
        try:
            session.start()
            # The recipe is waiting at its first presentation barrier, so it
            # cannot drain this queue until explicitly released.
            for _ in range(1024):
                try:
                    os.write(session.terminal, b'x' * 4096)
                except BlockingIOError:
                    break
            else:
                self.fail('PTY input queue did not saturate within 4 MiB')
            with self.assertRaisesRegex(ValueError, 'input queue'):
                session.advance({'input_hex': '78' * 4096})
        finally:
            session.close()
        with self.assertRaises(ChildProcessError):
            os.waitpid(session.pid, os.WNOHANG)
        for fd in (session.terminal, session.report, session.control):
            with self.assertRaises(OSError):
                os.fstat(fd)

    def test_recording_validation(self):
        sample = replay.read_json(test_features.ROOT / 'tests/recordings/form-resize.json')
        replay.validate(sample)
        variants = []
        for key, value in (('format', 'future'), ('timing', 'sleep'), ('recipe', '../../bad'),
                           ('geometry', [True, 40]), ('context', {}), ('actions', [{}]),
                           ('observations', [])):
            bad = copy.deepcopy(sample)
            bad[key] = value
            variants.append(bad)
        bad = copy.deepcopy(sample)
        bad['observations'][0]['frame']['cells'][0][2] = ['not text']
        variants.append(bad)
        bad = copy.deepcopy(sample)
        bad['observations'][1]['events'][0]['text'] = '$(touch marker)'
        variants.append(bad)
        for bad in variants:
            with self.assertRaises(ValueError):
                replay.validate(bad)
        for actions in ([{'input_hex': '1B'}], [{'input_hex': 'aa' * 4097}],
                        [{'resize': [0, 40]}], [{'input_hex': '1b'}] * 129,
                        [{'input_hex': 'aa' * 4096}] * 17 + [{'input_hex': '1b'}]):
            with self.assertRaises(ValueError):
                replay.actions_valid(actions)
        with tempfile.TemporaryDirectory(dir=test_features.ROOT / '.build') as tmp:
            oversized = Path(tmp) / 'oversized.json'
            with oversized.open('wb') as stream:
                stream.truncate(replay.LIMIT + 1)
            with self.assertRaisesRegex(ValueError, '16 MiB'):
                replay.read_json(oversized)


if __name__ == '__main__':
    unittest.main(verbosity=2)
