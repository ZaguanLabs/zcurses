#!/usr/bin/env python3
"""Measure complete design-study redraws; excludes readback and emulator paint."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests'))
from test_compositions import RecipeSession
from test_design_study import DesignStudyTests
from test_linked_detail import LinkedDetailTests
from test_change_gutter import ChangeGutterTests
from test_status_strip import StatusStripTests
import test_features


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trials', type=int, default=3)
    parser.add_argument('--frames', type=int, default=20)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--example', choices=('design-study', 'linked-detail', 'change-gutter', 'status-strip'), default='design-study')
    args = parser.parse_args()
    if not 1 <= args.trials <= 20 or not 2 <= args.frames <= 500:
        parser.error('use 1..20 trials and 2..500 frames')
    # Fixture capture is intentionally outside the timed path and unnecessary here.
    os.environ.pop('ZDRAW_STUDY_CAPTURE', None)
    linked = args.example == 'linked-detail'
    gutter = args.example == 'change-gutter'
    status = args.example == 'status-strip'
    component = linked or gutter or status
    record = dict(format=f'zdraw-{args.example}-benchmark-1', platform=platform.platform(),
                  measured_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  source_sha256=hashlib.sha256((ROOT / f'examples/{args.example}.zsh').read_bytes()).hexdigest(),
                  module_sha256=hashlib.sha256((ROOT / '.build/modules/zdraw.so').read_bytes()).hexdigest(),
                  shell=subprocess.check_output([test_features.ZSH, '--version'], text=True).strip(),
                  term='xterm-256color', locale='C.UTF-8', trials=args.trials,
                  frames_per_trial=args.frames, warmup_frames=4, scenarios=[])
    if component:
        record['component_sha256'] = hashlib.sha256((ROOT / f'examples/components/{args.example}.zsh').read_bytes()).hexdigest()
    case = StatusStripTests() if status else ChangeGutterTests() if gutter else LinkedDetailTests() if linked else DesignStudyTests()
    for size in ((32, 120), (20, 44)):
        designs = ('status' if status else 'gutter' if gutter else 'flat',) if component else ('quiet', 'workbench', 'expressive')
        for design in designs:
            samples, calls = [], []
            for trial in range(args.trials):
                session = RecipeSession(case, 'dark' if component else design, fixture=f'{args.example}.zsh')
                try:
                    session.advance()
                    session.advance(size=size)
                    if size[1] < 78 and not (gutter or status):
                        session.advance(b'\t')
                    current = []
                    for index in range(args.frames + 4):
                        key = (b'1' if index % 6 == 0 else b' ') if status else (b'j' if index % 2 == 0 else b'k')
                        frame = session.advance(key)
                        if index >= 4:
                            current.append(float(frame[10 if gutter or status else 13 if linked else 12]))
                            if not component:
                                calls.append(int(frame[13]))
                    samples.append(current)
                    case.finish(session)
                finally:
                    session.close()
            flat = sorted(value for trial in samples for value in trial)
            record['scenarios'].append(dict(design=design, rows=size[0], columns=size[1],
                interaction='status/progress updates' if status else ('redraw' if size[1] >= 78 else 'vertical scroll') if gutter else ('selection' if size[1] >= 78 else 'detail scroll'),
                median_ms=round(statistics.median(flat), 3),
                p95_ms=round(flat[max(0, (95 * len(flat) + 99) // 100 - 1)], 3),
                samples_ms=samples))
            if calls:
                record['scenarios'][-1].update(calls_min=min(calls), calls_max=max(calls))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2) + '\n')
    for scenario in record['scenarios']:
        print(f"{scenario['design']:11} {scenario['columns']}x{scenario['rows']}: "
              f"median {scenario['median_ms']:.3f} ms, p95 {scenario['p95_ms']:.3f} ms")


if __name__ == '__main__':
    main()
