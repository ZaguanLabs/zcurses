#!/usr/bin/env python3
"""Measure component work, curses staging and presentation in a drained PTY."""
import argparse
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import pty
import select
import signal
import statistics
import struct
import subprocess
import termios
import time

ROOT = Path(__file__).resolve().parent.parent
WORKLOADS = ('chart', 'canvas', 'form', 'document', 'surfaces', 'spans', 'prepared')


def trial(workload, pattern, size, frames, root=ROOT, zprof=None):
    report_r, report_w = os.pipe()
    ack_r, ack_w = os.pipe()
    pid, terminal = pty.fork()
    if pid == 0:
        os.close(report_r)
        os.close(ack_w)
        os.set_inheritable(report_w, True)
        os.set_inheritable(ack_r, True)
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        os.environ.update(TERM='xterm-256color', LC_ALL=os.environ.get('ZDRAW_TEST_LOCALE', 'C.UTF-8'))
        os.environ.pop('LINES', None)
        os.environ.pop('COLUMNS', None)
        os.environ['ZDRAW_BENCH_ROOT'] = str(root)
        os.environ.pop('ZDRAW_BENCH_ZPROF', None)
        if zprof:
            os.environ['ZDRAW_BENCH_ZPROF'] = str(zprof)
        shell = str(ROOT / '.build/zsh/Src/zsh')
        os.execl(shell, shell, '-df', str(ROOT / 'benchmarks/components.zsh'),
                 str(root / '.build/modules'), workload, pattern, size, str(frames), str(report_w), str(ack_r))
    os.close(report_w)
    os.close(ack_r)
    report, output = bytearray(), bytearray()
    watched = [terminal, report_r]
    deadline = time.monotonic() + 120
    reaped, peak = False, None
    try:
        while watched:
            if time.monotonic() >= deadline:
                raise RuntimeError('component benchmark timed out')
            for fd in select.select(watched, [], [], 1)[0]:
                try:
                    data = os.read(fd, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    data = b''
                (report if fd == report_r else output).extend(data)
                if not data:
                    watched.remove(fd)
                    if fd == report_r:
                        try:
                            for line in Path(f'/proc/{pid}/status').read_text().splitlines():
                                if line.startswith('VmHWM:'):
                                    peak = int(line.split()[1])
                        except (OSError, ValueError):
                            pass
                        try:
                            os.write(ack_w, b'continue\n')
                        except BrokenPipeError:
                            pass
        _, status = os.waitpid(pid, 0)
        reaped = True
        if os.waitstatus_to_exitcode(status):
            raise RuntimeError(output.decode(errors='replace'))
        header, snapshot = bytes(report).split(b'SNAPSHOT\n', 1)
        lines = header.decode().splitlines()
        work, stage, present = [float(v) * 1000 / frames for v in lines[0].split()]
        return dict(work_ms=work, stage_ms=stage, present_ms=present,
                    output_bytes=len(output), peak_rss_kib=peak,
                    output_sha256=hashlib.sha256(output).hexdigest(),
                    snapshot_sha256=hashlib.sha256(snapshot).hexdigest(),
                    resources=dict(line.split('=', 1) for line in lines[1:]))
    finally:
        if not reaped:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)
        for fd in (report_r, terminal, ack_w):
            os.close(fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trials', type=int, default=5)
    parser.add_argument('--frames', type=int, default=20)
    parser.add_argument('--workloads', nargs='+', choices=WORKLOADS, default=WORKLOADS)
    parser.add_argument('--label', default='working-tree')
    parser.add_argument('--baseline-root', type=Path,
                        help='alternate with a checkout containing lib/ and .build/modules/')
    parser.add_argument('--zprof-dir', type=Path,
                        help='write function profiles; requires matching staged zsh/zprof')
    args = parser.parse_args()
    if not 1 <= args.trials <= 20 or not 1 <= args.frames <= 1000:
        parser.error('trials must be 1..20 and frames 1..1000')
    cases = [(w, p, s) for w in args.workloads for p in ('repeated', 'changing') for s in ('small', 'large')]
    samples = {case: [] for case in cases}
    baseline = {case: [] for case in cases}
    if args.zprof_dir:
        if args.baseline_root:
            parser.error('profile and timing comparisons must be separate runs')
        args.zprof_dir.mkdir(parents=True, exist_ok=True)
    for run in range(args.trials):
        for case in (cases if run % 2 == 0 else list(reversed(cases))):
            runs = [(ROOT, samples)]
            if args.baseline_root:
                runs.append((args.baseline_root.resolve(), baseline))
                if run % 2:
                    runs.reverse()
            profile = args.zprof_dir / f'{"-".join(case)}-{run}.txt' if args.zprof_dir else None
            for root, destination in runs:
                destination[case].append(trial(*case, args.frames, root=root, zprof=profile))
    results = []
    for (workload, pattern, size), values in samples.items():
        if len({v['snapshot_sha256'] for v in values}) != 1:
            raise RuntimeError(f'unstable snapshot: {workload} {pattern} {size}')
        results.append(dict(workload=workload, pattern=pattern, size=size,
                            medians={key: statistics.median(v[key] for v in values)
                                     for key in ('work_ms', 'stage_ms', 'present_ms', 'output_bytes')},
                            samples=values))
        if args.baseline_root:
            old = baseline[workload, pattern, size]
            for field in ('snapshot_sha256', 'output_sha256', 'output_bytes', 'resources'):
                if any(v[field] != values[0][field] for v in [*old, *values]):
                    raise RuntimeError(f'baseline mismatch: {workload} {pattern} {size} {field}')
            results[-1]['baseline_samples'] = old
            results[-1]['baseline_medians'] = {
                key: statistics.median(v[key] for v in old)
                for key in ('work_ms', 'stage_ms', 'present_ms', 'output_bytes')}
    print(json.dumps(dict(label=args.label, platform=platform.platform(),
                          shell=subprocess.check_output([str(ROOT / '.build/zsh/Src/zsh'), '--version'], text=True).strip(),
                          locale=os.environ.get('ZDRAW_TEST_LOCALE', 'C.UTF-8'), terminal='xterm-256color',
                          frames=args.frames, trials=args.trials,
                          instrumented=bool(args.zprof_dir),
                          note='Work includes shell and native calls; stage and present are separate. Output counts the entire session. No emulator paint measurement. RSS is whole-shell Linux VmHWM, null when unavailable.',
                          results=results), indent=2))


if __name__ == '__main__':
    main()
