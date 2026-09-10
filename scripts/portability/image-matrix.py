#!/usr/bin/env python3
"""Opt-in image lifecycle research in private Xvfb terminals, never the user's session."""
import argparse
import base64
import ctypes
import ctypes.util
import hashlib
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
IMAGE_ID = 33554474  # Low byte 42 in the foreground; high byte 2 in a diacritic.
PHASES = {'initial', 'redraw', 'scrolled', 'overlay', 'replaced', 'before-resize',
          'resized', 'suspended', 'resumed', 'interrupted', 'reuploaded', 'ended', 'unloaded'}


def packets(replacement=False):
    colors = ((20, 40, 250), (30, 180, 250)) if replacement else ((250, 20, 30), (250, 180, 30))
    raw = b''.join(bytes(colors[(x // 16 + y // 16) % 2]) for y in range(32) for x in range(64))
    encoded = base64.b64encode(raw)
    result = []
    for start in range(0, len(encoded), 4096):
        header = f'a=T,U=1,f=24,s=64,v=32,c=8,r=4,i={IMAGE_ID},q=2,' if not start else 'q=2,'
        result.append(b'\x1b_G' + header.encode() + f'm={int(start+4096<len(encoded))};'.encode() + encoded[start:start+4096] + b'\x1b\\')
    return result


def setup(directory, transport='direct'):
    def wrap(packet):
        if transport == 'tmux':
            return b'\x1bPtmux;' + packet.replace(b'\x1b', b'\x1b\x1b') + b'\x1b\\'
        return packet
    for name, data in [('upload', packets()), ('replacement', packets(True)),
                       ('interrupted', packets()[:1]),
                       ('abort', [b'\x1b_Gm=0,q=2;\x1b\\']),
                       ('delete', [f'\x1b_Ga=d,d=I,i={IMAGE_ID},q=2\x1b\\'.encode()])]:
        (directory / name).write_bytes(b''.join(map(wrap, data)))
    os.mkfifo(directory / 'ack')


def resize_window(display):
    """Resize only the large top-level window on this newly created X server."""
    x = ctypes.CDLL(ctypes.util.find_library('X11'))
    ptr, win, uint = ctypes.c_void_p, ctypes.c_ulong, ctypes.c_uint
    x.XOpenDisplay.argtypes = [ctypes.c_char_p]; x.XOpenDisplay.restype = ptr
    x.XDefaultRootWindow.argtypes = [ptr]; x.XDefaultRootWindow.restype = win
    x.XQueryTree.argtypes = [ptr, win, ctypes.POINTER(win), ctypes.POINTER(win), ctypes.POINTER(ctypes.POINTER(win)), ctypes.POINTER(uint)]
    x.XGetGeometry.argtypes = [ptr, win, ctypes.POINTER(win), ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int), ctypes.POINTER(uint), ctypes.POINTER(uint), ctypes.POINTER(uint), ctypes.POINTER(uint)]
    x.XResizeWindow.argtypes = [ptr, win, uint, uint]
    x.XSync.argtypes = [ptr, ctypes.c_int]; x.XFree.argtypes = [ptr]; x.XCloseDisplay.argtypes = [ptr]
    connection = x.XOpenDisplay(display.encode())
    if not connection:
        raise RuntimeError('private X display unavailable')
    children = ctypes.POINTER(win)()
    try:
        root, parent, count = win(), win(), uint()
        if not x.XQueryTree(connection, x.XDefaultRootWindow(connection), ctypes.byref(root), ctypes.byref(parent), ctypes.byref(children), ctypes.byref(count)):
            raise RuntimeError('private X window query failed')
        for child in children[:count.value]:
            px, py, width, height, border, depth = ctypes.c_int(), ctypes.c_int(), uint(), uint(), uint(), uint()
            x.XGetGeometry(connection, child, ctypes.byref(root), ctypes.byref(px), ctypes.byref(py), ctypes.byref(width), ctypes.byref(height), ctypes.byref(border), ctypes.byref(depth))
            if width.value > 100 and height.value > 100:
                x.XResizeWindow(connection, child, 640, 480)
        x.XSync(connection, 0)
    finally:
        if children:
            x.XFree(children)
        x.XCloseDisplay(connection)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-private-terminals', action='store_true', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--captures', type=Path, required=True)
    args = parser.parse_args()
    from PIL import Image
    for command in ('Xvfb', 'kitty', 'xterm', 'import'):
        if not shutil.which(command):
            parser.error(f'{command} required for this optional research harness')
    args.captures.mkdir(parents=True, exist_ok=True)
    result = dict(format='zdraw-image-matrix-1', platform=platform.platform(), locale='C.UTF-8',
                  shell=subprocess.check_output([str(ROOT / '.build/zsh/Src/zsh'), '--version'], text=True).strip(),
                  image_id=IMAGE_ID, image_pixels=[64, 32], placement_cells=[8, 4], scenarios=[])
    rr, rw = os.pipe()
    xvfb = subprocess.Popen(['Xvfb', '-displayfd', str(rw), '-screen', '0', '1200x900x24', '-nolisten', 'tcp'],
                            pass_fds=(rw,), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.close(rw)
    try:
        if not select.select([rr], [], [], 5)[0]:
            raise RuntimeError('Xvfb startup timeout')
        display = ':' + os.read(rr, 64).decode().strip()
        with tempfile.TemporaryDirectory(prefix='image-matrix-', dir=ROOT / '.build') as tmp:
            for backend in ('kitty', 'kitty-tmux', 'kitty-screen', 'xterm'):
                multiplexer = backend.split('-')[1] if '-' in backend else None
                if multiplexer and not shutil.which(multiplexer):
                    result['scenarios'].append(dict(backend=backend, tested=False))
                    continue
                directory = Path(tmp) / backend
                directory.mkdir()
                setup(directory, 'tmux' if multiplexer == 'tmux' else 'direct')
                ack = os.open(directory / 'ack', os.O_RDWR | os.O_NONBLOCK)
                session = f'zdraw-image-{os.getpid()}'
                command = [str(ROOT / '.build/zsh/Src/zsh'), '-df', str(ROOT / 'scripts/portability/image-source.zsh'), str(directory)]
                env = os.environ.copy()
                for key in ('TERM', 'TERMINFO', 'TERMINFO_DIRS', 'LINES', 'COLUMNS', 'TMUX', 'STY'):
                    env.pop(key, None)
                env.update(DISPLAY=display, LC_ALL='C.UTF-8', LIBGL_ALWAYS_SOFTWARE='1', NO_COLOR='')
                if multiplexer == 'tmux':
                    config = directory / 'tmux.conf'
                    # Older tmux permits passthrough without this newer option.
                    # -q avoids entering the config-error screen on those builds.
                    config.write_text('set -gq allow-passthrough on\nset -g default-terminal screen-256color\nset -g status off\n')
                    command = ['tmux', '-L', session, '-f', str(config), 'new-session', shlex.join(command)]
                elif multiplexer == 'screen':
                    config = directory / 'screenrc'
                    config.write_text('startup_message off\n')
                    command = ['screen', '-c', str(config), '-T', 'screen-256color', '-S', session, *command]
                if backend == 'xterm':
                    launch = ['xterm', '-tn', 'xterm-256color', '-geometry', '90x25', '-fa', 'monospace', '-fs', '12', '-e', *command]
                else:
                    launch = ['kitty', '-c', 'NONE', '-o', 'linux_display_server=x11', '-o', 'font_family=monospace',
                              '-o', 'font_size=12', '-o', 'initial_window_width=1000', '-o', 'initial_window_height=700',
                              '-o', 'cursor_blink_interval=0', *command]
                process = subprocess.Popen(launch, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                seen, frames = set(), {}
                try:
                    deadline = time.monotonic() + 60
                    while process.poll() is None:
                        if time.monotonic() > deadline:
                            raise RuntimeError(f'{backend} timed out; phases: {seen}')
                        phase = (directory / 'phase').read_text().strip() if (directory / 'phase').exists() else ''
                        if phase and phase not in seen:
                            seen.add(phase)
                            if phase == 'before-resize':
                                resize_window(display)
                                time.sleep(.3)
                            else:
                                time.sleep(2 if phase == 'initial' else .2)
                                capture = args.captures / f'{backend}-{phase}.png'
                                subprocess.run(['import', '-display', display, '-window', 'root', str(capture.resolve())],
                                               env=env, check=True, timeout=5)
                                with Image.open(capture) as picture:
                                    colors = dict((rgb, count) for count, rgb in picture.convert('RGB').getcolors(1200*900))
                                frames[phase] = dict(file=capture.name, sha256=hashlib.sha256(capture.read_bytes()).hexdigest(),
                                                     original_pixels=colors.get((250, 20, 30), 0),
                                                     replacement_pixels=colors.get((20, 40, 250), 0))
                            os.write(ack, b'x')
                        time.sleep(.01)
                    _, stderr = process.communicate(timeout=5)
                    if process.returncode or seen != PHASES or not (directory / 'done').exists():
                        error = (directory / 'error').read_text() if (directory / 'error').exists() else ''
                        raise RuntimeError(f'{backend}: exit {process.returncode}, phases {seen}, {error}, {stderr.decode(errors="replace")}')
                    version_command = [multiplexer, '-V' if multiplexer == 'tmux' else '--version'] if multiplexer else [backend, '-version' if backend == 'xterm' else '--version']
                    result['scenarios'].append(dict(backend=backend, tested=True, version=subprocess.check_output(version_command, text=True).strip(),
                                                   storage=(directory / 'storage').read_text().splitlines(),
                                                   readback=(directory / 'readback.tsv').read_text().splitlines(), frames=frames))
                    print(f'{backend}: {len(frames)} lifecycle captures', flush=True)
                finally:
                    os.close(ack)
                    if process.poll() is None:
                        process.kill()
                        process.wait()
                    if multiplexer == 'tmux':
                        subprocess.run(['tmux', '-L', session, 'kill-server'], capture_output=True)
                    elif multiplexer == 'screen':
                        subprocess.run(['screen', '-S', session, '-X', 'quit'], capture_output=True)
    finally:
        os.close(rr)
        xvfb.terminate()
        xvfb.wait(timeout=5)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
