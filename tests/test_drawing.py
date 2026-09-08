"""Exercise cell contents and allocation boundaries in a real curses session."""
import ctypes
import errno
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import termios
import time
import unittest

import test_features
import tempfile

ROOT, ZSH = test_features.ROOT, test_features.ZSH


def drawing_session(case, mode, modules=None, env=None,
                    fixture='drawing.zsh', marker=b'DRAWING PASS'):
    locales = subprocess.run(['locale', '-a'], capture_output=True, text=True, check=True).stdout.splitlines()
    utf8_locale = os.environ.get('ZCURSES_TEST_LOCALE') or next(
        (name for name in locales if 'utf8' in name.lower().replace('-', '')), None)
    case.assertIsNotNone(utf8_locale, 'Drawing tests require a UTF-8 locale (or ZCURSES_TEST_LOCALE)')
    short_max = (1 << (8 * ctypes.sizeof(ctypes.c_short) - 1)) - 1
    pid, terminal = pty.fork()
    if pid == 0:
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        os.environ.update(TERM='xterm-256color', LC_ALL=utf8_locale)
        os.environ.pop('LINES', None)
        os.environ.pop('COLUMNS', None)
        if env:
            os.environ.update(env)
        os.execl(ZSH, ZSH, '-df', str(ROOT / 'tests' / fixture),
                 str(modules or ROOT / '.build/modules'), mode, str(short_max))
    output = bytearray()
    reaped = False
    deadline = time.monotonic() + 30
    try:
        while True:
            remaining = deadline - time.monotonic()
            case.assertGreater(remaining, 0, f'Drawing fixture timed out: {output[-4000:]!r}')
            if select.select([terminal], [], [], min(remaining, 0.1))[0]:
                try:
                    data = os.read(terminal, 65536)
                except OSError as exc:
                    if exc.errno != errno.EIO:
                        raise
                    data = b''
                output.extend(data)
                if not data:
                    child, result = os.waitpid(pid, os.WNOHANG)
                    if child:
                        reaped = True
                        break
            else:
                child, result = os.waitpid(pid, os.WNOHANG)
                if child:
                    reaped = True
                    # Read remaining output through EOF on the next iteration.
                    while select.select([terminal], [], [], 0)[0]:
                        try:
                            data = os.read(terminal, 65536)
                        except OSError as exc:
                            if exc.errno != errno.EIO:
                                raise
                            break
                        if not data:
                            break
                        output.extend(data)
                    break
        case.assertEqual(os.waitstatus_to_exitcode(result), 0, output.decode(errors='replace'))
        case.assertIn(marker, output)
        case.assertNotIn(b'runtime error:', output)
        case.assertNotIn(b'ERROR: AddressSanitizer', output)
    finally:
        if not reaped:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)
        os.close(terminal)


class DrawingTests(unittest.TestCase):
    def test_wide_characters_borders_and_colors(self):
        features = test_features.FeatureTests().run_shell(
            'zmodload zsh/curses || exit 1; print -rl -- "${zcurses_features[@]}"')
        if 'wide_borders' not in features.splitlines():
            self.skipTest('This build does not provide wide curses borders')
        drawing_session(self, 'wide')

    def test_color_pair_exhaustion(self):
        drawing_session(self, 'exhaustion')

    def test_narrow_curses_paths(self):
        source = (ROOT / 'Src/Modules/curses.c').read_text().replace(
            '#include <stdio.h>', '''#include <stdio.h>
#undef HAVE_SETCCHAR
#undef HAVE_GETCCHAR
#undef HAVE_WIN_WCH
#undef HAVE_WADDWSTR
#undef HAVE_WBORDER_SET''', 1)
        with tempfile.TemporaryDirectory(prefix='drawing-narrow-', dir=ROOT / '.build') as tmp:
            modules = test_features.FeatureTests().variant(tmp, source)
            drawing_session(self, 'narrow', modules)


if __name__ == '__main__':
    unittest.main(verbosity=2)
