"""Passive evidence, opt-in replies, slow transport, ownership and cleanup."""
import errno
import fcntl
import os
import pty
import select
import signal
import struct
import tempfile
import termios
import threading
import time
import unittest
import test_features

ROOT, ZSH = test_features.ROOT, test_features.ZSH


class CapabilityTests(unittest.TestCase):
    def test_passive_records(self):
        self.assertEqual(test_features.FeatureTests().run_shell('''
            zmodload zdraw || exit 1
            typeset -A info
            typeset -Ar frozen=(sentinel yes)
            zdraw capabilities frozen 2>/dev/null && exit 2
            inspect() {
                local -A info
                local sync_compiled=no
                (( ${zdraw_features[(Ie)synchronized_output]} )) && sync_compiled=yes
                zdraw capabilities info synchronized_output=yes || return 3
                [[ $info[format] == zdraw-capabilities-1 && $info[session] == inactive &&
                   $info[colors,support] == unknown && $info[colors,source] == none &&
                   $info[synchronized_output,source] == override &&
                   $info[synchronized_output,evidence_support] == unknown &&
                   $info[synchronized_output,enabled] == no &&
                   $info[synchronized_output,compiled] == $sync_compiled ]] || return 4
                read -r line || return 5
                [[ $line == unchanged ]] || return 6
            }
            inspect <<<'unchanged' || exit 7
            zdraw capabilities info || exit 8
            [[ $info[synchronized_output,source] == none ]] || exit 9
            for bad in absent=yes colors=auto 'colors=$(touch nope)' colors; do
                zdraw capabilities info "$bad" && exit 10
            done
            [[ $info[format] == zdraw-capabilities-1 ]] || exit 11
            (( ${#zdraw_windows} == 0 )) || exit 12
        '''), '')

    def session(self, mode='native', modules=None):
        control_r, control_w = os.pipe()
        report_r, report_w = os.pipe()
        pid, terminal = pty.fork()
        if pid == 0:
            os.close(control_w); os.close(report_r)
            os.set_inheritable(control_r, True); os.set_inheritable(report_w, True)
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
            os.environ.update(TERM='xterm-256color', LC_ALL='C.UTF-8')
            os.environ.pop('LINES', None); os.environ.pop('COLUMNS', None)
            os.execl(ZSH, ZSH, '-df', str(ROOT / 'tests/capabilities.zsh'),
                     str(modules or ROOT / '.build/modules'), mode, str(report_w), str(control_r))
        os.close(control_r); os.close(report_w)
        pending, screen = bytearray(), bytearray()
        reaped, original, timers = False, None, []
        try:
            while True:
                deadline = time.monotonic() + 10
                while b'\n' not in pending:
                    remaining = deadline - time.monotonic()
                    self.assertGreater(remaining, 0, bytes(screen[-4000:]))
                    for fd in select.select([terminal, report_r], [], [], remaining)[0]:
                        try:
                            data = os.read(fd, 65536)
                        except OSError as exc:
                            if fd != terminal or exc.errno != errno.EIO:
                                raise
                            data = b''
                        if fd == report_r:
                            self.assertTrue(data, bytes(screen[-4000:]))
                            pending.extend(data)
                        else:
                            screen.extend(data)
                step, _, rest = pending.partition(b'\n'); pending[:] = rest
                if step == b'done':
                    break
                if step == b'baseline':
                    original = termios.tcgetattr(terminal)
                elif step.startswith(b'report-'):
                    os.write(terminal, b'\x1b[?2026;' + step[-1:] + b'$y')
                elif step == b'rollback':
                    os.write(terminal, b'\x1b[?2004;0$y')
                elif step == b'malformed':
                    os.write(terminal, b'\x1b[?2026;9$yXY')
                elif step == b'slow-prefix':
                    os.write(terminal, b'\x1b[')
                    timer = threading.Timer(0.08, os.write, args=(terminal, b'?1004;2$y'))
                    timers.append(timer); timer.start()
                elif step == b'unsolicited':
                    self.assertNotIn(b'\x1b[?2004$p', screen)
                    os.write(terminal, b'\x1b[?2004;1$y')
                elif step == b'fragmented':
                    os.write(terminal, b'A\x1b[')
                    for delay, data in ((0.03, b'?2004;'), (0.09, b'2$'), (0.15, b'y\x1bOA')):
                        timer = threading.Timer(delay, os.write, args=(terminal, data))
                        timers.append(timer); timer.start()
                elif step == b'timeout':
                    # Deliberately no response, like an unresponsive remote peer.
                    pass
                elif step == b'late':
                    os.write(terminal, b'\x1b[?1004;2$y\x1b[200~\x1b[?2026;1$y\x1b[201~')
                elif step == b'suspended':
                    self.assertEqual(termios.tcgetattr(terminal), original)
                elif step == b'resumed':
                    os.write(terminal, b'\x1b[?2026;2$y')
                elif step == b'off':
                    os.write(terminal, b'Z')
                else:
                    self.fail(step)
                if step not in (b'resumed', b'off'):
                    self.assertNotIn(b'UNPRESENTED', screen)
                os.write(control_w, b'continue\n')
            _, status = os.waitpid(pid, 0); reaped = True
            self.assertEqual(os.waitstatus_to_exitcode(status), 0, bytes(screen[-4000:]))
            self.assertEqual(termios.tcgetattr(terminal), original)
        finally:
            for timer in timers:
                timer.join()
            if not reaped:
                os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0)
            for fd in (control_w, report_r, terminal):
                os.close(fd)

    def test_query_lifecycle_and_delayed_transport(self):
        self.session()

    def test_report_values_and_incomplete_sequences(self):
        self.session('reports')

    def test_queries_without_optional_support(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text().replace(
            '#include <stdio.h>', '#include <stdio.h>\n#undef HAVE_CLOCK_GETTIME', 1)
        with tempfile.TemporaryDirectory(prefix='queries-optional-', dir=ROOT / '.build') as tmp:
            modules = test_features.FeatureTests().variant(tmp, source)
            self.session('unavailable', modules)

    def test_partial_registration_failure(self):
        source = (ROOT / 'Src/Modules/zdraw.c').read_text()
        before = 'code == KEY_MAX + 257 || define_key(sequence, code) == ERR'
        self.assertIn(before, source)
        source = source.replace(before, 'code == KEY_MAX + 257 || i == 7 || define_key(sequence, code) == ERR', 1)
        with tempfile.TemporaryDirectory(prefix='query-registration-', dir=ROOT / '.build') as tmp:
            modules = test_features.FeatureTests().variant(tmp, source)
            self.session('registration_failure', modules)
