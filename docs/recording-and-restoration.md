# Interaction recording and screen restoration

Two separate formats serve different purposes. `zdraw-interaction-1` reproduces
scripted input and resize sequences in a real curses PTY and compares logical
frames. `zdraw-screen-1` restores a bounded subset of retained text cells to an
existing window. Neither captures terminal pixels, application state, images or
scaled-text placements. Existing `zdraw-snapshot-1` associations and
`zdraw-ui-fixture-1` comparison fixtures keep their previous default schemas.

## Record and replay a recipe

Build using the public-source setup in the [README](building.md#build-and-test).
The runner uses `.build/zsh/Src/zsh` and the module from the same build, Python's
standard library, the `xterm-256color` terminfo entry and `C.UTF-8` locale. It
supports the repository's `form`, `document` and `canvas` recipes. The form opts
into bracketed paste; all protocols retain the recipe's normal cleanup.

```sh
python3 scripts/replay.py record form \
  tests/recordings/form-resize.actions.json .build/my-interaction.json \
  --rows 16 --columns 40
python3 scripts/replay.py replay .build/my-interaction.json \
  --diff .build/my-interaction.diff
```

Recording is explicit. **Files contain the supplied input and paste bytes,
observed events and displayed text.** Hex encoding is not redaction or encryption.
There is no global keyboard hook, automatic recording or external command field.
Output files are created exclusively; choose another name to retain an earlier
recording or diff. A recording cannot select a shell, executable or arbitrary
recipe path. The trusted local examples still execute normally.

The checked-in [action sequence](../tests/recordings/form-resize.actions.json)
validates the empty form, pastes `界` with its UTF-8 bytes split across two chunks,
submits it, shrinks to 6×20, returns to 16×40 and exits. The accompanying
[recording](../tests/recordings/form-resize.json) was captured with public Zsh 5.9.2
and ncurses 6.5. A changed feature set, locale, curses version, terminfo database or
recipe can produce a context or frame mismatch; capture a baseline on the intended
configuration. A mismatch is evidence to review, not permission to replace it.

## Interaction format and timing

The JSON object has exactly these fields:

| Field | Contract |
| --- | --- |
| `format` | `zdraw-interaction-1` |
| `recipe` | `form`, `document` or `canvas` |
| `geometry` | Initial `[rows, columns]`; each 1–128, product at most 16384 |
| `context` | `{"term":"xterm-256color","locale":"C.UTF-8"}` |
| `timing` | `presentation-barrier` |
| `actions` | Ordered input/resize actions, described below |
| `observations` | Initial observation followed by one per action |

Each action contains exactly one field: `input_hex` (1–4096 raw bytes encoded as
lowercase hex), or `resize` with the same geometry bounds. There are 1–128 actions,
at most 64 KiB of input, and the final action is `{"input_hex":"1b"}` (Escape).
Files and observed runner traffic are bounded to 16 MiB. Malformed recordings are
rejected before starting the child.

Each observation contains `events`, `context`, `frame` and `done`. Native events
retain their key/value fields in order of receipt; each value is a hex byte string,
including empty strings and fragmented UTF-8. The initial native context contains
passive capability evidence, sorted compiled features, locale and curses version.
Later context fields are null. Frames use the existing portable comparison format.
Only the final observation has `done: true` and `frame: null`.

The child waits after each `refresh` or `present`. The parent injects the next
bytes or applies `TIOCSWINSZ`/`SIGWINCH`, then releases the barrier. This avoids
sleep-based injection guesses. Each action must cause one presentation or exit;
keys ignored by a recipe, multi-key bursts, duplicate resize sizes and input that
needs a later action before rendering are unsuitable steps. The runner bounds input-queue writes, each
barrier wait and final exit to ten seconds, verifies terminal mode restoration,
and closes its descriptors/reaps its child on success and failure.

This mode preserves **action ordering**, not original inter-byte delays. Native
Escape and paste timeouts still use real time; CPU scheduling, timing-sensitive
protocol bugs, asynchronous external producers, emulator shaping and slow network
links require separate real-terminal tests. The runner does not emulate a terminal
protocol responder or inject events directly into application state.

Replay compares native context, event fields and every fixture cell/cursor. Exit
status is 0 for a match, 1 for differences and 2 for invalid data or runner failure.
A readable diff identifies the presentation barrier and changed cell. To inspect
a frame visually, write either observation's `frame` object as JSON and use
[scripts/visual_diff.py](../scripts/visual_diff.py) with `--html`.

`tests/test_replay.py` demonstrates retaining a failed assertion: it records the
paste/resize interaction, deliberately replaces one expected `界` with `?`, saves
that recording, replays it and asserts that the saved diff identifies the barrier,
coordinate and both values. A [saved example diff](../tests/recordings/form-resize.failure.diff)
shows the output. This is a deliberate oracle mutation, not a claim that
the current form loses text on resize. The unchanged recording matches.

## Optional native occupancy metadata

```zsh
typeset -A pixels
zdraw snapshot sample pixels occupancy
print -r -- "$pixels[0,3,occupancy] $pixels[0,3,occupancy_source]"
```

The `cell_occupancy` feature advertises the optional final `occupancy` argument.
Every readback coordinate additionally has:

| Field | Values |
| --- | --- |
| `occupancy` | `single`, `base`, `continuation`, `unknown` |
| `occupancy_source` | `readback`, `inferred`, `unknown` |
| `base_column` | Zero-based relative column, or `unknown` |
| `cell_width` | Positive system character width, or `unknown` |
| `style_supported` | `yes` when all non-color attribute bits have supported style names; otherwise `no` |

Single-column printable cells have direct readback evidence. For wide characters,
identical text/style/pair runs bounded on **both** sides by different cells can be
partitioned into whole widths; these are marked **inferred**, never authoritative
library flags. Runs touching either horizontal window edge, partial runs, invalid
text and clipped/shared edges remain unknown. Adjacent equal wide glyphs can form
one run. Columns and inference refer only to the captured window.

Public curses complex-character readback exposes text, attributes and pair, but
its storage is opaque; see [ncurses `getcchar`](https://invisible-island.net/ncurses/man/curs_getcchar.3x.html).
No private continuation bits are accessed. Corrupted or orphaned storage can be
indistinguishable from valid repeated readback, and inference does not prove
terminal rendering or grapheme shaping. **Restoration below rejects all wide
cells**, including inferred complete ones. Default snapshots append none of these
fields and retain their original bounds, private-copy cleanup and atomic assignment.

## Text-screen serialization and restoration

Source the passive companion and explicitly supply a caller-owned scalar:

```zsh
source ./lib/zdraw-screen.zsh
typeset zdraw_screen_data
zdraw-screen-save sample || return
# The data survives drawing, deleting windows, end and module unload.
zdraw-screen-restore destination "$zdraw_screen_data" || return
```

This first subset supports one printable column per cell, including combining
marks that fit curses' complex-character storage. Dimensions are 1–64 each, at most
4096 cells, with exactly one serialized cell per row-major coordinate. The cursor
must be inside the rectangle. Destination dimensions must match exactly. The
operation does not create/resize windows or restore input modes/application state.
Restoring a subwindow writes its shared backing region, as ordinary drawing does.

The ASCII scalar has this grammar, with no final newline:

```text
zdraw-screen-1 ROWS COLUMNS CURSOR_ROW CURSOR_COLUMN
STYLE_HEX:TEXT_HEX
STYLE_HEX:TEXT_HEX
...
```

Integers are canonical unsigned decimal. Each cell field is lowercase, even-length
hex; `-` encodes the empty style. Decoded style is native comma-separated attribute
names plus an optional `foreground/background` color token. It contains no color
pair IDs or library-specific attribute numbers. Cached colors retain their names,
indices or RGB spelling. Uncached pair zero uses the default native style; other
uncached pairs and unsupported attribute bits, including alternate character set
flags, cannot be exported. Default/indexed colors depend on the destination's theme
and palette; RGB spelling does not guarantee the same displayed color on a terminal
that approximates it. Locale/system widths must agree across capture and restore.

The valid encoded scalar is limited to 1 MiB. Each hex field is at most 4096
characters (2048 decoded bytes). Restore validates all fields, rejects NULs,
controls, invalid encoding, empty text, multi-column text and unknown styles, and
prepares all rows before drawing any of them. Preparation also checks complex-cell
storage and color allocation. There is no `eval`, source-file execution or unsafe
escape interpretation: the decoder constructs only validated `\\xNN` escapes.

Temporary prepared rows have collision-checked names, at most 64 owned rows and
8192 candidate names, and share the native prepared-storage/color budgets. They
are always released, including after a later prepare/draw failure. Native color
pairs already allocated during preparation remain cached until session cleanup.
Validation/preparation failure preserves the destination. A curses **write** failure
can leave earlier rows or part of the failing row drawn; restoration does not
promise rollback of library writes. The saved cursor is set after all rows draw.
The caller's serialized scalar is never changed by restore. Save assigns it only
after complete successful capture.

Return status is 0 on success, 1 for invalid data, geometry, budgets or native
failures, and 2 for unsupported cells/styles or unavailable native support. Sourcing
the library does not initialize curses, inspect a window, read input or write files.
File storage is caller-owned: persist the ASCII scalar without evaluating it, and
apply the 1 MiB bound while reading external files before calling restore.
