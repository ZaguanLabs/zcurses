#!/usr/bin/env python3
"""Measure retained canvas compilation/drawing and fresh-shell peak RSS (Unix)."""
import argparse
import errno
import fcntl
import json
import os
from pathlib import Path
import platform
import pty
import select
import signal
import statistics
import struct
import sys
import termios
import time

ROOT = Path(__file__).resolve().parent.parent


def trial(backend, palette, frames, rows, columns):
    report_r, report_w = os.pipe()
    acknowledge_r, acknowledge_w = os.pipe()
    pid, terminal = pty.fork()
    if pid == 0:
        os.close(report_r)
        os.close(acknowledge_w)
        os.set_inheritable(acknowledge_r, True)
        os.set_inheritable(report_w, True)
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', max(rows, 24), max(columns, 80), 0, 0))
        os.environ.update(TERM='xterm-256color', LC_ALL=os.environ.get('ZDRAW_TEST_LOCALE', 'C.UTF-8'))
        for key in ('LINES', 'COLUMNS'):
            os.environ.pop(key, None)
        shell = str(ROOT / '.build/zsh/Src/zsh')
        os.execl(shell, shell, '-df', str(ROOT / 'benchmarks/canvas.zsh'),
                 str(ROOT / '.build/modules'), backend, palette, str(frames), str(rows), str(columns), str(report_w), str(acknowledge_r))
    os.close(report_w)
    os.close(acknowledge_r)
    acknowledged, shell_peak = False, None
    output, report = bytearray(), bytearray()
    watched = [terminal, report_r]
    deadline = time.monotonic() + 120
    reaped = False
    try:
        while watched:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError('canvas benchmark timed out')
            for fd in select.select(watched, [], [], min(remaining, 1))[0]:
                try:
                    data = os.read(fd, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    data = b''
                if not data:
                    watched.remove(fd)
                (report if fd == report_r else output).extend(data)
                if not acknowledged and b'\n' in report:
                    try:
                        for line in Path(f'/proc/{pid}/status').read_text().splitlines():
                            if line.startswith('VmHWM:'):
                                shell_peak = int(line.split()[1])
                    except (OSError, ValueError):
                        pass
                    os.write(acknowledge_w, b'continue\n')
                    acknowledged = True
        _, status, usage = os.wait4(pid, 0)
        reaped = True
        if os.waitstatus_to_exitcode(status):
            raise RuntimeError(output.decode(errors='replace'))
        elapsed, pixels, cells, writes = report.decode().split()
        # Linux/BSD report KiB; macOS reports bytes. This is whole-process RSS.
        rss_kib = usage.ru_maxrss / 1024 if sys.platform == 'darwin' else usage.ru_maxrss
        return {'ms_per_frame': float(elapsed) * 1000 / frames,
                'peak_rss_kib': shell_peak if shell_peak is not None else rss_kib,
                'memory_source': 'proc-vmhwm' if shell_peak is not None else 'wait4-including-launch', 'pixels': int(pixels), 'occupied_cells': int(cells), 'writes': int(writes)}
    finally:
        if not reaped:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)
        os.close(report_r)
        os.close(terminal)
        os.close(acknowledge_w)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trials', type=int, default=3)
    parser.add_argument('--frames', type=int, default=10)
    args = parser.parse_args()
    if not 1 <= args.trials <= 20 or not 1 <= args.frames <= 1000:
        parser.error('trials must be 1..20 and frames 1..1000')
    results = []
    for rows, columns in ((8, 32), (16, 64)):
        for palette in ('ascii', 'braille'):
            backends = ('baseline', 'raster', 'cached', 'rebuild')
            samples = {name: [] for name in backends}
            for run in range(args.trials):
                for backend in (backends if run % 2 == 0 else tuple(reversed(backends))):
                    samples[backend].append(trial(backend, palette, args.frames, rows, columns))
            for backend, values in samples.items():
                results.append({'rows': rows, 'columns': columns, 'palette': palette, 'backend': backend,
                                'median_ms_per_frame': statistics.median(v['ms_per_frame'] for v in values),
                                'range_ms_per_frame': [min(v['ms_per_frame'] for v in values), max(v['ms_per_frame'] for v in values)],
                                'median_peak_rss_kib': statistics.median(v['peak_rss_kib'] for v in values),
                                'memory_source': sorted({v['memory_source'] for v in values}),
                                'pixels': values[0]['pixels'], 'occupied_cells': values[0]['occupied_cells'],
                                'writes': values[0]['writes']})
    print(json.dumps({'platform': platform.platform(), 'frames': args.frames, 'trials': args.trials,
                      'locale': os.environ.get('ZDRAW_TEST_LOCALE', 'C.UTF-8'),
                      'note': 'No refresh in measured frames; RSS is the whole shell when proc-vmhwm is available; wait4 may include launch overhead. Neither measures canvas allocations alone.',
                      'results': results}, indent=2))


if __name__ == '__main__':
    main()
