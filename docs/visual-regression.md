# Portable visual fixtures

Load `lib/zdraw-fixture.zsh`, declare a writable scalar `zdraw_ui_fixture`, and
call `zdraw-fixture window` during an initialized session. The complete result
is assigned atomically; the function prints nothing, presents nothing, and
preserves the window cursor and drawing state.

```zsh
source ./lib/zdraw-fixture.zsh
typeset zdraw_ui_fixture
zdraw-fixture stdscr || return
print -r -- "$zdraw_ui_fixture" > .build/actual.json
```

The ASCII JSON format `zdraw-ui-fixture-1` stores dimensions, cursor and every
coordinate's text, normalized color, named attributes and encoding. Named basic
colors become indexes; RGB spelling is normalized. Session-specific pair IDs and
implementation-specific attribute bitmasks are omitted. Unknown colors stay
unknown. Captures are limited to 16,384 cells and inherit native snapshot bounds.

The `layout=readback` contract deliberately retains the text returned at every
coordinate, including repeated text at wide-character continuation columns. It
does not infer continuation positions, including in subwindows starting inside
a wide glyph. This is portable serialization for comparisons, not a screen
restore or replay format. Encoding and curses differences remain visible rather
than being silently discarded.

## Compare and review

The standard-library Python tool validates inputs, prints coordinate-level
changes, and optionally writes a self-contained HTML comparison:

```sh
python3 scripts/visual_diff.py tests/fixtures/ui/dark-256-0.json .build/actual.json \
  --html .build/visual-diff.html
```

Exit status is zero for equality, one for differences and two for invalid input
or an I/O error. `--limit` bounds printed changes; the HTML report contains all
changes. The report shows expected and actual readback grids with changed cells
outlined. It uses a reference palette for indexed/default colors and preserves
raw data in tooltips. It is not a terminal/font screenshot; repeated wide-cell
readback and unmodeled terminal attributes can differ from actual presentation.

## Baselines

`tests/visual.zsh` renders a fixed panel/list/meter composition in dark/light,
256-color/monochrome and compact/padded variants. `make test` compares those eight
captures with checked-in fixtures, alongside export, alias normalization and
HTML-escaping checks. Tests never update baselines by default.

After an intentional visual change, explicitly regenerate and review:

```sh
ZDRAW_UPDATE_VISUALS=1 PYTHONPATH=tests python3 -m unittest test_visual -v
git diff -- tests/fixtures/ui
```

Use the matching built Zsh and module, as selected by the repository's test
harness. For a different platform or encoding, inspect differences before
adopting replacement baselines. Screenshots from actual terminals remain useful
for font rendering and terminal-specific behavior that logical fixtures cannot
prove.
