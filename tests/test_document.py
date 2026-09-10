"""Structured document wrapping, source anchors and semantic retained cells."""
import unittest
import test_clipping
from test_drawing import drawing_session


class DocumentTests(unittest.TestCase):
    def test_headless_document(self):
        test_clipping.ClippingTests().headless(fixture='ui-document.zsh', marker='UI DOCUMENT PASS')

    def test_document_rendering(self):
        drawing_session(self, 'wide', fixture='ui-document-draw.zsh', marker=b'UI DOCUMENT DRAW PASS')
