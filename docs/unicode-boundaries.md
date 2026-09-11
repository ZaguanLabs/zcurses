# Unicode editing boundaries

The optional `grapheme` policy lets a field move, select and delete sequences such
as `👍🏽`, `🇳🇴` and `👩‍💻` as complete units. The default `cell` policy remains one
positive-width character plus its following zero-width characters. Both policies
preserve original source bytes and use the system's character widths.

```zsh
typeset -A hit clipped zdraw_ui_input
zdraw textpos hit '👍🏽X' byte 4 grapheme
# hit[text]=👍🏽, byte_start=0, byte_end=8; system columns may total 4.
zdraw textinfo clipped '👍🏽X' 2 grapheme
# With widths 2+2, the complete first unit does not fit: text is empty.
source ./lib/zdraw-input.zsh
zdraw-input-init '👍🏽X' 4096 grapheme
zdraw-input-edit left       # Move before X.
zdraw-input-edit backspace  # Delete all of 👍🏽, leaving X.
```

## Native API

```text
zdraw textpos association text byte|column offset [cell|grapheme]
zdraw textinfo association text [columns [cell|grapheme]]
```

`textinfo` requires an explicit column budget when specifying a policy. Omitting
the policy, or using `cell`, preserves the original result fields and semantics.
Explicit `grapheme` results additionally contain `policy=grapheme` and
`unicode_version=17.0.0`. Byte offsets still address original UTF-8 bytes; offsets
inside any member of a unit return that whole unit. A budget too small for the
first unit returns an empty prefix. Text beyond the retained prefix or requested
position is still validated before assignment.

The feature `grapheme_boundaries` means this build provides the optional policy.
It requires Zsh multibyte support, `nl_langinfo(CODESET)`, an active UTF-8 codeset
and the `MULTIBYTE` option. Explicit requests return **2** when unavailable,
including ASCII requests in the C locale; there is no silent policy fallback.
Invalid input, unknown policies, excessive input or invalid result destinations
return **1**. Query destinations retain their existing value on these failures.
Normal queries continue working before initialization, after cleanup and during
suspension, without terminal input, output, protocol activation or locale changes.

The optional policy accepts at most **1,048,576 original bytes** per query.
Segmentation uses a binary search in a static property table per decoded scalar
and constant-sized suffix state. The returned strings still allocate storage
proportional to the source, as existing text queries do. There is no persistent
segmentation cache, runtime download or new linked library.

## Boundary definition and width

