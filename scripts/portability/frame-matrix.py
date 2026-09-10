#!/usr/bin/env python3
"""Observe native frame pixels through a deliberately paused private PTY relay.

Requires Xvfb, xterm, ImageMagick import; kitty/tmux/screen cases are optional.
All terminals and key input belong to the private display and temporary sessions.
"""
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
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import termios
import time
import tty

ROOT = Path(__file__).resolve().parents[2]
BEGIN, END = b'\x1b[?2026h', b'\x1b[?2026l'


def notify(directory, phase):
    (directory / 'phase').write_text(phase)
    deadline = time.monotonic() + 10
    ack = directory / (phase + '.ack')
    while not ack.exists():
        if time.monotonic() > deadline: raise RuntimeError('screenshot acknowledgement timeout')
        time.sleep(0.01)


def bridge(directory, mode):
    saved = termios.tcgetattr(0)
    size = fcntl.ioctl(0, termios.TIOCGWINSZ, b'\0' * 8)
    cr, cw = os.pipe(); rr, rw = os.pipe()
    pid, master = pty.fork()
    if pid == 0:
        os.close(cw); os.close(rr)
        os.set_inheritable(cr, True); os.set_inheritable(rw, True)
        fcntl.ioctl(0, termios.TIOCSWINSZ, size)
        os.execl(str(ROOT / '.build/zsh/Src/zsh'), 'zsh', '-df',
                 str(ROOT / 'scripts/portability/frame-source.zsh'), mode,
                 str(rw), str(cr), str(directory / 'evidence.tsv'))
    os.close(cr); os.close(rw)
    pending, captured = bytearray(), bytearray()
    capture, reaped = False, False
    tty.setraw(0)

    def output(data):
        with (directory / 'terminal.bin').open('ab') as log:
            log.write(data)
        if capture: captured.extend(data)
        else:
            sys.stdout.buffer.write(data); sys.stdout.buffer.flush()

    try:
        while True:
            ready = select.select([0, master, rr], [], [], 12)[0]
            if not ready: raise RuntimeError('native frame timeout')
            for fd in ready:
                try: data = os.read(fd, 65536)
                except OSError as exc:
                    if fd != master or exc.errno != errno.EIO: raise
                    data = b''
                if fd == 0:
                    if data: os.write(master, data)
                elif fd == master: output(data)
                else:
                    if not data: raise RuntimeError('native frame exited early')
                    pending.extend(data)
            while b'\n' in pending:
                phase, _, rest = pending.partition(b'\n'); pending[:] = rest
                while select.select([master], [], [], 0)[0]:
                    try: data = os.read(master, 65536)
                    except OSError as exc:
                        if exc.errno != errno.EIO: raise
                        break
                    if not data: break
                    output(data)
                if phase == b'done':
                    _, status = os.waitpid(pid, 0); reaped = True
                    if os.waitstatus_to_exitcode(status): raise RuntimeError('native frame failed')
                    return
                if phase == b'unsupported': notify(directory, 'unsupported')
                elif phase == b'staged':
                    notify(directory, 'before')
                    capture = True
                    started = time.monotonic()
                elif phase == b'framed':
                    native_ms = (time.monotonic() - started) * 1000
                    data = bytes(captured)
                    if mode == 'sync' and not (data.startswith(BEGIN) and data.endswith(END)):
                        raise RuntimeError('native synchronization boundary mismatch')
                    split = len(data) // 2
                    sys.stdout.buffer.write(data[:split]); sys.stdout.buffer.flush()
                    partial_started = time.monotonic()
                    notify(directory, 'partial')
                    hold_ms = (time.monotonic() - partial_started) * 1000
                    sys.stdout.buffer.write(data[split:]); sys.stdout.buffer.flush()
                    notify(directory, 'after')
                    (directory / 'wire.json').write_text(json.dumps(dict(
                        bytes=len(data), split=split, producer_interval_ms=round(native_ms, 3),
                        held_output_ms=round(hold_ms, 3))))
                    capture = False
                os.write(cw, b'continue\n')
    finally:
        if not reaped:
            os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0)
        termios.tcsetattr(0, termios.TCSANOW, saved)
        for fd in (cw, rr, master): os.close(fd)


