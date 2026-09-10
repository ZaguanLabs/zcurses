#!/usr/bin/env python3
"""Explicit bounded input/resize recording and presentation-barrier replay."""
import argparse
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import sys
import termios
import time

import visual_diff

ROOT = Path(__file__).resolve().parents[1]
LIMIT = 16 * 1024 * 1024
RECIPES = ('form', 'document', 'canvas')
CONTEXT = {'term': 'xterm-256color', 'locale': 'C.UTF-8'}


def read_json(path):
    with open(path, 'rb') as stream:
        raw = stream.read(LIMIT + 1)
    if len(raw) > LIMIT:
        raise ValueError('recording exceeds 16 MiB')
    try:
        return json.loads(raw.decode('ascii'))
    except RecursionError as error:
        raise ValueError('recording nesting is too deep') from error


def geometry(value):
    if (not isinstance(value, list) or len(value) != 2 or
            any(type(n) is not int or not 1 <= n <= 128 for n in value) or
            value[0] * value[1] > 16384):
        raise ValueError('geometry must contain rows/columns in 1..128, at most 16384 cells')


def actions_valid(actions):
    if not isinstance(actions, list) or not 1 <= len(actions) <= 128:
        raise ValueError('expected 1..128 actions')
    budget = 0
    for action in actions:
        if not isinstance(action, dict) or len(action) != 1:
            raise ValueError('each action has exactly one input_hex or resize field')
        if 'input_hex' in action:
            value = action['input_hex']
            if not isinstance(value, str) or not re.fullmatch(r'(?:[0-9a-f]{2}){1,4096}', value):
                raise ValueError('input_hex must encode 1..4096 bytes in lowercase hex')
            budget += len(value) // 2
        elif 'resize' in action:
            geometry(action['resize'])
        else:
            raise ValueError('unsupported action')
    if budget > 65536:
        raise ValueError('input exceeds 64 KiB')
    if actions[-1] != {'input_hex': '1b'}:
        raise ValueError('last action must be Escape (input_hex 1b) to close the recipe')


def fields_valid(fields):
    if not isinstance(fields, dict) or len(fields) > 256:
        raise ValueError('invalid native field record')
    for key, value in fields.items():
        if (not isinstance(key, str) or not re.fullmatch(r'[a-z0-9_,]+', key) or
                not isinstance(value, str) or not re.fullmatch(r'(?:[0-9a-f]{2}){0,8192}', value)):
            raise ValueError('invalid native field encoding')


def validate(data):
    if not isinstance(data, dict) or set(data) != {'format', 'recipe', 'geometry', 'context', 'timing', 'actions', 'observations'}:
        raise ValueError('invalid recording fields')
    if data['format'] != 'zdraw-interaction-1' or data['timing'] != 'presentation-barrier':
        raise ValueError('unsupported recording format or timing policy')
    if data['recipe'] not in RECIPES or data['context'] != CONTEXT:
        raise ValueError('unsupported recipe or terminal/locale context')
    geometry(data['geometry'])
    actions_valid(data['actions'])
    observations = data['observations']
    if not isinstance(observations, list) or len(observations) != len(data['actions']) + 1:
        raise ValueError('one observation is required initially and after each action')
    size = data['geometry']
    for index, observation in enumerate(observations):
        if index and 'resize' in data['actions'][index - 1]:
            size = data['actions'][index - 1]['resize']
        if not isinstance(observation, dict) or set(observation) != {'events', 'context', 'frame', 'done'}:
            raise ValueError('invalid observation fields')
        if type(observation['done']) is not bool or observation['done'] != (index == len(observations) - 1):
            raise ValueError('only the final observation may finish')
        events = observation['events']
        if not isinstance(events, list) or len(events) > 128:
            raise ValueError('invalid observed events')
        for event in events:
            fields_valid(event)
        if index == 0:
            fields_valid(observation['context'])
        elif observation['context'] is not None:
            raise ValueError('context must appear only initially')
        if observation['done']:
            if observation['frame'] is not None:
                raise ValueError('final observation cannot have a frame')
        else:
            frame = visual_diff.validate(observation['frame'])
            if [frame['rows'], frame['columns']] != size:
                raise ValueError('frame geometry differs from action geometry')
    return data


