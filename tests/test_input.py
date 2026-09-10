"""Editing boundaries, paste transactions, validation and retained form cells."""
import unittest
import test_clipping
from test_drawing import drawing_session


class InputTests(unittest.TestCase):
    def test_headless_editing_and_forms(self):
        test_clipping.ClippingTests().headless(fixture='ui-input.zsh', marker='UI INPUT PASS')

    def test_field_and_form_rendering(self):
        drawing_session(self, 'wide', fixture='ui-form.zsh', marker=b'UI FORM PASS')
