#!/usr/bin/env python3
"""Capture real xterm and isolated tmux/screen mode-report evidence under Xvfb."""
import argparse
import json
import os
from pathlib import Path
import platform
import select
import shlex
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def version(command):
    return subprocess.check_output(command, stderr=subprocess.STDOUT, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    for program in ('Xvfb', 'xterm'):
        if not shutil.which(program):
            parser.error(f'{program} is required')
    records = dict(format='zdraw-terminal-matrix-1', platform=platform.platform(),
                   xterm=version(['xterm', '-version']), scenarios=[])
    rr, rw = os.pipe()
    server = subprocess.Popen(['Xvfb', '-displayfd', str(rw), '-screen', '0', '800x600x24', '-nolisten', 'tcp'],
                              pass_fds=(rw,), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.close(rw)
    try:
        if not select.select([rr], [], [], 10)[0]:
            raise RuntimeError('Xvfb startup timeout')
        display = ':' + os.read(rr, 64).decode().strip()
        with tempfile.TemporaryDirectory(prefix='terminal-matrix-', dir=ROOT / '.build') as tmp:
            for backend in ('direct', 'tmux', 'screen'):
                if backend != 'direct' and not shutil.which(backend):
                    records['scenarios'].append(dict(backend=backend, tested=False, reason='executable unavailable'))
                    continue
                output = Path(tmp) / f'{backend}.tsv'
                command = [str(ROOT / '.build/zsh/Src/zsh'), '-df',
                           str(ROOT / 'scripts/portability/terminal.zsh'), str(output)]
                session = f'zdraw-matrix-{os.getpid()}-{backend}'
                record = dict(backend=backend, tested=True, transport='local PTY')
                if backend == 'tmux':
                    record['version'] = version(['tmux', '-V'])
                    command = ['tmux', '-L', session, '-f', '/dev/null', 'new-session', shlex.join(command)]
                elif backend == 'screen':
                    record['version'] = version(['screen', '--version'])
                    command = ['screen', '-c', '/dev/null', '-S', session, *command]
                env = os.environ.copy()
                for key in ('TMUX', 'STY', 'TERMINFO', 'TERMINFO_DIRS', 'LINES', 'COLUMNS'):
                    env.pop(key, None)
                env.update(LC_ALL='C.UTF-8', DISPLAY=display)
                try:
                    result = subprocess.run(['xterm', '-display', display, '-geometry', '80x24', '-e', *command],
                                            env=env, capture_output=True, text=True, timeout=20)
                    if result.returncode or not output.exists():
                        raise RuntimeError(f'{backend}: exit {result.returncode}: {result.stderr}')
                    record['evidence'] = dict(line.split('\t', 1) for line in output.read_text().splitlines())
                finally:
                    if backend == 'tmux':
                        subprocess.run(['tmux', '-L', session, 'kill-server'], capture_output=True)
                    elif backend == 'screen':
                        subprocess.run(['screen', '-S', session, '-X', 'quit'], capture_output=True)
                records['scenarios'].append(record)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(records, indent=2) + '\n')
    finally:
        os.close(rr)
        server.terminate()
        server.wait(timeout=5)


if __name__ == '__main__':
    main()
