"""An interactive matching Zsh owns the foreground/background application job."""
import errno
import fcntl
import os
import pty
import select
import shlex
import signal
import struct
import tempfile
import termios
import time
import unittest
from test_features import ROOT, ZSH


class JobControlTests(unittest.TestCase):
    def test_explicit_handoff_across_bg_and_fg(self):
        control_r, control_w = os.pipe()
        report_r, report_w = os.pipe()
        with tempfile.TemporaryDirectory(prefix='jobs-', dir=ROOT / '.build') as dotdir:
            pid, terminal = pty.fork()
            if pid == 0:
                os.close(control_w); os.close(report_r)
                os.set_inheritable(control_r, True); os.set_inheritable(report_w, True)
                fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
                os.environ.update(TERM='xterm-256color', LC_ALL='C.UTF-8', ZDOTDIR=dotdir,
                                  PS1='ZDRAW_PROMPT> ', PS2='MORE> ')
                os.execl(ZSH, ZSH, '-dfi', '+o', 'zle')
            os.close(control_r); os.close(report_w)
            pending, screen = bytearray(), bytearray()
            app, reaped = None, False
            def drain(fd):
                try:
                    data = os.read(fd, 65536)
                except OSError as exc:
                    if fd != terminal or exc.errno != errno.EIO:
                        raise
                    data = b''
                if fd == terminal:
                    screen.extend(data)
                else:
                    self.assertTrue(data, bytes(screen[-4000:]))
                    pending.extend(data)
            def line():
                deadline = time.monotonic() + 10
                while b'\n' not in pending:
                    remain = deadline - time.monotonic()
                    self.assertGreater(remain, 0, bytes(screen[-4000:]))
                    for fd in select.select([terminal, report_r], [], [], remain)[0]:
                        drain(fd)
                result, _, rest = pending.partition(b'\n'); pending[:] = rest
                return result
            def shell_foreground():
                deadline = time.monotonic() + 5
                while os.tcgetpgrp(terminal) != pid:
                    self.assertLess(time.monotonic(), deadline, bytes(screen[-4000:]))
                    for fd in select.select([terminal], [], [], 0.02)[0]:
                        drain(fd)
            try:
                # Outer shell has job control but no line-editor terminal modes.
                command = (f'unsetopt zle; {shlex.quote(ZSH)} -df '
                           f'{shlex.quote(str(ROOT / "tests/job-control.zsh"))} {report_w} {control_r}\n')
                os.write(terminal, command.encode())
                ready = line().split()
                self.assertEqual(ready[0], b'ready', bytes(screen[-4000:]))
                app = int(ready[1])
                self.assertEqual(os.tcgetpgrp(terminal), app)
                os.kill(app, signal.SIGTSTP)
                self.assertEqual(line(), b'suspended')
                shell_foreground()
                suspended = termios.tcgetattr(terminal)
                self.assertTrue(suspended[3] & termios.ICANON)
                os.write(terminal, b'bg\n')
                os.write(control_w, b'wake\n')
                self.assertEqual(line(), b'background')
                shell_foreground()
                self.assertEqual(termios.tcgetattr(terminal), suspended)
                # The outer shell's second stop notification closes the race between
                # the application's report and its following SIGSTOP.
                deadline = time.monotonic() + 5
                while screen.count(b'suspended (signal)') < 2:
                    self.assertLess(time.monotonic(), deadline, bytes(screen[-4000:]))
                    for fd in select.select([terminal], [], [], 0.02)[0]:
                        drain(fd)
                os.write(terminal, b'fg\n')
                self.assertEqual(line(), b'foreground')
                self.assertEqual(line(), b'done')
                shell_foreground()
                self.assertEqual(termios.tcgetattr(terminal), suspended)
                os.write(terminal, b'exit\n')
                _, status = os.waitpid(pid, 0); reaped = True
                self.assertEqual(os.waitstatus_to_exitcode(status), 0, bytes(screen[-4000:]))
            finally:
                if not reaped:
                    if app:
                        try:
                            os.kill(app, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                    os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0)
                for fd in (control_w, report_r, terminal):
                    os.close(fd)
