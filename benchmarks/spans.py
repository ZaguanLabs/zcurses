#!/usr/bin/env python3
"""Compare equal 20-row, eight-span frames in a controlled 24x80 PTY."""
import argparse
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import statistics
import struct
import termios
import time

ROOT = Path(__file__).resolve().parents[1]


def trial(backend, scenario, frames):
    read_fd, write_fd = os.pipe()
    os.set_inheritable(write_fd, True)
    pid, terminal = pty.fork()
    if pid == 0:
        os.close(read_fd)
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        os.environ.update(TERM='xterm-256color', LC_ALL='C')
        os.environ.pop('LINES', None)
        os.environ.pop('COLUMNS', None)
        shell = str(ROOT / '.build/zsh/Src/zsh')
        os.execl(shell, shell, '-df', str(ROOT / 'benchmarks/spans.zsh'),
                 str(ROOT / '.build/modules'), backend, scenario, str(frames), str(write_fd))
    os.close(write_fd)
    screen, report = bytearray(), bytearray()
    streams = {terminal: screen, read_fd: report}
    reaped = False
    try:
        deadline = time.monotonic() + 60
        while streams:
            if time.monotonic() >= deadline:
                raise TimeoutError('benchmark trial exceeded 60 seconds')
            for fd in select.select(list(streams), [], [], 0.1)[0]:
                try:
                    data = os.read(fd, 65536)
                except OSError as exc:
                    if exc.errno != errno.EIO or fd != terminal:
                        raise
                    data = b''
                if data:
                    streams[fd].extend(data)
                else:
                    del streams[fd]
        _, result = os.waitpid(pid, 0)
        reaped = True
        if os.waitstatus_to_exitcode(result) != 0:
            raise RuntimeError(screen.decode(errors='replace'))
        return float(report), len(screen)
    finally:
        if not reaped:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        os.close(read_fd)
        os.close(terminal)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trials', type=int, default=7)
    parser.add_argument('--frames', type=int, default=500)
    args = parser.parse_args()
    if args.trials < 1 or args.frames < 1:
        parser.error('trials and frames must be positive')
    results = {}
    for scenario in ('draw', 'refresh'):
        samples = {backend: [] for backend in ('legacy', 'spans')}
        sizes = {backend: set() for backend in samples}
        for run in range(args.trials):
            # Alternate order to reduce drift from load or temperature.
            for backend in (('legacy', 'spans') if run % 2 == 0 else ('spans', 'legacy')):
                elapsed, size = trial(backend, scenario, args.frames)
                samples[backend].append(elapsed * 1000 / args.frames)
                sizes[backend].add(size)
        results[scenario] = {
            backend: {'median_ms_per_frame': statistics.median(samples[backend]),
                      'min_ms_per_frame': min(samples[backend]),
                      'max_ms_per_frame': max(samples[backend]),
                      'terminal_bytes_including_setup': sorted(sizes[backend])}
            for backend in samples
        }
        results[scenario]['median_speedup'] = (
            statistics.median(samples['legacy']) / statistics.median(samples['spans']))
    print(json.dumps({'frames': args.frames, 'trials': args.trials,
                      'rows': 20, 'spans_per_row': 8, 'columns_drawn': 64,
                      'TERM': 'xterm-256color', 'locale': 'C', 'results': results}, indent=2))


if __name__ == '__main__':
    main()
