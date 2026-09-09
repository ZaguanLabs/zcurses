#!/usr/bin/env python3
"""Compare equivalent 20x64 uniform rectangle fills in a controlled PTY."""
import argparse
import json
import statistics
from spans import trial


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trials', type=int, default=7)
    parser.add_argument('--frames', type=int, default=500)
    args = parser.parse_args()
    if args.trials < 1 or args.frames < 1:
        parser.error('trials and frames must be positive')
    backends = ('rows', 'prepared', 'fill')
    results = {}
    for scenario in ('draw', 'refresh'):
        samples = {backend: [] for backend in backends}
        sizes = {backend: set() for backend in backends}
        for run in range(args.trials):
            for backend in (backends if run % 2 == 0 else tuple(reversed(backends))):
                elapsed, size = trial(backend, scenario, args.frames, 'fill.zsh')
                samples[backend].append(elapsed * 1000 / args.frames)
                sizes[backend].add(size)
        results[scenario] = {
            backend: {'median_ms_per_frame': statistics.median(samples[backend]),
                      'min_ms_per_frame': min(samples[backend]),
                      'max_ms_per_frame': max(samples[backend]),
                      'terminal_bytes_including_setup': sorted(sizes[backend])}
            for backend in backends
        }
        results[scenario]['speedup_over_rows'] = statistics.median(samples['rows']) / statistics.median(samples['fill'])
        results[scenario]['speedup_over_prepared'] = statistics.median(samples['prepared']) / statistics.median(samples['fill'])
    print(json.dumps({'frames': args.frames, 'trials': args.trials,
                      'rows': 20, 'columns': 64, 'TERM': 'xterm-256color',
                      'locale': 'C', 'results': results}, indent=2))


if __name__ == '__main__':
    main()
