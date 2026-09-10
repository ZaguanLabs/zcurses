#!/usr/bin/env python3
"""Capture raw text and native cells on private Xvfb terminals; opt-in probe."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import select
import shlex
import shutil
import subprocess
import sys
import tempfile
import termios
import time
import tty

ROOT = Path(__file__).resolve().parents[2]


def wait_capture(directory, phase):
    (directory / 'phase').write_text(phase)
    deadline = time.monotonic() + 15
    while not (directory / (phase + '.ack')).exists():
        if time.monotonic() > deadline:
            raise RuntimeError('capture acknowledgement timeout')
        time.sleep(.02)


def probe(directory):
    cases = json.loads((ROOT / 'tests/unicode/corpus.json').read_text())
    (directory / 'corpus.tsv').write_text(''.join(c['name'] + '\t' + c['text'] + '\n' for c in cases))
    original = termios.tcgetattr(0)
    records = []
    try:
        tty.setraw(0)
        os.write(1, b'\x1b[2J\x1b[H\x1b[?25lRAW TEXT | emulator cursor report | marker follows source bytes')
        for row, case in enumerate(cases, 3):
            os.write(1, f'\x1b[{row};1H{case["name"]}\x1b[{row};25H'.encode() + case['text'].encode() + b'|\x1b[6n')
            reply = bytearray()
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline and not reply.endswith(b'R'):
                if select.select([0], [], [], max(0, deadline-time.monotonic()))[0]:
                    reply.extend(os.read(0, 1))
            match = re.fullmatch(rb'\x1b\[(\d+);(\d+)R', reply)
            records.append(dict(name=case['name'], cursor_reply=reply.hex(),
                                raw_columns=int(match[2])-26 if match and int(match[1]) == row else None))
        (directory / 'raw.json').write_text(json.dumps(records, indent=2))
        wait_capture(directory, 'raw')
    finally:
        os.write(1, b'\x1b[?25h')
        termios.tcsetattr(0, termios.TCSANOW, original)
    os.mkfifo(directory / 'ack')
    result = subprocess.run([str(ROOT / '.build/zsh/Src/zsh'), '-df',
                             str(ROOT / 'scripts/portability/unicode-source.zsh'), str(directory)], stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace'))


def version(backend):
    flag = '-V' if backend == 'tmux' else '-version' if backend == 'xterm' else '--version'
    return subprocess.check_output([backend, flag], stderr=subprocess.STDOUT, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--captures', type=Path)
    parser.add_argument('--probe', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.probe:
        try:
            probe(args.probe)
        except Exception:
            import traceback
            (args.probe / 'error').write_text(traceback.format_exc())
            raise
        return
    if not args.output or not args.captures:
        parser.error('--output and --captures are required')
    for program in ('Xvfb', 'xterm', 'import'):
        if not shutil.which(program):
            parser.error(f'{program} unavailable')
    args.captures.mkdir(parents=True, exist_ok=True)
    records = dict(format='zdraw-unicode-matrix-1', platform=platform.platform(), locale='C.UTF-8',
                   unicode_version='17.0.0', font='monospace (fontconfig fallback); xterm size 12, kitty size 12',
                   shell=subprocess.check_output([str(ROOT / '.build/zsh/Src/zsh'), '--version'], text=True).strip(), scenarios=[])
    rr, rw = os.pipe()
    xvfb = subprocess.Popen(['Xvfb', '-displayfd', str(rw), '-screen', '0', '1200x900x24', '-nolisten', 'tcp'],
                            pass_fds=(rw,), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.close(rw)
    try:
        if not select.select([rr], [], [], 5)[0]:
            raise RuntimeError('Xvfb startup timeout')
        display = ':' + os.read(rr, 64).decode().strip()
        with tempfile.TemporaryDirectory(prefix='unicode-matrix-', dir=ROOT / '.build') as tmp:
            for backend in ('xterm', 'tmux', 'screen', 'kitty'):
                if not shutil.which(backend):
                    records['scenarios'].append(dict(backend=backend, tested=False, reason='executable unavailable'))
                    continue
                directory = Path(tmp) / backend
                directory.mkdir()
                command = [sys.executable, str(Path(__file__).resolve()), '--probe', str(directory)]
                session = f'zdraw-unicode-{os.getpid()}'
                env = os.environ.copy()
                for key in ('TERM', 'TERMINFO', 'TERMINFO_DIRS', 'LINES', 'COLUMNS', 'TMUX', 'STY'):
                    env.pop(key, None)
                env.update(DISPLAY=display, LC_ALL='C.UTF-8', LIBGL_ALWAYS_SOFTWARE='1')
                if backend == 'kitty':
                    launch = ['kitty', '-c', 'NONE', '-o', 'linux_display_server=x11', '-o', 'font_family=monospace',
                              '-o', 'font_size=12', '-o', 'initial_window_width=1100', '-o', 'initial_window_height=800',
                              '-o', 'cursor_blink_interval=0', *command]
                else:
                    if backend == 'tmux':
                        command = ['tmux', '-L', session, '-f', '/dev/null', 'new-session', shlex.join(command)]
                    elif backend == 'screen':
                        command = ['screen', '-c', '/dev/null', '-S', session, *command]
                    launch = ['xterm', '-display', display, '-geometry', '90x25', '-fa', 'monospace', '-fs', '12',
                              '-xrm', 'XTerm*cursorBlink: false', '-e', *command]
                process = subprocess.Popen(launch, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                seen, captures = set(), {}
                try:
                    deadline = time.monotonic() + 65
                    while process.poll() is None:
                        if time.monotonic() > deadline:
                            raise RuntimeError(f'{backend}: rendering probe timeout')
                        if (directory / 'error').exists():
                            raise RuntimeError((directory / 'error').read_text())
                        phase = (directory / 'phase').read_text().strip() if (directory / 'phase').exists() else ''
                        if phase and phase not in seen:
                            seen.add(phase)
                            time.sleep(.2)
                            destination = args.captures / f'{backend}-{phase}.png'
                            subprocess.run(['import', '-display', display, '-window', 'root', str(destination.resolve())],
                                           env=env, check=True, timeout=5)
                            captures[phase] = dict(file=destination.name, sha256=hashlib.sha256(destination.read_bytes()).hexdigest())
                            if phase == 'native':
                                fd = os.open(directory / 'ack', os.O_WRONLY | os.O_NONBLOCK)
                                os.write(fd, b'continue\n')
                                os.close(fd)
                            else:
                                (directory / (phase + '.ack')).touch()
                        time.sleep(.02)
                    stdout, stderr = process.communicate()
                    if process.returncode or seen != {'raw', 'native'}:
                        detail = (directory / 'error').read_text() if (directory / 'error').exists() else ''
                        raise RuntimeError(f'{backend}: {detail} {stderr.decode()}')
                    native = {}
                    for line in (directory / 'native.tsv').read_text().splitlines():
                        name, key, value = line.split('\t')
                        native.setdefault(name, {})[key] = int(value)
                    snapshot = dict(line.split('\t', 1) for line in (directory / 'snapshot.tsv').read_text().splitlines())
                    evidence = []
                    for row, item in enumerate(json.loads((directory / 'raw.json').read_text()), 2):
                        values = native[item['name']]
                        width = values['width']
                        values['stored_cells'] = ([snapshot.get(f'{row},{col},text', '') for col in range(24, 24+width)]
                                                  if values.get('draw_status') == 0 else None)
                        if values['query_status']:
                            values['width'] = None
                        evidence.append({**item, **values})
                    records['scenarios'].append(dict(backend=backend, version=version(backend), tested=True,
                                                       captures=captures, evidence=evidence))
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
                    if backend == 'tmux':
                        subprocess.run(['tmux', '-L', session, 'kill-server'], capture_output=True)
                    elif backend == 'screen':
                        subprocess.run(['screen', '-S', session, '-X', 'quit'], capture_output=True)
    finally:
        os.close(rr)
        xvfb.terminate()
        xvfb.wait(timeout=5)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(records, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
