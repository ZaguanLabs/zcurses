"""Optional conversion limits, retained mosaics and native placeholder research."""
import importlib.util
import os
from pathlib import Path
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unittest
import zlib

import test_features
from test_drawing import drawing_session
from test_compositions import RecipeSession

SPEC = importlib.util.spec_from_file_location('image_preview', test_features.ROOT / 'scripts/image-preview.py')
preview = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(preview)


def png(width=2, height=2, colors=((255, 255, 255),)):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    row = b''.join(bytes(colors[x % len(colors)]) for x in range(width))
    raw = b''.join(b'\0' + row for _ in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


class ImageTests(unittest.TestCase):
    def test_retained_mosaic(self):
        drawing_session(self, 'wide', env={'NO_COLOR': ''}, fixture='ui-image.zsh', marker=b'UI IMAGE PASS')

    def test_ascii_build(self):
        source = (test_features.ROOT / 'Src/Modules/zdraw.c').read_text().replace(
            '#include <stdio.h>', '#include <stdio.h>\n#undef MULTIBYTE_SUPPORT\n#undef HAVE_SETCCHAR\n#undef HAVE_GETCCHAR\n#undef HAVE_WIN_WCH\n#undef HAVE_WADD_WCHNSTR', 1)
        with tempfile.TemporaryDirectory(prefix='image-ascii-', dir=test_features.ROOT / '.build') as directory:
            modules = test_features.FeatureTests().variant(directory, source)
            drawing_session(self, 'ascii', modules, env={'NO_COLOR': ''}, fixture='ui-image.zsh', marker=b'UI IMAGE PASS')

    @unittest.skipUnless(shutil.which('magick'), 'optional ImageMagick 7 converter unavailable')
    def test_png_jpeg_and_literal_filename(self):
        with tempfile.TemporaryDirectory(dir=test_features.ROOT / '.build') as directory:
            image = Path(directory) / '-$(do-not-execute) [0].png'
            image.write_bytes(png())
            packet = preview.convert(image, 1, 2, palette='ansi16')
            self.assertEqual(packet, 'zdraw-image-1 1 2\nff\nff\n')
            jpeg = Path(directory) / 'sample.jpg'
            subprocess.run(['magick', 'PNG:' + str(image.resolve()), str(jpeg)], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=5)
            self.assertEqual(preview.convert(jpeg, 1, 2, palette='ansi16'), packet)
            image.write_bytes(b'\x89PNG\r\n\x1a\n' + b'\0' * 30)
            with self.assertRaises(ValueError):
                preview.convert(image, 1, 2)

    def test_input_bounds_and_format(self):
        with tempfile.TemporaryDirectory(dir=test_features.ROOT / '.build') as directory:
            image = Path(directory) / 'input'
            for content in (b'https://example.invalid/image.png', b'<svg/>', b'\xff\xd8\xff\xc0\x00\x01',
                            png(4097, 1), b'x' * (preview.MAX_INPUT + 1)):
                image.write_bytes(content)
                with self.assertRaises(ValueError):
                    preview.read_image(image)
            image.unlink()
            os.mkfifo(image)
            with self.assertRaises(ValueError):
                preview.read_image(image)
            with self.assertRaises(ValueError):
                preview.convert(image, 65, 128)

    @unittest.skipUnless(shutil.which('magick'), 'optional ImageMagick 7 converter unavailable')
    def test_adaptive_palette_preserves_dark_surfaces_and_accents(self):
        colors = ((0, 0, 0), (28, 28, 28), (48, 48, 48), (95, 135, 215),
                  (215, 175, 0), (0, 175, 95), (238, 238, 238))
        with tempfile.TemporaryDirectory(dir=test_features.ROOT / '.build') as directory:
            image = Path(directory) / 'dark-ui.png'
            image.write_bytes(png(7, 2, colors))
            lines = preview.convert(image, 1, 7).splitlines()
            self.assertEqual(lines[0], 'zdraw-image-2 1 7')
            palette = list(map(int, lines[1].removeprefix('palette=').split(',')))
            self.assertEqual(len(palette), 16)
            self.assertTrue(all(16 <= color <= 255 for color in palette))
            decoded = [preview.EXTENDED[palette[int(pixel, 16)] - 16] for pixel in lines[2]]
            self.assertEqual(decoded, list(colors))
            self.assertEqual(lines[2], lines[3])
            # Complex inputs still fit the packet and per-image pair budgets.
            image.write_bytes(png(128, 64, tuple((i*2, (i*41)%256, (i*83)%256) for i in range(128))))
            packet = preview.convert(image, 32, 128)
            self.assertLessEqual(len(packet), 8500)
            self.assertEqual(len(packet.splitlines()), 66)

    def test_converter_output_deadline_and_reaping(self):
        with tempfile.TemporaryDirectory(dir=test_features.ROOT / '.build') as directory:
            common = dict(env=os.environ.copy(), cwd=directory, expected=6)
            for code in ('import os; os.write(1,b"x"*7)', 'import os; os.write(1,b"x")',
                         'import time; time.sleep(10)'):
                with self.assertRaises(ValueError):
                    preview.bounded_process([sys.executable, '-c', code], timeout=.1, **common)
            self.assertEqual(preview.bounded_process([sys.executable, '-c', 'print("12345")'], **common), b'12345\n')

    def test_conversion_cancellation_reaps_worker(self):
        with tempfile.TemporaryDirectory(dir=test_features.ROOT / '.build') as directory:
            root = Path(directory).resolve()
            image, marker, converter = root / 'sample.png', root / 'worker', root / 'magick'
            image.write_bytes(png())
            converter.write_text(f'#!{sys.executable}\nimport os, pathlib, time\npathlib.Path(os.environ["IMAGE_TEST_PID"]).write_text(str(os.getpid()))\ntime.sleep(30)\n')
            converter.chmod(0o700)
            env = os.environ.copy()
            env.update(PATH=str(root) + os.pathsep + env.get('PATH', ''), TMPDIR=str(root), IMAGE_TEST_PID=str(marker))
            process = subprocess.Popen([sys.executable, str(test_features.ROOT / 'scripts/image-preview.py'), str(image)],
                                       env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 5
                while not marker.exists():
                    self.assertLess(time.monotonic(), deadline)
                    time.sleep(.01)
                worker = int(marker.read_text())
                process.terminate()
                stdout, stderr = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 143)
                self.assertEqual(stdout, b'')
                with self.assertRaises(ProcessLookupError):
                    os.kill(worker, 0)
                self.assertEqual(list(root.glob('zdraw-image-*')), [])
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                process.stdout.close()
                process.stderr.close()

    @unittest.skipUnless(shutil.which('magick'), 'optional ImageMagick 7 converter unavailable')
    def test_recipe_resize_modes_and_cleanup(self):
        with tempfile.TemporaryDirectory(dir=test_features.ROOT / '.build') as directory:
            image = Path(directory) / 'sample.png'
            image.write_bytes(png())
            session = RecipeSession(self, str(image), fixture='image-recipe.zsh')
            try:
                self.assertEqual(session.advance(), ['frame', '0', 'auto', 'image', '24', '80'], bytes(session.output[-3000:]))
                self.assertEqual(session.advance(b'g')[2], 'ascii')
                self.assertEqual(session.advance(b'm')[3], 'theme')
                self.assertEqual(session.advance(size=(6, 20))[-2:], ['6', '20'])
                self.assertEqual(session.advance(b's')[:2], ['frame', '0'])
                session.finish()
                self.assertNotIn(b'\x1b_G', session.output)
            finally:
                session.close()

    def test_unavailable_placeholder_and_signal_cleanup(self):
        session = RecipeSession(self, '/nonexistent/zdraw-image.png', fixture='image-recipe.zsh')
        try:
            self.assertEqual(session.advance()[:2], ['frame', '1'], bytes(session.output[-3000:]))
            os.write(session.control, b'interrupt\n')
            self.assertEqual(session.read(), ['done'])
            _, status = os.waitpid(session.pid, 0)
            session.reaped = True
            self.assertEqual(os.waitstatus_to_exitcode(status), 143)
            self.assertEqual(termios.tcgetattr(session.terminal), session.baseline)
        finally:
            session.close()