def version(command):
    return subprocess.check_output(command, stderr=subprocess.STDOUT, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--bridge', type=Path, help=argparse.SUPPRESS)
    parser.add_argument('--mode', choices=('plain', 'sync'), default='plain', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.bridge:
        try:
            bridge(args.bridge, args.mode)
        except Exception:
            import traceback
            (args.bridge / 'error').write_text(traceback.format_exc())
            raise
        return
    if not args.output: parser.error('--output is required')
    for program in ('Xvfb', 'xterm', 'import'):
        if not shutil.which(program): parser.error(f'{program} unavailable')
    records = dict(format='zdraw-frame-matrix-1', platform=platform.platform(),
                   transport='local PTY with a paused midpoint', scenarios=[])
    rr, rw = os.pipe()
    xvfb = subprocess.Popen(['Xvfb', '-displayfd', str(rw), '-screen', '0', '1024x768x24', '-nolisten', 'tcp'],
                            pass_fds=(rw,), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.close(rw)
    try:
        if not select.select([rr], [], [], 5)[0]: raise RuntimeError('Xvfb startup timeout')
        display = ':' + os.read(rr, 64).decode().strip()
        with tempfile.TemporaryDirectory(prefix='frame-matrix-', dir=ROOT / '.build') as tmp:
            for backend in ('xterm', 'tmux', 'screen', 'kitty'):
                if not shutil.which(backend):
                    records['scenarios'].append(dict(backend=backend, tested=False, reason='executable unavailable'))
                    continue
                for mode in ('plain', 'sync'):
                    directory = Path(tmp) / f'{backend}-{mode}'; directory.mkdir()
                    command = [sys.executable, str(Path(__file__).resolve()), '--bridge', str(directory), '--mode', mode]
                    session = f'zdraw-frame-{os.getpid()}-{mode}'
                    env = os.environ.copy()
                    for key in ('TERM', 'TERMINFO', 'TERMINFO_DIRS', 'LINES', 'COLUMNS', 'TMUX', 'STY'):
                        env.pop(key, None)
                    env.update(DISPLAY=display, LC_ALL='C.UTF-8', LIBGL_ALWAYS_SOFTWARE='1')
                    if backend == 'kitty':
                        launch = ['kitty', '-c', 'NONE', '-o', 'linux_display_server=x11',
                                  '-o', 'initial_window_width=800', '-o', 'initial_window_height=600',
                                  '-o', 'cursor_blink_interval=0', *command]
                        release = version(['kitty', '--version'])
                    else:
                        if backend == 'tmux': command = ['tmux', '-L', session, '-f', '/dev/null', 'new-session', shlex.join(command)]
                        if backend == 'screen': command = ['screen', '-c', '/dev/null', '-S', session, *command]
                        launch = ['xterm', '-display', display, '-geometry', '80x24', '-xrm', 'XTerm*cursorBlink: false', '-e', *command]
                        release = version([backend, '-V' if backend == 'tmux' else '--version' if backend == 'screen' else '-version'])
                    process = subprocess.Popen(launch, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    pixels, seen = {}, set()
                    try:
                        deadline = time.monotonic() + 25
                        while process.poll() is None:
                            if time.monotonic() > deadline: raise RuntimeError(f'{backend} rendering probe timeout')
                            phasefile = directory / 'phase'
                            phase = phasefile.read_text() if phasefile.exists() else ''
                            if phase and phase not in seen:
                                seen.add(phase)
                                if phase != 'unsupported':
                                    time.sleep(0.15)  # Let the private emulator render the bytes delivered so far.
                                    pixels[phase] = subprocess.check_output(['import', '-display', display, '-window', 'root',
                                        '-depth', '8', 'rgb:-'], env=env, timeout=5)
                                (directory / (phase + '.ack')).touch()
                            time.sleep(0.01)
                        stdout, stderr = process.communicate()
                        if process.returncode: raise RuntimeError(f'{backend} exit {process.returncode}: {stderr.decode()}')
                        if not (directory / 'evidence.tsv').exists() or (directory / 'error').exists():
                            detail = (directory / 'error').read_text() if (directory / 'error').exists() else ''
                            wire = (directory / 'terminal.bin').read_bytes() if (directory / 'terminal.bin').exists() else b''
                            raise RuntimeError(f'{backend}: {detail} {wire[-2000:]!r} {stderr!r}')
                        evidence = dict(line.split('\t', 1) for line in (directory / 'evidence.tsv').read_text().splitlines())
                        record = dict(backend=backend, version=release, mode=mode, tested=True, evidence=evidence)
                        if 'unsupported' in seen: record['activation'] = 'declined'
                        else:
                            if set(pixels) != {'before', 'partial', 'after'}: raise RuntimeError(f'missing phases: {seen}')
                            record.update(activation='enabled' if mode == 'sync' else 'off',
                                partial_changed_bytes=sum(a != b for a, b in zip(pixels['before'], pixels['partial'])),
                                final_changed_bytes=sum(a != b for a, b in zip(pixels['before'], pixels['after'])),
                                hashes={key: hashlib.sha256(value).hexdigest() for key, value in pixels.items()},
                                wire=json.loads((directory / 'wire.json').read_text()))
                            if not record['final_changed_bytes']: raise RuntimeError('final frame did not become visible')
                            if mode == 'plain' and not record['partial_changed_bytes']: raise RuntimeError('plain comparison did not expose partial output')
                            if mode == 'sync' and record['partial_changed_bytes']: raise RuntimeError('synchronized frame exposed partial output')
                        records['scenarios'].append(record)
                    finally:
                        if process.poll() is None: process.kill(); process.wait()
                        if backend == 'tmux': subprocess.run(['tmux', '-L', session, 'kill-server'], capture_output=True)
                        if backend == 'screen': subprocess.run(['screen', '-S', session, '-X', 'quit'], capture_output=True)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(records, indent=2) + '\n')
        print(json.dumps(records, indent=2))
    finally:
        os.close(rr)
        xvfb.terminate(); xvfb.wait(timeout=5)


if __name__ == '__main__':
    main()
