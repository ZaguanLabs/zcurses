#!/usr/bin/env python3
"""Check wire output around pad input; pass a separately compiled probe binary."""
import argparse
import errno
import fcntl
import json
import os
import pty
import select
import signal
import struct
import termios
import time


def run(binary, wide):
    rr, rw = os.pipe()
    cr, cw = os.pipe()
    pid, terminal = pty.fork()
    if pid == 0:
        os.close(rr); os.close(cw)
        os.set_inheritable(rw, True); os.set_inheritable(cr, True)
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        os.environ.pop('TERMINFO', None); os.environ.pop('TERMINFO_DIRS', None)
        os.environ.update(TERM='xterm-256color', LC_ALL='C.UTF-8')
        os.execl(binary, binary, str(rw), str(cr), str(int(wide)))
    os.close(rw); os.close(cr)
    pending, screen, reaped = bytearray(), bytearray(), False
    original = termios.tcgetattr(terminal)
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
            if not data:
                raise RuntimeError(f'probe EOF: {bytes(screen)!r}')
            pending.extend(data)
    try:
        for expected in (b'polled', b'read', b'presented'):
            deadline = time.monotonic() + 5
            while b'\n' not in pending:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise RuntimeError('probe timeout')
                for fd in select.select([rr, terminal], [], [], remaining)[0]:
                    drain(fd)
            phase, _, rest = pending.partition(b'\n'); pending[:] = rest
            if phase != expected:
                raise RuntimeError(f'unexpected phase {phase!r}')
            while select.select([terminal], [], [], 0)[0]:
                drain(terminal)
            if (b'UNPRESENTED_PAD_FRAME' in screen) != (phase == b'presented'):
                raise RuntimeError(f'frame visibility at {phase!r}: {bytes(screen)!r}')
            if phase == b'polled':
                os.write(terminal, b'K')
            os.write(cw, b'ack\n')
        _, status = os.waitpid(pid, 0); reaped = True
        if status or termios.tcgetattr(terminal) != original:
            raise RuntimeError(f'exit or termios failure: {status}')
        return dict(input='wide' if wide else 'byte', poll_no_frame=True,
                    key_no_frame=True, explicit_present=True, termios_restored=True)
    finally:
        if not reaped:
            os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0)
        for fd in (rr, cw, terminal):
            os.close(fd)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary')
    args = parser.parse_args()
    print(json.dumps([run(os.path.abspath(args.binary), wide) for wide in (False, True)], indent=2))