class Session:
    """Own one child, its PTY and two synchronization pipes; never sleep to inject."""
    def __init__(self, recipe, size):
        control_r, self.control = os.pipe()
        self.report, report_w = os.pipe()
        self.pid, self.terminal = pty.fork()
        if self.pid == 0:
            try:
                os.close(self.control)
                os.close(self.report)
                os.set_inheritable(control_r, True)
                os.set_inheritable(report_w, True)
                fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', *size, 0, 0))
                os.environ.update(TERM=CONTEXT['term'], LC_ALL=CONTEXT['locale'])
                for name in ('LINES', 'COLUMNS', 'NO_COLOR', 'ZSH_ENV', 'ENV'):
                    os.environ.pop(name, None)
                shell = str(ROOT / '.build/zsh/Src/zsh')
                os.execl(shell, shell, '-df', str(ROOT / 'scripts/replay-recipe.zsh'),
                         str(report_w), str(control_r), recipe)
            except BaseException as error:
                os.write(2, str(error).encode(errors='replace'))
                os._exit(1)
        os.close(control_r)
        os.close(report_w)
        os.set_blocking(self.terminal, False)
        self.pending = bytearray()
        self.output = bytearray()
        self.terminal_open = True
        self.reaped = False
        self.total = 0

    def line(self, deadline):
        while b'\n' not in self.pending:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ValueError('recipe did not reach a presentation barrier within 10 seconds')
            watched = [self.report] + ([self.terminal] if self.terminal_open else [])
            for fd in select.select(watched, [], [], remaining)[0]:
                try:
                    raw = os.read(fd, 65536)
                except BlockingIOError:
                    continue
                except OSError as error:
                    if fd != self.terminal or error.errno != errno.EIO:
                        raise
                    raw = b''
                if fd == self.terminal:
                    self.output.extend(raw)
                    del self.output[:-4000]
                    if not raw:
                        self.terminal_open = False
                else:
                    if not raw:
                        raise ValueError('recipe exited before its barrier: ' + repr(bytes(self.output)))
                    self.pending.extend(raw)
                    self.total += len(raw)
                    if self.total > LIMIT:
                        raise ValueError('observations exceed 16 MiB')
        line, _, rest = self.pending.partition(b'\n')
        self.pending[:] = rest
        return line.decode('ascii')

    def start(self):
        if self.line(time.monotonic() + 10) != 'baseline':
            raise ValueError('missing initial synchronization barrier')
        self.baseline = termios.tcgetattr(self.terminal)
        return self.advance()

    def advance(self, action=None):
        if action and 'input_hex' in action:
            remaining = bytes.fromhex(action['input_hex'])
            deadline = time.monotonic() + 10
            while remaining:
                timeout = deadline - time.monotonic()
                if timeout <= 0 or not select.select([], [self.terminal], [], timeout)[1]:
                    raise ValueError('input queue did not accept the action within 10 seconds')
                try:
                    count = os.write(self.terminal, remaining)
                    remaining = remaining[count:]
                except BlockingIOError:
                    continue
        elif action:
            fcntl.ioctl(self.terminal, termios.TIOCSWINSZ, struct.pack('HHHH', *action['resize'], 0, 0))
            os.kill(self.pid, signal.SIGWINCH)
        os.write(self.control, b'continue\n')
        observation = {'events': [], 'context': None, 'frame': None, 'done': False}
        deadline = time.monotonic() + 10
        while True:
            packet = self.line(deadline).split('\t')
            kind = packet.pop(0)
            if kind in ('event', 'context'):
                fields = {}
                for entry in packet:
                    key, value = entry.split('=', 1)
                    if key in fields:
                        raise ValueError('duplicate native field')
                    fields[key] = '' if value == '-' else value
                fields_valid(fields)
                if kind == 'context':
                    if observation['context'] is not None:
                        raise ValueError('duplicate native context')
                    observation['context'] = fields
                else:
                    observation['events'].append(fields)
                    if len(observation['events']) > 128:
                        raise ValueError('too many events before a frame')
            elif kind == 'frame' and len(packet) == 1:
                observation['frame'] = visual_diff.validate(json.loads(packet[0]))
                return observation
            elif kind == 'done' and not packet:
                observation['done'] = True
                if termios.tcgetattr(self.terminal) != self.baseline:
                    raise ValueError('recipe did not restore terminal modes')
                return observation
            else:
                raise ValueError('invalid runner packet')

    def finish(self):
        # Drain the terminal through EOF with a deadline before reaping the child.
        deadline = time.monotonic() + 10
        while True:
            pid, status = os.waitpid(self.pid, os.WNOHANG)
            if pid:
                self.reaped = True
                if os.waitstatus_to_exitcode(status):
                    raise ValueError('recipe exited unsuccessfully: ' + repr(bytes(self.output)))
                return
            if time.monotonic() >= deadline:
                raise ValueError('recipe did not exit after cleanup')
            if select.select([self.terminal], [], [], 0.05)[0]:
                try:
                    raw = os.read(self.terminal, 65536)
                    self.output.extend(raw)
                    del self.output[:-4000]
                except BlockingIOError:
                    continue
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise

    def close(self):
        if not self.reaped:
            try:
                os.kill(self.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(self.pid, 0)
            self.reaped = True
        for fd in (self.control, self.report, self.terminal):
            os.close(fd)


def capture(recipe, size, actions):
    if recipe not in RECIPES:
        raise ValueError('unsupported recipe')
    geometry(size)
    actions_valid(actions)
    session = Session(recipe, size)
    try:
        observations = [session.start()]
        for index, action in enumerate(actions):
            observation = session.advance(action)
            observations.append(observation)
            if observation['done'] and index != len(actions) - 1:
                raise ValueError('recipe ended before the final action')
        if not observations[-1]['done']:
            raise ValueError('last action did not finish the recipe')
        session.finish()
        return validate({'format': 'zdraw-interaction-1', 'recipe': recipe,
                         'geometry': size, 'context': dict(CONTEXT),
                         'timing': 'presentation-barrier', 'actions': actions,
                         'observations': observations})
    finally:
        session.close()


def differences(expected, actual):
    result = []
    for index, (left, right) in enumerate(zip(expected['observations'], actual['observations'])):
        for key in ('context', 'events', 'done'):
            if left[key] != right[key]:
                result.append(f'barrier {index} {key}: {left[key]!r} -> {right[key]!r}')
        if left['frame'] is not None and right['frame'] is not None:
            result.extend(f'barrier {index} {line}' for line in visual_diff.changes(left['frame'], right['frame']))
        elif left['frame'] != right['frame']:
            result.append(f'barrier {index}: frame/exit mismatch')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    record = sub.add_parser('record', help='explicitly save scripted input, paste and frames')
    record.add_argument('recipe', choices=RECIPES)
    record.add_argument('actions', help='JSON array of input_hex/resize actions')
    record.add_argument('output')
    record.add_argument('--rows', type=int, default=24)
    record.add_argument('--columns', type=int, default=80)
    replay = sub.add_parser('replay')
    replay.add_argument('recording')
    replay.add_argument('--diff', help='write a readable mismatch report')
    args = parser.parse_args()
    try:
        if args.command == 'record':
            data = capture(args.recipe, [args.rows, args.columns], read_json(args.actions))
            encoded = json.dumps(data, ensure_ascii=True, separators=(',', ':')) + '\n'
            if len(encoded) > LIMIT:
                raise ValueError('serialized recording exceeds 16 MiB')
            # Exclusive creation protects existing recordings and action inputs.
            with open(args.output, 'x', encoding='ascii') as stream:
                stream.write(encoded)
            print(f'Recorded {len(data["actions"])} actions to {args.output}')
            return 0
        expected = validate(read_json(args.recording))
        actual = capture(expected['recipe'], expected['geometry'], expected['actions'])
        delta = differences(expected, actual)
        report = '\n'.join(delta) or 'Replay matched every event and frame.'
        if args.diff:
            with open(args.diff, 'x', encoding='utf-8') as stream:
                stream.write(report + '\n')
        print('\n'.join(delta[:100]) if delta else report)
        return bool(delta)
    except (ValueError, OSError, TypeError, KeyError) as error:
        print(f'Replay failed: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
