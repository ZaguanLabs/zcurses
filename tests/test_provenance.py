"""The recorded baseline is immutable and independent of project licence edits."""
import hashlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ProvenanceTests(unittest.TestCase):
    def test_upstream_manifest(self):
        paths = set()
        for entry in (ROOT / 'upstream/SHA256SUMS').read_text().splitlines():
            digest, name = entry.split()
            with self.subTest(file=name):
                path = Path(name)
                self.assertEqual(path.parts[0], 'upstream')
                self.assertNotIn('..', path.parts)
                self.assertNotIn(name, paths)
                paths.add(name)
                self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), digest)
        self.assertIn('upstream/LICENCE', paths)