The engine implements Unicode 17.0.0 extended grapheme boundaries from
[UAX #29 revision 47](https://www.unicode.org/reports/tr29/tr29-47.html), including
Hangul, Indic conjuncts, emoji modifiers, pictographic joiners and regional
indicator pairing. It passes all 766 cases in the pinned
[official break tests](../tests/unicode/GraphemeBreakTest.txt).

The terminal-facing policy is a **profile**, rather than an unmodified Unicode
boundary API: it suppresses a break before a system-zero-width character, so it
never splits an existing native clipping unit. For example, `a` + ZERO WIDTH
SPACE + `b` has the two units `a` + ZERO WIDTH SPACE, then `b`. The standalone
engine's full-rule conformance is tested separately from this adapter.

All existing printable-text validation remains: malformed encodings, controls,
and an initial zero-width character fail. Unicode assignment does not override
what the installed libc regards as printable. A UTF-8 locale with older character
data may reject newer Unicode characters even though their boundary properties
are in the table. No normalization occurs.

Widths remain the sum of the system `wcwidth` values consumed by curses. This
policy changes boundaries, not glyph shaping, ambiguous-width preference or
curses' storage capacity. Combining sequences too long for a curses complex cell
can pass measurement and fail drawing. Native spans, prepared rows, snapshots,
`textwrap` and document reflow retain their existing clipping/storage contracts.
A grapheme query is not permission to assume that a later native draw fits a
terminal's shaped width.

## Fields and forms

`zdraw-input-init text [byte-limit [cell|grapheme]]` selects the field policy. The
usual 4096-byte default and 32767-byte maximum remain. The optional association
key `boundary` records the choice; missing or empty means `cell`. Every editing,
selection, paste and display query reads that field's policy. Cursor and anchor
remain source byte offsets at valid boundaries. After a splice that joins two
units, the caret advances to the joined unit's end.

Rendering clips complete selected-policy units at the viewport's right edge.
A unit wider than the viewport is omitted and the software caret uses a blank
cell; it is not partially drawn. This does not solve terminal/curses width drift.
Locale or option changes that make the policy unavailable leave text and selection
unchanged. Restore the locale/option before continuing. Active paste still follows
the existing drain/cancel rules, with validation on completion.

Forms preserve an individual field's `boundary` through loading, editing and
validation. Set it immediately after form initialization, while anchors are at
the ends, to opt in a field:

```zsh
zdraw-form-init Name '👩‍💻' required
zdraw_ui_form[1,boundary]=grapheme
zdraw-form-action edit backspace
```

Changing the policy on an already edited association requires cursor and anchor
to be valid under the new policy; invalid anchors are rejected without changing
the field. Default fields and existing document word wrapping remain available.
The tests cover joining across insertion/deletion, selection, split UTF-8 paste,
right-edge clipping, locale changes and retained document source anchors.

## Corpus and real terminal evidence

The [18-case corpus](../tests/unicode/corpus.json) records literal text, code points
and expected terminal-profile units. It covers combining marks, storage overflow,
modifiers, joiners, flags and odd flag runs, variation selectors, keycaps,
ambiguous-width characters, CJK, Hangul, Indic conjuncts, spacing marks, zero-width
space and rejected leading marks.

The [recorded matrix](portability/unicode-matrix-2026-09-10.json) and
[captures](portability/unicode-captures) compare native geometry, retained cell
text and actual pixels in private Xvfb terminals. They use public Zsh 5.9.2,
wide ncurses 6.5, Linux and `C.UTF-8`. The font request is `monospace` at size 12,
with the installed fontconfig fallback. These are observations of those exact
configurations, not assertions for every font or terminal version.

| Sequence | Native column sum | Xterm 407 raw cursor advance | Kitty 0.44.0 raw cursor advance |
| --- | ---: | ---: | ---: |
| `é` | 1 | 1 | 1 |
| `👍🏽` | 4 | 4 | 2 |
| `👩‍💻` | 4 | 4 | 2 |
| `👨‍👩‍👧‍👦` | 8 | 8 | 2 |
| `🇳🇴` | 2 | 2 | 4 |
| `❤️` | 1 | 1 | 2 |
| `1️⃣` | 1 | 1 | 2 |
| `क्ष` | 2 | 2 | 1 |

The flag observation is the cursor advance of the raw sequence followed by a
marker, not a claim that the painted flag occupies four cells. Cursor reports,
pixels and retained cell data answer different questions.

Xterm directly and through tmux `next-3.3` reports widths matching libc for this
corpus, but the captures show separate family glyphs and missing/substitute
characters. Screen 5.0.1 reports the same widths while visibly corrupting several
combining/joining examples. Kitty shapes joined emoji in these captures, while
its advances diverge from the native cell model. Retained curses readback remains
multiple cells even when the emulator paints one glyph. The nine-character
combining case measures one column but native drawing rejects it instead of
silently losing marks. Initial combining marks are rejected by text queries.

The raw phase explicitly owns its terminal input, emits the fixed corpus and
requests cursor positions; the native phase owns a separate curses session and
waits for screenshot acknowledgement before cleanup. Only these probe programs
use cursor-report queries. The production boundary API never does. Screenshots
are sampled after 200 ms of settling and do not measure physical display latency.
Other terminal versions, actual SSH connections, IMEs, bidi editing and a full
alternate-curses module remain untested.

```sh
python3 scripts/portability/unicode-matrix.py \
  --output .build/portability/unicode-matrix.json \
  --captures .build/portability/unicode-captures
```

The optional probe requires Xvfb, xterm and ImageMagick `import`; tmux, screen and
kitty are optional cases. It uses private sessions and a private display, never
the user's existing terminal or desktop.

## Data provenance and regeneration

The generated table is checked in at
[`zdraw_grapheme_data.h`](../Src/Modules/zdraw_grapheme_data.h), with the complete
Unicode data license. [Source URLs and SHA-256 digests](../tests/unicode/sources.json)
pin GraphemeBreakProperty, DerivedCoreProperties, emoji-data and the conformance
vectors. [Unicode's license](../tests/unicode/LICENSE.txt) covers that data; the
original zdraw engine uses the module's existing license.

```sh
python3 scripts/generate-graphemes.py        # Download into .build/ if needed.
python3 scripts/generate-graphemes.py --check
ZSH_BUILD_ROOT=/path/to/zsh-5.9.2 make test
```

Normal builds use only the checked-in headers. Regeneration needs Python's
standard library and the pinned downloads (or an already populated `--cache`).
Updating the Unicode version is an explicit data-and-tests change. The generated
header dependencies and additive Zsh integration patch include both headers.
