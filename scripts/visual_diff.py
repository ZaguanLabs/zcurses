#!/usr/bin/env python3
"""Validate and compare portable zdraw readback fixtures (standard library only)."""
import argparse
import html
import json
from pathlib import Path
import re
import sys


def load(path):
    path = Path(path)
    if path.stat().st_size > 8 * 1024 * 1024:
        raise ValueError('fixture exceeds 8 MiB')
    data = json.loads(path.read_text(encoding='ascii'))
    if not isinstance(data, dict):
        raise ValueError('fixture must be an object')
    if data.get('format') != 'zdraw-ui-fixture-1' or data.get('layout') != 'readback':
        raise ValueError('unsupported fixture format/layout')
    rows, columns = data.get('rows'), data.get('columns')
    if any(type(n) is not int or not 1 <= n <= 32767 for n in (rows, columns)) or rows * columns > 16384:
        raise ValueError('invalid dimensions')
    cursor = data.get('cursor')
    if not isinstance(cursor, list) or len(cursor) != 2 or any(type(n) is not int for n in cursor):
        raise ValueError('invalid cursor')
    if not (0 <= cursor[0] < rows and 0 <= cursor[1] < columns):
        raise ValueError('cursor outside fixture')
    cells = data.get('cells')
    if not isinstance(cells, list) or len(cells) != rows * columns:
        raise ValueError('incomplete cells')
    color = r'(?:default|(?:0|[1-9][0-9]{0,2})|#[0-9a-f]{6})'
    for index, cell in enumerate(cells):
        if not isinstance(cell, list) or len(cell) != 6 or any(type(n) is not int for n in cell[:2]) or cell[:2] != [index // columns, index % columns]:
            raise ValueError('cells must be complete and ordered by coordinate')
        if any(not isinstance(value, str) for value in cell[2:]):
            raise ValueError('invalid cell fields')
        if len(cell[2]) > 128 or len(cell[4]) > 512 or cell[5] not in ('byte', 'multibyte'):
            raise ValueError('invalid cell text, attributes or encoding')
        if cell[3] != 'unknown' and not re.fullmatch(color + '/' + color, cell[3]):
            raise ValueError('invalid color')
        for side in cell[3].split('/'):
            if side.isdecimal() and int(side) > 255:
                raise ValueError('invalid indexed color')
    return data


def changes(before, after):
    result = []
    for field in ('rows', 'columns', 'cursor'):
        if before[field] != after[field]:
            result.append(f'{field}: {before[field]!r} -> {after[field]!r}')
    left = {tuple(c[:2]): c[2:] for c in before['cells']}
    right = {tuple(c[:2]): c[2:] for c in after['cells']}
    for pos in sorted(left.keys() | right.keys()):
        if left.get(pos) != right.get(pos):
            result.append(f'cell {pos[0]},{pos[1]}: {left.get(pos)!r} -> {right.get(pos)!r}')
    return result


def css_color(value, default):
    ansi = ['#000000', '#800000', '#008000', '#808000', '#000080', '#800080', '#008080', '#c0c0c0',
            '#808080', '#ff0000', '#00ff00', '#ffff00', '#0000ff', '#ff00ff', '#00ffff', '#ffffff']
    if value in ('default', 'unknown'):
        return default
    if value.startswith('#'):
        return value
    index = int(value)
    if index < 16:
        return ansi[index]
    if index >= 232:
        return '#{0:02x}{0:02x}{0:02x}'.format(8 + (index - 232) * 10)
    index -= 16
    cube = [0, 95, 135, 175, 215, 255]
    return '#{:02x}{:02x}{:02x}'.format(cube[index // 36], cube[index // 6 % 6], cube[index % 6])


def html_report(before, after):
    differences = changes(before, after)
    maps = [{tuple(c[:2]): c[2:] for c in item['cells']} for item in (before, after)]
    changed = {pos for pos in maps[0].keys() | maps[1].keys() if maps[0].get(pos) != maps[1].get(pos)}
    parts = ['<!doctype html><meta charset="utf-8"><title>zdraw fixture comparison</title>',
             '<style>body{font:16px system-ui;background:#eee;color:#222;padding:24px}'
             '.screen{display:grid;width:max-content;font:16px/1.4 monospace;border:1px solid #888}'
             '.cell{width:1ch;height:1.4em;white-space:pre;overflow:hidden}.changed{outline:1px solid #f44;outline-offset:-1px}'
             'section{overflow:auto;margin-bottom:24px}pre{white-space:pre-wrap}</style>',
             '<h1>Fixture comparison</h1><p>Logical curses readback cells, not a terminal screenshot. '
             'Red outlines mark changed cells. Wide continuation columns retain repeated readback text; '
             'default and indexed colors use a reference palette. Hover for exact data.</p>']
    for label, data in (('Expected', before), ('Actual', after)):
        parts.append(f'<h2>{label}</h2><section><div class="screen" style="grid-template-columns:repeat({data["columns"]},1ch)">')
        for row, column, text, color, attrs, encoding in data['cells']:
            fg, bg = color.split('/') if '/' in color else ('unknown', 'unknown')
            fg, bg = css_color(fg, '#ddd'), css_color(bg, '#222')
            if 'reverse' in attrs.split():
                fg, bg = bg, fg
            style = f'color:{fg};background:{bg};'
            if 'bold' in attrs.split():
                style += 'font-weight:bold;'
            if 'underline' in attrs.split():
                style += 'text-decoration:underline;'
            cls = 'cell changed' if (row, column) in changed else 'cell'
            title = html.escape(repr((row, column, text, color, attrs, encoding)), quote=True)
            parts.append(f'<span class="{cls}" style="{style}" title="{title}">{html.escape(text)}</span>')
        parts.append('</div></section>')
    parts.append('<h2>Changes</h2><pre>' + html.escape('\n'.join(differences) or 'No changes.') + '</pre>')
    return ''.join(parts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('expected')
    parser.add_argument('actual')
    parser.add_argument('--html', metavar='OUTPUT', help='also write a self-contained visual report')
    parser.add_argument('--limit', type=int, default=100, help='maximum printed changes')
    args = parser.parse_args()
    try:
        if not 1 <= args.limit <= 16387:
            raise ValueError('limit must be 1..16387')
        before, after = load(args.expected), load(args.actual)
        result = changes(before, after)
        if args.html:
            target = Path(args.html)
            if target.resolve() in (Path(args.expected).resolve(), Path(args.actual).resolve()):
                raise ValueError('HTML output must not overwrite an input fixture')
            target.write_text(html_report(before, after), encoding='utf-8')
        print('\n'.join(result[:args.limit]) or 'No changes.')
        if len(result) > args.limit:
            print(f'... {len(result) - args.limit} more changes')
        return bool(result)
    except (ValueError, OSError, TypeError, KeyError) as error:
        print(f'Invalid fixture: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
