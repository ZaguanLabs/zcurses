# Rendering lessons from btop

Reviewed 2026-09-08 against btop commit
`0999c29dc19d5900daacebe03637271662679ebd` and this fork at
`eb1a4ad09ba86f513dc3dddcd8c03b92a98ee0bf`. The local btop checkout's tracked
files were clean; its untracked patch was outside this review. References below
pin the public source revision, so btop is not a project dependency.

The strongest next steps are custom borders and reliable color limits, with
wide-character buffer fixes before expanding Unicode drawing. Styled spans are
worth measuring next. Btop's themes, graph algorithms and caching are useful
application examples; its ANSI output and input decoder should not become a
second terminal backend inside this module. These are design recommendations,
not implemented APIs or measured performance claims.

Implementation follow-up: the first drawing changes now fix the wide-character
buffers and color allocation bounds and implement the eight-glyph border form.
Runtime color information is also implemented. See the [current API](native-api.md#runtime-color-information).
The project has since been renamed to `zdraw`; the review retains the API names
used at the reviewed revision. The review below records the
findings at the revisions above; its references to defects describe that baseline.

## What creates the appearance and responsiveness

| Mechanism in btop | Evidence | Relevance here |
| --- | --- | --- |
| Rounded/square corners, line glyphs and title junctions | [`Symbols` and `createBox`](https://github.com/aristocratos/btop/blob/0999c29dc19d5900daacebe03637271662679ebd/src/btop_draw.cpp#L60), especially lines 279–338 | Expose border characters; let Zsh compose titles and separators |
| Semantic theme colors, RGB/256-color output and precomputed gradients | [`btop_theme.cpp`](https://github.com/aristocratos/btop/blob/0999c29dc19d5900daacebe03637271662679ebd/src/btop_theme.cpp#L42), conversion at 160–235, gradients at 321–388 | Keep theme roles and gradient generation in Zsh; improve the module's color contract |
| Cached meter strings for integer percentages 0–100 | [`Meter::operator()`](https://github.com/aristocratos/btop/blob/0999c29dc19d5900daacebe03637271662679ebd/src/btop_draw.cpp#L407) | Cache application output when data, geometry and theme are unchanged |
| Two samples per braille cell, alternating cached graph representations | [`Graph`](https://github.com/aristocratos/btop/blob/0999c29dc19d5900daacebe03637271662679ebd/src/btop_draw.cpp#L428) | A Zsh example can use glyph lookup tables and cached rows; no graph object is needed in C |
| Output assembled as strings and flushed with optional synchronized-output markers | [`Runner`](https://github.com/aristocratos/btop/blob/0999c29dc19d5900daacebe03637271662679ebd/src/btop.cpp#L719) | Distinguish shell-call overhead, curses screen diffing and terminal presentation |
| Clock redraw skipped when the formatted value is unchanged | [`update_clock`](https://github.com/aristocratos/btop/blob/0999c29dc19d5900daacebe03637271662679ebd/src/btop_draw.cpp#L340) | Redraw according to visible changes, with application-owned invalidation |

Btop's `createBox` also includes theme selection, filling, titles, panel numbers
and cursor placement. Its useful primitive is the configurable perimeter. The
complete function would put application policy into the module.

## Custom borders and lines

The current [`zccmd_border`](../Src/Modules/zdraw.c) passes eight zeros to
`wborder`, so callers get only curses' default perimeter. The dispatcher accepts
exactly a window argument. The manual's synopsis misleadingly includes an extra
`border` argument; that is an existing documentation defect, not an implemented
customization feature.

A small candidate extension is:

```text
zcurses border window [left right top bottom top_left top_right bottom_left bottom_right]
```

Preserve the existing one-argument operation. For the extended form, accept
exactly eight glyph arguments, with an empty argument selecting the corresponding
curses default and a literal space remaining a space. A first version can require
one printable character occupying one cell per nonempty argument. Reject controls,
invalid encoding, isolated combining marks, multi-character strings and wide
glyphs before modifying the window. Supporting base-plus-combining sequences can
be a separate contract; it is unnecessary for ordinary box-drawing characters.

Use Zsh's metafied-string decoding, explicit terminated wide buffers and actual
build checks for the functions used. Keep an ASCII path for narrow builds and
report unavailable wide support explicitly. Zsh 5.9.2's configuration checks
`setcchar` but does not currently check `wborder_set`; a portable patch may need
configuration changes, build-harness support and patch-export changes as well as
the module and manual.

The wide curses border and line APIs operate on cells without wrapping or moving
the cursor. They provide a natural implementation model, subject to feature
checks. See the [curses border/line manual](https://invisible-island.net/ncurses/man/curs_border_set.3x.html).

Preserve cursor position, current attributes, interior cells and deferred refresh.
Validate inputs first, but do not promise transactional rollback of arbitrary
curses failures. Define tiny-window behavior explicitly. Test default and custom
borders, all eight positions, colors/attributes, invalid input without drawing,
last-row/last-column placement and narrow builds.

Junctions do not require the module to understand panel layouts. Zsh can overlay
them as text. Horizontal and vertical line primitives would be useful follow-ups,
especially to avoid one shell call per cell for vertical separators. Measure that
use case separately from borders.

## Colors: existing support and actual gaps

The module already exposes `ZCURSES_COLORS` and `ZCURSES_COLOR_PAIRS` after
initialization, and accepts numeric `foreground/background` values. The
[`module manual`](../Doc/Zsh/mod_zdraw.yo) documents these. A new capability API
should supplement their semantics rather than duplicate them.

In [`curses.c`](../Src/Modules/zdraw.c), review these paths together:

- `zcurses_colorget` (337–406) parses numbers with `atoi` into `short` values,
  caches pairs by the original spelling, and increments the `short` `next_cp`
  before checking the library limit. Numeric suffixes and narrowing conversions
  need validation; aliases such as `red/black` and `1/0` can consume separate
  pairs. Canonicalization also affects the spelling returned by `querychar`, so
  it needs a compatibility decision.
- The parameter getters (1803–1819) return raw curses counts. Those counts do
  not establish the range safely usable through every module operation. Guard
  allocation before narrowing or incrementing beyond the representable range.
- The narrow `bg` path (968–974) explicitly rejects pair IDs at or above 256;
  other paths store or retrieve pair IDs through `short`. Extended support needs
  an end-to-end audit of allocation, attributes, backgrounds and cell queries.
- Initialization (461–490) calls `use_default_colors` without recording its
  return status. The compiled `default_colors` feature is therefore not a
  runtime success report.

The first color patch should establish predictable exhaustion, preserve already
drawn cells when allocation fails, and test boundary values. Do not recycle pair
IDs merely because they are absent from the latest draw request: retained cells
can still refer to them. Test named/numeric equivalents, malformed and oversized
numbers, default colors, repeated use, and behavior across `end`/reinitialization.
The manual's claimed maximum index of 254 on a 256-color terminal also needs
verification against the selected library and correction as appropriate.

A subsequent runtime query should distinguish initialization state, color
availability, successful default-color setup, palette mutability, raw library
counts and usable module limits. Keep unknown/uninitialized distinct from false,
and keep this information separate from `zcurses_features`.

Extended pair APIs use wider integer arguments, but changing the allocator alone
does not widen all drawing and readback paths. Palette redefinition, extended
pair counts and direct RGB output are separate capabilities. `can_change_color`
does not establish arbitrary RGB text support. See the [curses color manual](https://www.invisible-island.net/ncurses/man/curs_color.3x.html).

Btop produces RGB SGR sequences directly and converts to indexed color when its
`lowcolor` setting requests it. This is not proof of terminal capability detection
or a drop-in implementation for curses. Its `truecolor` configuration defaults
to true; `init_config` derives `lowcolor` from configuration and its argument.
Applications should initially quantize and budget their palettes for the actual
module limits. Direct RGB support deserves a separate feature proposal.

## Unicode: correctness before a new width API

Btop separates UTF-8 code-point counting from `wide_ulen` and clipping helpers.
See [`btop_tools.cpp`, lines 240–322](https://github.com/aristocratos/btop/blob/0999c29dc19d5900daacebe03637271662679ebd/src/btop_tools.cpp#L240)
and its [Unicode width table](https://github.com/aristocratos/btop/blob/0999c29dc19d5900daacebe03637271662679ebd/include/widechar_width.hpp#L1).
The table identifies Unicode 17.0.0 and chooses narrow ambiguous characters.
The helpers sum individual character widths; they do not segment grapheme
clusters. The wide clipping path also sizes its output byte buffer using the
number of wide characters, and the suffix helper uses a byte-based heuristic.
These routines need independent correctness work before any reuse.

Zsh already has width-aware parameter expansion: `${(m)#text}` and the `m` flag
with `l`/`r` padding. Consult the selected release's `Doc/Zsh/expn.yo`, parameter
expansion flags, and its `Src/utils.c` width helpers. Zsh's configured width policy
and the linked curses library can differ. A new API must define whether it
predicts curses cell placement or some other policy, as well as handling tabs,
newlines, invalid bytes, combining sequences and clipping at a wide cell. A
second independent width table can make alignment less consistent.

There are existing buffer defects to address first in this fork:

- `zccmd_char` (735–768) passes `&c`, a single `wchar_t`, to `setcchar`, which
  expects a terminated wide string. It also uses raw `mbrtowc` on a Zsh argument
  instead of the metafied-string conversion used by `zccmd_string`.
- `zccmd_querychar` (1430–1467) passes a single `wchar_t` as `getcchar`'s output
  buffer. The API writes a terminated string, potentially including combining
  marks. Even a plain character requires room for its terminator.

These are source-level findings, not sanitizer reproductions. The
[complex-character API contract](https://invisible-island.net/ncurses/man/curs_getcchar.3x.html)
specifies both buffer requirements. Fix them as focused correctness patches and
add regression coverage, including combining characters and instrumented builds.
Existing passing tests do not prove these accesses safe.

## Styled spans and refresh

Btop joins movement, attributes and text into output strings. In this module,
`move`, `attr` and `string` already update curses' retained state, and
`refresh window ...` calls `wnoutrefresh` for each window followed by one
`doupdate`. Preserve that model.

A useful experiment is one command carrying several explicit style/text spans.
Use structured arguments with literal text, not embedded ANSI or evaluated shell
commands. Specify full versus incremental styles, restoration of the caller's
attributes, final cursor position, clipping/wrapping, and partial-failure behavior.
Validate the argument structure before drawing. Call reduction is plausible;
speedup remains unmeasured.

Benchmark equivalent cell output using repeated existing commands and a span
prototype. Measure shell/rendering time with refresh excluded, then refresh time
and terminal bytes separately. Include unchanged frames, changed rows and a
complete repaint. Cache rows/spans in the application and invalidate them for
theme, geometry and content changes.

Btop's synchronized output uses DEC mode 2026, with `terminal_sync` enabled by
default in this revision. This affects terminal presentation rather than shell
call count. Any corresponding module extension must be opt-in, bound its active
lifetime, restore state on errors/end/unload, and define input ownership if
probing for support. Keep it separate from spans and existing refresh batching.

Btop owns stdin and terminal modes; its
[`Input::poll`/`get`](https://github.com/aristocratos/btop/blob/0999c29dc19d5900daacebe03637271662679ebd/src/btop_input.cpp#L95)
reads chunks and interprets keys and mouse events. That design cannot simply run
beside curses input. Preserve `zcurses input`; shortcut routing and mouse hit
regions remain application responsibilities.

## Suggested contribution sequence

1. Fix wide-character buffers and establish safe color allocation boundaries as
   independently reviewable correctness changes.
2. Add custom borders with standalone tests and a small shell example; correct
   the border synopsis in the same feature documentation.
3. Add runtime color information, then separately consider extended color paths.
4. Measure a styled-span prototype; add line drawing where measurements or clear
   usability benefits justify it.
5. Revisit width/clipping and synchronized output with explicit contracts and
   terminal/multiplexer coverage.

Use a standalone border/style showcase as the first consumer and zcoder as an
integration proving ground. The showcase should run with public Zsh sources and
the staged module, without requiring btop or zcoder. Themes, title placement,
meters, graphs and shortcuts belong in its Zsh layer.

Btop's reviewed source files carry Apache-2.0 notices; preserve provenance for
any future reuse. This review introduces no copied implementation. Small native
wrappers around curses fit this project's upstream direction.

## Review validation

At the initial review, `ZSH_BUILD_ROOT="$PWD/.build/sources/zsh-5.9.2" make test`
passed all seven tests
using the staged shell and module. This establishes the existing test baseline;
it does not validate the proposed APIs or reproduce the buffer defects under a
sanitizer. Only documentation changed during that initial review.
