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


def send_x11_a(display):
    # This display is the driver's private Xvfb, never the user's desktop.
    import ctypes as c
    import ctypes.util
    x11 = c.CDLL(ctypes.util.find_library('X11'))
    xtst = c.CDLL(ctypes.util.find_library('Xtst'))
    class Hint(c.Structure):
        _fields_ = [('name', c.c_void_p), ('klass', c.c_void_p)]
    x11.XOpenDisplay.argtypes = [c.c_char_p]; x11.XOpenDisplay.restype = c.c_void_p
    x11.XDefaultRootWindow.argtypes = [c.c_void_p]; x11.XDefaultRootWindow.restype = c.c_ulong
    x11.XQueryTree.argtypes = [c.c_void_p, c.c_ulong, c.POINTER(c.c_ulong), c.POINTER(c.c_ulong),
                              c.POINTER(c.POINTER(c.c_ulong)), c.POINTER(c.c_uint)]
    x11.XGetClassHint.argtypes = [c.c_void_p, c.c_ulong, c.POINTER(Hint)]
    x11.XFree.argtypes = [c.c_void_p]
    x11.XSetInputFocus.argtypes = [c.c_void_p, c.c_ulong, c.c_int, c.c_ulong]
    x11.XKeysymToKeycode.argtypes = [c.c_void_p, c.c_ulong]; x11.XKeysymToKeycode.restype = c.c_ubyte
    x11.XFlush.argtypes = [c.c_void_p]; x11.XCloseDisplay.argtypes = [c.c_void_p]
    xtst.XTestFakeKeyEvent.argtypes = [c.c_void_p, c.c_uint, c.c_int, c.c_ulong]
    connection = x11.XOpenDisplay(display.encode())
    if not connection:
        raise RuntimeError('cannot open private Xvfb display')
    try:
        root, parent, children, count = c.c_ulong(), c.c_ulong(), c.POINTER(c.c_ulong)(), c.c_uint()
        if not x11.XQueryTree(connection, x11.XDefaultRootWindow(connection), c.byref(root),
                             c.byref(parent), c.byref(children), c.byref(count)):
            raise RuntimeError('cannot inspect private Xvfb windows')
        target = None
        for index in range(count.value):
            hint = Hint()
            if x11.XGetClassHint(connection, children[index], c.byref(hint)):
                if hint.klass and b'kitty' in c.string_at(hint.klass).lower():
                    target = children[index]
                if hint.name: x11.XFree(hint.name)
                if hint.klass: x11.XFree(hint.klass)
        if children: x11.XFree(children)
        if target is None:
            raise RuntimeError('private kitty window not found')
        x11.XSetInputFocus(connection, target, 2, 0)
        keycode = x11.XKeysymToKeycode(connection, ord('a'))
        xtst.XTestFakeKeyEvent(connection, keycode, 1, 0)
        xtst.XTestFakeKeyEvent(connection, keycode, 0, 0)
        x11.XFlush(connection)
    finally:
        x11.XCloseDisplay(connection)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--enhanced', action='store_true', help='Test focus/keyboard activation and optional real kitty key events')
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
            for backend in (('direct', 'tmux', 'screen', 'kitty') if args.enhanced else ('direct', 'tmux', 'screen')):
                if backend != 'direct' and not shutil.which(backend):
                    records['scenarios'].append(dict(backend=backend, tested=False, reason='executable unavailable'))
                    continue
                output = Path(tmp) / f'{backend}.tsv'
                command = [str(ROOT / '.build/zsh/Src/zsh'), '-df',
                           str(ROOT / ('scripts/portability/terminal-enhanced.zsh' if args.enhanced else 'scripts/portability/terminal.zsh')), str(output)]
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
                    if backend == 'kitty':
                        record['version'] = version(['kitty', '--version'])
                        address = 'unix:' + str(Path(tmp) / 'kitty.sock')
                        env.update(LIBGL_ALWAYS_SOFTWARE='1')
                        process = subprocess.Popen(['kitty', '-c', 'NONE', '--listen-on', address,
                            '-o', 'allow_remote_control=yes', '-o', 'linux_display_server=x11', *command],
                            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                        try:
                            deadline = time.monotonic() + 15
                            while not Path(str(output) + '.ready').exists() and process.poll() is None:
                                if time.monotonic() >= deadline:
                                    raise RuntimeError('kitty startup/negotiation timeout')
                                time.sleep(0.02)
                            if process.poll() is None:
                                for chord in ('ctrl+shift+s',):
                                    subprocess.run(['kitty', '@', '--to', address, 'send-key', chord],
                                                   env=env, capture_output=True, check=True, timeout=5)
                                send_x11_a(display)
                            stdout, stderr = process.communicate(timeout=15)
                            if process.returncode or not output.exists():
                                raise RuntimeError(f'kitty: exit {process.returncode}: {stderr}')
                        finally:
                            if process.poll() is None:
                                process.kill(); process.wait()
                    else:
                        result = subprocess.run(['xterm', '-display', display, '-geometry', '80x24', '-e', *command],
                                                env=env, capture_output=True, text=True, timeout=20)
                        if result.returncode or not output.exists():
                            raise RuntimeError(f'{backend}: exit {result.returncode}: {result.stderr}')
                    record['evidence'] = dict(line.split('\t', 1) for line in output.read_text().splitlines())
                    if backend == 'kitty' and any(record['evidence'].get(field) != '1' for field in
                            ('shortcut_press', 'shortcut_release', 'associated_text')):
                        raise RuntimeError(f'kitty event verification failed: {record}')
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
