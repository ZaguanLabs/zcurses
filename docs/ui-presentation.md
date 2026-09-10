# Tabs, badges, meters and help rows

These optional components share the existing theme and utility vocabulary. Each
loader includes common styling and its own component; it does not load other
component renderers. Loading remains passive, with no terminal access or input.

```zsh
source ./lib/zdraw-tabs.zsh
source ./lib/zdraw-badge.zsh
source ./lib/zdraw-meter.zsh
source ./lib/zdraw-help.zsh
```

Select only the pieces needed. Drawing requires an initialized native session and
a caller-owned `zdraw_ui_theme` association. These calls neither refresh nor read
keys, and preserve the window's cursor and current attributes. They do not modify
the caller's `reply` or `zdraw_ui_style`.

The [task-monitor recipe](recipes/task-monitor.md) combines them with panels,
layouts and a table in a complete application.

## Tabs

```text
zdraw-tabs window row column columns selected focus|inactive|disabled \
  [utility ...] -- [label ...]
```

Pass 1–32 labels as separate array entries and a one-based selected index. An
empty set uses `selected=0` and clears the row. Selection is input data, not an
output or an instruction to read keys. The application maps Tab, arrow keys or
other actions to its chosen index, including any wrapping behavior.

```zsh
zdraw-tabs stdscr 1 0 60 2 focus -- Overview Queue History
```

Tabs use natural label widths, a two-column selection-marker area, and `px=1`
padding. One blank column separates tabs. When the row cannot fit them all, the
renderer always includes the selected tab, adds preceding neighbors while they
fit, then adds following neighbors. A long selected tab clips to the available
width. Padding shrinks when needed to keep at least one content column, so even
a one-column rectangle can show its `>` marker. Other hidden tabs are not drawn.

Defaults are `fg=muted bg=canvas`, with selected tabs using
`fg=on-selection bg=selection bold`. Inactive selections use the inactive theme
colors. Disabled tabs use muted text on the canvas without bold/reverse, while
retaining the marker. Monochrome selections add reverse video. Override parts
with the existing state utilities:

```zsh
zdraw-tabs stdscr 1 0 60 2 focus px=0 \
  selected:bg=4 selected:fg=7 selected:underline -- Overview Queue History
```

`align` positions text inside each tab; borders and nonzero `py` are rejected.
Disabling interaction remains application policy. This version supplies one
shared focus/disabled state for the strip, not per-tab enabled flags.

## Badges and status values

```text
zdraw-badge window row column columns text states [utility ...]
```

A badge is a label preset: `fg=on-selection bg=selection bold align=center px=1`.
Monochrome adds reverse video. Its allocated row segment is filled with the
badge background, and text clips inside the padding. It consumes no intrinsic
width or layout state; the application allocates a rectangle just as for labels.

```zsh
zdraw-badge stdscr 0 48 12 Running normal
zdraw-badge stdscr 0 48 12 Failed normal bg=error fg=surface no-bold
```

It inherits the label contract, including rejection of borders and nonzero `py`.
Use labels and badges together for a custom status row. Plain words communicate
the state alongside its color; no icon font is required.

## Meters

```text
zdraw-meter window row column columns value total states \
  [utility ...] [label=on|off] [fill-char=character] [empty-char=character]
```

Values are unsigned decimal integers up to 32,767, with `total>0` and
`value<=total`. The bar fills `floor(bar-columns * value / total)` cells. The
numeric label shows `floor(100 * value / total)%`. By default it reserves five
columns at the right, or four when the whole meter is only four columns wide.
Below four columns, the label is omitted and the entire width becomes the bar.
`label=off` also gives the entire width to the bar.

```zsh
zdraw-meter stdscr 4 2 50 37 100 normal
zdraw-meter stdscr 5 2 50 8 12 normal label=off fill-char='=' empty-char='.'
```

Default glyphs are ASCII `#` and `-`. Custom glyphs must each be one character
that occupies one terminal column; invalid or unsupported glyphs fail before
drawing. Choose ASCII yourself when a custom Unicode glyph is unavailable.

The shared `track`, `filled` and `label` tags style meter parts. Defaults are
`fg=border bg=surface`, `filled:fg=accent`, `label:fg=text` and
`label:align=right`. For example:

```zsh
zdraw-meter stdscr 4 2 50 37 100 normal \
  filled:fg=error track:fg=muted label:bold
```

Borders and nonzero `px`/`py` are rejected. Alignment applies only to the numeric
label within its reserved area. The component owns no timer, animation, task or
completion state. Repaint it when the application's value changes.

## Help rows

```text
zdraw-help window row column columns states [utility ...] -- [key action ...]
```

Pass key/action pairs, with up to 32 pairs. Each pair displays as `key action`,
and pairs are separated by two spaces. The renderer displays the longest leading
sequence of complete pairs that fits. It does not truncate a key or action, skip
an oversized item to show a later one, or invoke any of the displayed actions.
An empty sequence clears the row. Put critical shortcuts first and provide
shorter descriptions when space is limited.

```zsh
zdraw-help stdscr 23 0 80 normal -- q quit Space pause Tab view r reset
```

Defaults are `fg=muted bg=canvas`, with `key:fg=accent key:bold`. The new `key`
and `label` tags distinguish shortcut keys from descriptions. Customize them
through ordinary utility arrays. Borders, padding and non-left alignment are
rejected for this sequential row.

## Validation and limits

All arguments, text and resolved part styles are validated before painting,
including labels or shortcuts omitted from the visible row. Text follows native
`textinfo` rules: printable content without control sequences, tabs, newlines or
leading combining characters. Tabs and help rows accept at most 262,144 total
text characters; badges inherit the label limit. Utility limits include defaults.

The shared geometry limits and two-pass utility precedence apply. Part conditions
are resolved after unconditional properties, in declaration order. Use a part
condition to override its default, such as `key:no-bold` or `label:fg=accent`.
Invalid toolkit arguments return one; native errors propagate. As with the other
components, native allocation or drawing failures can leave partial output.
