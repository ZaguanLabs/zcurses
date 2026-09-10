#!/usr/bin/env python3
"""Optional PNG/JPEG -> bounded zdraw-image-1 data, using ImageMagick 7."""
import argparse
import os
from pathlib import Path
import selectors
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import time

MAX_INPUT = 8 * 1024 * 1024
PALETTE = ((0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0),
           (0, 0, 128), (128, 0, 128), (0, 128, 128), (192, 192, 192),
           (128, 128, 128), (255, 0, 0), (0, 255, 0), (255, 255, 0),
           (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255))
POLICY = '''<policymap>
<policy domain="delegate" rights="none" pattern="*"/>
<policy domain="filter" rights="none" pattern="*"/>
<policy domain="coder" rights="none" pattern="*"/>
<policy domain="coder" rights="read" pattern="{PNG,JPEG}"/>
<policy domain="coder" rights="write" pattern="RGB"/>
<policy domain="path" rights="none" pattern="@*"/>
<policy domain="resource" name="width" value="4096"/>
<policy domain="resource" name="height" value="4096"/>
<policy domain="resource" name="list-length" value="4"/>
<policy domain="resource" name="memory" value="128MiB"/>
<policy domain="resource" name="map" value="0"/>
<policy domain="resource" name="disk" value="0"/>
<policy domain="resource" name="thread" value="1"/>
<policy domain="resource" name="time" value="5"/>
</policymap>
'''


def read_image(filename):
    fd = os.open(filename, os.O_RDONLY | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_INPUT:
            raise ValueError('expected a regular image file of at most 8 MiB')
        data = stream.read(MAX_INPUT + 1)
    if len(data) > MAX_INPUT:
        raise ValueError('input exceeded 8 MiB')
    if data.startswith(b'\x89PNG\r\n\x1a\n') and len(data) >= 33 and data[8:16] == b'\0\0\0\rIHDR':
        width, height = struct.unpack('>II', data[16:24])
        kind = 'PNG'
    elif data.startswith(b'\xff\xd8'):
        offset, width, height = 2, 0, 0
        while offset < len(data):
            if data[offset] != 255:
                break
            while offset < len(data) and data[offset] == 255:
                offset += 1
            if offset >= len(data):
                break
            marker = data[offset]
            offset += 1
            if marker in (0xDA, 0xD9):
                break
            if marker == 1 or 0xD0 <= marker <= 0xD7:
                continue
            if offset + 2 > len(data):
                break
            length = int.from_bytes(data[offset:offset + 2], 'big')
            if length < 2 or offset + length > len(data):
                break
            if marker in (0xC0, 0xC1, 0xC2):
                if length >= 8:
                    height, width = struct.unpack('>HH', data[offset + 3:offset + 7])
                break
            offset += length
        kind = 'JPEG'
    else:
        raise ValueError('only PNG and baseline/progressive JPEG are supported')
    if not (0 < width <= 4096 and 0 < height <= 4096 and width * height <= 4194304):
        raise ValueError('invalid dimensions or image exceeds 4096 per side / 4 Mi pixels')
    return kind, data


def bounded_process(command, *, env, cwd, expected, timeout=5):
    """Own/reap the converter; never accumulate more than expected+1 output bytes."""
    process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, env=env, cwd=cwd, start_new_session=True)
    output = bytearray()
    deadline = time.monotonic() + timeout
    try:
        with selectors.DefaultSelector() as reader:
            reader.register(process.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not reader.select(remaining):
                    raise ValueError('conversion timed out')
                chunk = os.read(process.stdout.fileno(), min(4096, expected + 1 - len(output)))
                if not chunk:
                    break
                output.extend(chunk)
                if len(output) > expected:
                    raise ValueError('converter exceeded its output limit')
        remaining = max(0.001, deadline - time.monotonic())
        if process.wait(timeout=remaining) or len(output) != expected:
            raise ValueError('conversion failed or returned incomplete pixels')
        return bytes(output)
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
        process.wait()
        process.stdout.close()


def convert(filename, rows, columns):
    if not (1 <= rows <= 64 and 1 <= columns <= 128 and rows * columns <= 4096):
        raise ValueError('preview must fit 1–64 rows, 1–128 columns and 4096 cells')
    kind, data = read_image(filename)
    executable = shutil.which('magick')
    if executable is None:
        raise ValueError('ImageMagick 7 magick is unavailable')
    with tempfile.TemporaryDirectory(prefix='zdraw-image-') as directory:
        root = Path(directory)
        (root / 'input.bin').write_bytes(data)
        (root / 'policy.xml').write_text(POLICY)
        env = os.environ.copy()
        env.update(MAGICK_CONFIGURE_PATH=directory, MAGICK_TEMPORARY_PATH=directory,
                   MAGICK_THREAD_LIMIT='1')
        size = f'{columns}x{rows * 2}'
        command = [executable, '-limit', 'memory', '128MiB', '-limit', 'map', '0',
                   '-limit', 'disk', '0', '-limit', 'thread', '1', '-limit', 'time', '5',
                   f'{kind}:{root / "input.bin"}[0]', '-auto-orient', '-background', '#000000',
                   '-alpha', 'remove', '-alpha', 'off', '-colorspace', 'sRGB',
                   '-resize', size, '-gravity', 'center', '-extent', size, '-depth', '8', 'RGB:-']
        rgb = bounded_process(command, env=env, cwd=directory, expected=rows * columns * 6)
    indices = []
    for offset in range(0, len(rgb), 3):
        pixel = rgb[offset:offset + 3]
        index = min(range(16), key=lambda i: sum((pixel[c] - PALETTE[i][c]) ** 2 for c in range(3)))
        indices.append(format(index, 'x'))
    return f'zdraw-image-1 {rows} {columns}\n' + '\n'.join(
        ''.join(indices[start:start + columns]) for start in range(0, len(indices), columns)) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('--rows', type=int, default=24)
    parser.add_argument('--columns', type=int, default=80)
    args = parser.parse_args()
    interrupted_status = 130
    def interrupted(signum, _frame):
        nonlocal interrupted_status
        interrupted_status = 128 + signum
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    try:
        packet = convert(args.image, args.rows, args.columns)
        sys.stdout.write(packet)
    except KeyboardInterrupt:
        return interrupted_status
    except (ValueError, OSError, subprocess.TimeoutExpired):
        # Neither the filename nor converter diagnostics can become terminal text.
        print('Image preview unavailable: invalid input, converter failure or resource limit.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
