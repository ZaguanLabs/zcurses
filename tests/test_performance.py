"""Behavior at the boundaries of the performance shortcuts."""
import unittest
from test_drawing import drawing_session


class PerformanceContracts(unittest.TestCase):
    def test_cells_and_lookup_lifetimes(self):
        drawing_session(self, 'wide', fixture='performance.zsh',
                        marker=b'PERFORMANCE CONTRACTS PASS')
