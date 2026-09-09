# zdraw

A portable, general-purpose terminal drawing and interaction module for Zsh,
derived from Zsh's `zsh/curses` module. `zdraw` has its own module identity,
builtin and parameters, and develops its API independently. General-purpose
fixes and extensions remain candidates for contribution to Zsh.
It has no dependency on another application or a contributor's local setup.

Applications own their layouts, themes and event-loop policy; `zdraw` supplies
terminal primitives. The [exploration checklist](docs/roadmap.md) tracks candidate
additions and completed milestones.

**`zdraw geometry array`** queries the controlling terminal's current rows
and columns without a subprocess or screen update. The read-only
**`zdraw_features`** array reports optional compiled support without accessing
the terminal, including in headless processes.
See the [design notes](docs/design.md) for scope and future work.

**Custom borders** support eight configurable edge/corner characters, including
rounded Unicode borders on wide curses builds. A standalone
[border showcase](examples/borders.zsh) demonstrates ASCII, rounded and double
borders. Color allocation now validates numeric values and fails safely when
the library or module pair limit is reached.

**`zdraw colorinfo association`** reports the current session's color
capabilities, usable limits and remaining pair capacity. It works headlessly
before initialization, reporting unavailable values as `unknown`.

**`zdraw spans window row column style text ...`** draws a row of differently
styled text in one module call, preserving cursor and window state. See the
[API](#styled-span-batching) and [reproducible benchmark](benchmarks/README.md).

**Opt-in truecolor** accepts `#RRGGBB` colors through curses when the build and
terminal description support 24-bit direct colors. See [the API](#truecolor)
and the standalone [gradient example](examples/truecolor.zsh).

**Cell-aware clipping** adds headless `textinfo` measurement and `spansclip`
drawing with a shared column budget. It uses system character widths and adds
no Unicode database or grapheme segmentation. See the [contract](#cell-aware-clipping)
and [headless example](examples/clipping.zsh). `textpos` maps source byte offsets
and displayed columns to complete clipping units; see
[text hit-testing](#text-positions-and-hit-testing).

**Structured input** returns character, key, resize and optional mouse records
through an association. **Prepared styled rows** decode reusable drawing data
once, with explicit release and session cleanup. See [input](#structured-input),
[prepared rows](#prepared-styled-rows) and the [event inspector](examples/events.zsh).

## Build and test

Prerequisites:

- Zsh to run the build script, GNU Make, a C compiler, and standard Unix build
  tools (including a POSIX shell, Awk, and Sed).
- Autoconf (including Autoheader), M4, and Patch to regenerate Zsh's configuration
  with the optional drawing function checks.
- Curses development headers and libraries, such as ncurses, and a terminfo
  database containing `xterm-256color` and `vt100` for the tests. The truecolor
  tests also use ncurses `tic -x` to compile private fixtures under `.build/`.
- Python 3.9 or newer and an installed UTF-8 locale for the PTY tests. The drawing
  tests select a UTF-8 locale from `locale -a`; `ZDRAW_TEST_LOCALE` overrides it.
- Curl, Tar, and Xz for the download example below.

From this repository's root, download and extract a public
[Zsh release](https://www.zsh.org/pub/), then build:

```sh
mkdir -p .build/downloads .build/sources
curl -fL https://www.zsh.org/pub/zsh-5.9.2.tar.xz \
  -o .build/downloads/zsh-5.9.2.tar.xz
tar -xJf .build/downloads/zsh-5.9.2.tar.xz -C .build/sources
export ZSH_BUILD_ROOT="$PWD/.build/sources/zsh-5.9.2"
make test
```

The release archive's SHA-256 is
`36fa734374b44783582cec09bcd67822e2f992c779ec1624ab5596df078d2f81`,
as listed in the publisher's [checksums](https://www.zsh.org/pub/SHA256SUM).
Use `gmake` instead of `make` on systems where GNU Make has that name.

The build copies the supplied source tree to `.build/zsh`, adds this module,
applies the build integration patch in `patches/`, and regenerates configuration
using Autoconf and Autoheader. Configured copies are rechecked with their saved
configuration arguments. It uses Zsh's own build rules to build both the shell and
its modules; tests use that matching shell. All build products stay in `.build/`.
No installation, administrator access, or changes to the supplied tree are needed.
The tests create their own pseudo-terminal, so they also run without an
interactive terminal. `make build` builds without running tests.

An extracted release needs no prior configuration. Standard compiler environment
variables such as `CC`, `CPPFLAGS`, `CFLAGS`, and `LDFLAGS` can be set before the
first build, including paths to curses installed in a nonstandard location.
Alternatively, set `ZSH_BUILD_ROOT` to your own configured in-tree Zsh build
using relative source paths. Separate source/build trees are not supported by
the copy-based harness. Run `make clean` before changing sources or configuration;
it removes the working copy and staged module, preserving downloads and extracted
sources.

## Try the module

From the repository root, in a terminal, start the newly built shell:

```sh
.build/zsh/Src/zsh -df
```

Then run these Zsh commands:

```zsh
module_path=("$PWD/.build/modules")
zmodload zdraw
typeset -a size
zdraw geometry size && print -r -- "$size[1] rows, $size[2] columns"
```

The staged module is `.build/modules/zdraw.so` on systems using the `.so`
module suffix; the build uses the suffix selected by Zsh on other systems.
Type `exit` to leave the test shell.

To use the module in an existing Zsh installation, build against sources and
configuration matching that shell's ABI. In a fresh process, prepend the staged
module directory to `module_path` before `zmodload zdraw`. Changing
`module_path` does not replace an already loaded module. To test a particular
matching shell, run `ZSH_TEST_SHELL=/path/to/zsh make test` with `ZSH_BUILD_ROOT`
still set. A binary built for one Zsh configuration or operating system is not
a universal binary.

The public Zsh 5.9.2 release is the tested source baseline. The implementation
uses Zsh's platform configuration and curses abstractions; Linux is currently
verified, while BSD/macOS and alternative curses libraries still need testing.

## Migrating from this project's zcurses module

The module is now loaded with `zmodload zdraw`. Update consumers as follows:

| Previous name | New name |
| --- | --- |
| `zmodload zsh/curses` | `zmodload zdraw` |
| `zcurses ...` | `zdraw ...` |
| `zcurses_features`, `zcurses_colors`, `zcurses_attrs`, `zcurses_keycodes`, `zcurses_windows` | Corresponding `zdraw_*` parameters |
| `ZCURSES_COLORS`, `ZCURSES_COLOR_PAIRS` | `ZDRAW_COLORS`, `ZDRAW_COLOR_PAIRS` |
| `ZCURSES_TEST_LOCALE`, `ZCURSES_MAKE` | `ZDRAW_TEST_LOCALE`, `ZDRAW_MAKE` |

Subcommands, arguments, return statuses and terminal behavior are unchanged.
There are no automatic aliases for the old names. Stock `zsh/curses` remains
separate and retains its `zcurses` builtin and parameters. Only one module
should own an active curses session in a process; end and unload it before
switching modules.

Run `make clean` once when migrating an existing build cache, then rebuild with
`ZSH_BUILD_ROOT` set as above. The staged artifact is now `zdraw.so` (or the
platform's equivalent suffix) at the root of `.build/modules`.

## API

### Compiled feature discovery

After loading the module, use Zsh's standard module-feature check to discover
whether the read-only `zdraw_features` array is available:

```zsh
zmodload zdraw
if zmodload -F -e zdraw +p:zdraw_features; then
  if (( ${zdraw_features[(Ie)geometry]} )); then
    print -r -- 'Native terminal-size queries are compiled in.'
  else
    print -r -- 'Native terminal-size queries are not compiled in.'
  fi
else
  print -r -- 'Compiled feature information is unavailable.'
fi
```

This example works without a controlling terminal or `zdraw init`. When this
parameter is unavailable, the feature check returns 1 silently without invoking
an unsupported `zdraw` command. A missing or disabled parameter means support is
unknown, so the application chooses its fallback policy.

| Feature name | Compiled support |
| --- | --- |
| `geometry` | Terminal-size queries through `TIOCGWINSZ` |
| `resize` | Curses resizing through `resize_term` |
| `mouse` | Ncurses mouse input and configuration |
| `default_colors` | The `default` color name through `use_default_colors` |
| `custom_borders` | Eight-character borders, including printable ASCII |
| `wide_borders` | Unicode borders through `setcchar` and `wborder_set` |
| `colorinfo` | Runtime color capabilities and allocation information |
| `truecolor` | Optional ncurses extended-color APIs and terminfo queries for RGB |
| `structured_events` | Associative input records using the curses decoder |
| `norefresh_events` | Opt-in event input without refreshing drawing windows (ncurses) |
| `wide_events` | Locale-based wide-character input; otherwise events contain raw bytes |
| `resize_events` | Terminal size queries or curses resize key notifications |
| `prepared_rows` | Immutable session-scoped styled rows, with clipping and inspection |
| `styled_spans` | Single-row styled text batching |
| `wide_spans` | Wide characters and representable combining sequences in spans |
| `clipped_spans` | Styled-span drawing with one shared column budget |
| `textinfo` | Headless text measurement and prefix clipping; printable ASCII always supported |
| `text_positions` | Headless mapping between source byte offsets and displayed columns |
| `wide_text` | Locale-based multibyte measurement/clipping, independent of wide curses support |

Read the array as a set: order is unspecified, and future names should be ignored
unless understood. A listed feature can still fail at runtime, for example when
`geometry` has no controlling terminal. These names describe compiled support;
they do not report terminfo data, negotiated protocols, or ABI compatibility.
The array is unchanged by initialization, resizing, and `end`. Reading it emits
no output, consumes no input, and changes no terminal state. It can also be loaded
alone with `zmodload -F zdraw p:zdraw_features`.

### Terminal geometry

```text
zdraw geometry array
```

Returns a two-element array: **rows, columns**. It queries the controlling
terminal directly, works before `init` and after `end`, and leaves curses window
dimensions and terminal modes alone. There is no default output parameter.

| Status | Meaning |
| --- | --- |
| 0 | Dimensions assigned successfully |
| 1 | Query failed, a dimension was zero, assignment failed, or arguments were invalid |
| 2 | This build lacks `TIOCGWINSZ` |

A failed terminal query leaves the output parameter unchanged. Check the return
status before using it. `position stdscr array` continues to describe the curses
window; `geometry` describes the terminal, which may have changed independently.

The [upstream-format documentation](Doc/Zsh/mod_zdraw.yo) includes the extension.
The PTY tests exercise live resizing before curses processes input, zero-sized
terminals, local and readonly parameters, argument errors, operation before and
after curses, terminal-mode restoration, no controlling terminal, and existing
window/text/color/refresh operations. Feature tests cover headless discovery,
read-only enforcement, module feature lifecycle, and temporary builds with
optional support disabled and with the preserved stock module.

### Custom borders

```text
zdraw border window [left right top bottom top_left top_right bottom_left bottom_right]
```

The existing `zdraw border window` operation is unchanged. The new form takes
all eight characters; each empty argument selects that edge/corner's curses
default, while a literal space selects a space instead of a border glyph
(curses' normal background-character substitution still applies).
For example, after creating a
window named `panel` in a UTF-8 session:

```zsh
zdraw border panel '│' '│' '─' '─' '╭' '╮' '╰' '╯'
zdraw refresh panel
```

Custom borders preserve the cursor, current window attributes and interior
cells. They inherit the window's drawing attributes and do not refresh the
screen. Windows must have at least two rows and columns. Glyphs must be single
printable characters with system display width one; controls, combining marks,
multi-character strings and double-width characters are rejected before drawing.

Check `custom_borders` in `zdraw_features` before using the new form and
`wide_borders` before selecting Unicode glyphs. Printable ASCII works on narrow
builds. Unicode also requires a suitable locale and Zsh's `MULTIBYTE` option.
Status 0 means success, 1 means invalid arguments or a curses failure, and 2
means a non-ASCII glyph was requested without compiled wide-border support.
A curses failure during drawing can leave a partial border.

Run the showcase with the matching shell, in a UTF-8 terminal of at least
19 rows and 50 columns:

```sh
.build/zsh/Src/zsh -df examples/borders.zsh
```

### Color and character correctness

`ZDRAW_COLORS` and `ZDRAW_COLOR_PAIRS` remain the library's raw counts.
Numeric colors must contain only decimal digits, be below `ZDRAW_COLORS`, and
fit in C's `short` type. Index 255 is valid on a 256-color terminal. Pair IDs
also must fit in `short`; allocation fails before exceeding either that range
or the library limit. Existing pairs remain usable after exhaustion. Named and
numeric spellings retain separate cache entries and their existing `querychar`
readback spelling. Opt-in [truecolor](#truecolor) adds a separate RGB syntax
without widening decimal indices or pair IDs.

The wide-character `char` operation now decodes Zsh's internal string encoding
and passes a terminated buffer to curses, as does the background operation.
`querychar` allocates enough space
for the full curses cell, retaining its existing first-character result when
combining marks are present. Drawing tests cover these paths, custom borders,
deferred refresh, color validation and pair exhaustion, and a temporary module
build using narrow drawing paths.

### Runtime color information

```zsh
typeset -A colors
zdraw colorinfo colors
```

This replaces the named ordinary writable association, creating it if absent.
Other types, readonly or special parameters, and subscripted names are rejected.
There is no default output variable. Status 0 means assignment succeeded; status
1 means invalid arguments or assignment failure. A successful query does not
imply that color drawing is available.

Before `zdraw init` and after `zdraw end`, `initialized` is `0` and all other
fields below are `unknown`. During a session:

| Key | Meaning |
| --- | --- |
| `initialized` | `1` while the module has a curses session |
| `has_colors` | Curses' color capability for the terminal type: `0` or `1` |
| `color_started` | Whether `start_color` succeeded: `0` or `1` |
| `default_colors` | Whether `use_default_colors` succeeded: `0` or `1`; `0` if unavailable or color initialization failed |
| `can_change_color` | Curses' palette-redefinition capability: `0` or `1` |
| `truecolor_supported` | `0` or `1`: this build and initialized terminal description support the RGB interface |
| `truecolor_enabled` | `0` or `1`: the application has enabled RGB color arguments in this session |
| `rgb_min`, `rgb_max` | Inclusive packed RGB range, independent of `color_limit`; `unknown` if unsupported |
| `colors`, `color_pairs` | Raw library counts after successful color initialization; otherwise `unknown` |
| `color_limit` | Number of representable numeric colors: `min(colors, SHRT_MAX + 1)`; indices start at zero |
| `pair_limit` | Available nonzero pair slots: `max(0, min(color_pairs - 1, SHRT_MAX))`; also the highest allocatable pair ID |
| `bg_pair_limit` | Highest pair ID representable by `bg`, accounting for its narrower packed-color path where applicable |
| `query_pair_limit` | Highest pair ID representable by `querychar`, accounting for its narrower readback path where applicable |
| `spans_pair_limit` | Highest pair ID representable by `spans`, accounting for its packed ASCII path; zero if unavailable |
| `pairs_used` | Nonzero pair IDs allocated in this session |
| `pairs_free` | `pair_limit - pairs_used` |

If color initialization fails, module limits and allocation counts are zero,
while raw library counts remain `unknown`. A monochrome terminal can have
`color_started=1` with zero colors; check capabilities and limits as well.
The narrower `bg` and `querychar`
limits apply to **pair IDs**, not foreground/background color indices. Limits
are upper bounds; they do not reserve resources or guarantee a drawing call.
Palette mutability does not establish direct RGB drawing support.

The query reads session state and cached library data. It does not initialize
curses, refresh the screen, allocate pairs, consume input, emit terminal output
or negotiate protocols. Capabilities reflect curses' terminal description.
The legacy count parameters and drawing behavior are unchanged. Applications
can check the `colorinfo` entry in `zdraw_features` before using the command.
Ignore unfamiliar future keys; association order is unspecified.

Repeated queries and repeated `init` calls leave pair allocations alone. Existing
allocation rules still apply: distinct spellings can consume separate slots,
window deletion does not release pairs, and `end` clears them. This also preserves
the existing first-use behavior of `default/default`.

The standalone example captures values before initialization, after initialization,
after allocating a pair, and after cleanup, then prints them with the terminal
restored:

```sh
.build/zsh/Src/zsh -df examples/colors.zsh
```

Tests cover headless and local assignment, readonly/invalid targets, lifecycle
and allocation accounting, monochrome terminals, failed color initialization,
failed or absent default-color support, and narrow builds.

## Source and upstream contribution

- `Src/Modules/`: forked module sources, retaining Zsh's file layout.
- `Doc/Zsh/`: module documentation in Zsh's native format.
- `upstream/`: preserved original sources, checksums and provenance.
- `tests/`: standalone module tests, with no application dependencies.
- `examples/`: standalone Zsh demonstrations of module primitives.
- `patches/`: small changes to Zsh's configuration checks, applied in `.build/`.
- `.build/`: ignored build inputs and outputs.

Run `make -s patch > zdraw.patch` to export an additive integration patch for
the selected Zsh source release. It adds the module sources, build descriptor,
key generator and manual, plus manual registration and optional configuration
checks; it leaves the stock `zsh/curses` sources intact. Apply it with `patch -p1`, then regenerate
`configure` and `config.h.in` with `autoconf` and `autoheader` and rerun configure.
For a feature submission to `zsh/curses`, adapt the relevant changes to its
original names and interface instead of submitting the whole integration patch.
See [provenance](upstream/README.md) for the baseline's origin. An upstream
submission also needs tests adapted to Zsh's test harness and review against the
maintainers' current tree. This project is not part of the official Zsh distribution.

The original copyright notices and [Zsh licence](LICENCE) are retained.

## Styled-span batching

```zsh
zdraw spans panel 1 2 \
  'bold,cyan/black' 'CPU ' \
  'green/black' '23%' \
  '' '  ready'
zdraw refresh panel
```

Supply at least one `style text` pair. Row and column are zero-based, unsigned
decimal coordinates within the window. A style is empty or a comma-separated
list of existing attribute names (`blink`, `bold`, `dim`, `reverse`, `standout`,
`underline`) and at most one existing `foreground/background` color pair.
Tokens cannot be empty or contain whitespace; `+`/`-` attribute changes are not
accepted. Arguments are data and are never evaluated as shell code.

Each style is complete: omitted attributes are off, and an omitted color uses
reserved pair 0. Window/background attributes and background-character
substitution do not affect spans. `default/default` follows the existing color
cache rules; an empty style needs no color support or allocation. Empty texts
are valid, still have their styles validated, and do not allocate colors.

The command preserves the cursor, current attributes, color pair and background.
It neither wraps nor scrolls, even at the bottom-right cell, and does not refresh
or read input. `refresh` remains the application's responsibility. As with other
curses writes, replacing part of an existing wide character can clear its other
cells to avoid leaving an orphaned half-character.

For `spans`, text must fit in the remaining columns of that row; it is never
clipped. Use the separate `spansclip` command for bounded prefix drawing. Tabs,
newlines, other controls, NULs, invalid encoding, and unrepresentable text are
rejected. The `wide_spans` path uses the current locale's system `wcwidth`, with
the `MULTIBYTE` option required for non-ASCII text. A spacing character can have
following zero-width characters within the same span, up to the curses complex
character capacity. A span cannot begin with a zero-width character. This is
curses character handling, not Unicode grapheme segmentation or a guarantee of
emoji/ZWJ rendering. Builds without `wide_spans` accept printable ASCII only.

Status is 0 on success, 1 for invalid arguments, text that does not fit, color
allocation failure or a curses error, and 2 if span drawing is not compiled in
or non-ASCII text needs the unavailable wide path. Check `styled_spans` and
`wide_spans` in `zdraw_features` before selecting an application fallback.

All arguments and text are validated before color allocation or cell changes.
Pairs share the existing session cache and are never recycled. A later
allocation failure leaves earlier successful allocations in the cache, but
leaves window cells unchanged. A curses write error can leave partial drawing;
applications can redraw after failure. `colorinfo[spans_pair_limit]` reports the
highest usable pair ID: the normal `pair_limit` on the wide path, further limited
by packed curses attributes on the ASCII path, or zero when spans are unavailable.
Before initialization and after `end` this value is `unknown`. The narrow path
rejects a pair that exceeds its limit instead of truncating the ID.

## Cell-aware clipping

```zsh
typeset -A info
zdraw textinfo info $'e\u0301界b' 2
# info[text]        = e + combining acute
# info[width]       = 1
# info[remainder]   = 界b
# info[total_width] = 4
# info[truncated]   = 1
```

`zdraw textinfo association text [columns]` measures text and optionally keeps
the longest fitting prefix. It works before `init`, after `end`, and without a
controlling terminal or `TERM`. Omit the budget to measure and return all text.
The named ordinary writable association is replaced, or created if absent, with:

| Key | Value |
| --- | --- |
| `text` | The retained prefix, preserving original bytes |
| `remainder` | The omitted suffix; concatenating it with `text` reconstructs the input |
| `width` | Columns occupied by the prefix under the system-width model |
| `total_width` | Columns occupied by the entire input under that model |
| `truncated` | `1` if any text was omitted; otherwise `0` |

A clipping unit is **one positive-width character followed by all immediately
following zero-width characters**. Widths come from the current locale's system
`wcwidth`, matching the character-width function used by curses, and not Zsh's
optional Unicode width table. Complete multibyte characters are preserved.
A unit is retained only if its positive-width character fits; its zero-width
suffix is retained with it. The first non-fitting unit ends the prefix, even if
some later, narrower character could fit in the leftover space. No partial wide
character, padding, ellipsis, replacement character or normalization is inserted.
The caller can choose such presentation policies in Zsh.

Text must be printable and start with a positive-width character, or be empty.
Tabs, line breaks, other controls, NULs, invalid encoding, and leading zero-width
characters are rejected. A zero budget is valid and retains no nonempty text.
The entire input is validated, including any omitted suffix. Budgets are unsigned
decimal integers from zero through `INT_MAX`; an input whose total width exceeds
`INT_MAX` is rejected. Invalid input leaves an existing association unchanged and
does not create a missing one. Readonly/special parameters, subscripts and other
parameter types are rejected, following `colorinfo`'s assignment contract.

Status is 0 on successful measurement or clipping, 1 for invalid input or
assignment failure, and 2 for non-ASCII text on a build without `wide_text`.
Multibyte text requires a suitable locale and the `MULTIBYTE` option. Without
`wide_text`, printable ASCII is supported. With that feature but an unsuitable
locale or `MULTIBYTE` unset, non-ASCII text fails with status 1. `wide_text` is
independent of `wide_spans`: being able to measure text does not establish that
the linked curses library can draw it. Measurement does not enforce curses'
complex-character storage limit; styled drawing does.

### Text positions and hit-testing

```zsh
typeset -A hit
zdraw textpos hit $'e\u0301界b' column 2
# hit[text] = 界; columns [1, 3); original UTF-8 bytes [3, 6)
zdraw textpos hit $'e\u0301界b' byte 4
# The same group, even though byte 4 is inside its UTF-8 encoding.
```

`zdraw textpos association text column|byte offset` maps a position to the
complete clipping unit containing it. Its unit and validation rules are the
same as `textinfo`: one positive-width character followed by its zero-width
characters. Either column of a double-width character selects the entire unit;
any byte of a base or its following marks selects that same unit.

All offsets are **zero-based**, and range ends are **exclusive**. Byte offsets
count the original encoded bytes, not Zsh character indices or internal escapes.
The ordinary writable association is replaced, or created if absent, with:

| Key | Meaning |
| --- | --- |
| `text` | The complete selected unit, preserving its original bytes |
| `prefix`, `remainder` | Text before and after the unit; `prefix + text + remainder` reconstructs the input |
| `byte_start`, `byte_end` | Source byte range of the unit |
| `column_start`, `column_end` | Displayed column range of the unit |
| `total_bytes`, `total_width` | Length and width of the entire input |
| `at_end` | `1` at the end boundary; `0` for a selected unit |

An offset exactly equal to the chosen total returns an empty range at the end,
with all input in `prefix`. Thus offset zero is valid for empty text. An offset
past the end fails; it is not clamped. Offsets, total bytes and total width must
fit in `INT_MAX`. Decimal offsets are parsed literally, without shell evaluation.

The entire input is checked before assignment, including text after the hit.
Status 0 means success, 1 means invalid text/arguments or assignment failure,
and 2 means non-ASCII text on a build without `wide_text`. Invalid input leaves
the target unchanged. Like `textinfo`, this query works without initialization
or a terminal, reads no input and emits no terminal output. It scans the input
once per query and returns one range, without constructing a full position map.

These are the module's clipping units, **not Unicode grapheme clusters**. A
zero-width joiner stays with its preceding base; the next positive-width
character starts a new unit. The query does not model terminal emoji shaping,
normalize text or enforce curses' combining-character storage limit. Results
use the current locale and `MULTIBYTE` setting; recompute after changing those
or the text. To hit-test a clipped display, query the prefix returned by
`textinfo`, subtracting the drawing origin from the mouse's screen coordinates.

The [hit-testing example](examples/hit-test.zsh) combines prepared drawing,
structured events and this query. Arrow keys move the selected column; optional
mouse input selects a complete unit:

```sh
.build/zsh/Src/zsh -df examples/hit-test.zsh
.build/zsh/Src/zsh -df examples/hit-test.zsh --mouse
```

### Clipped styled spans

For drawing a composite stream of complete style/text runs:

```zsh
zdraw spansclip panel 1 2 12 \
  'bold,cyan/black' 'Status: ' \
  'green/black' 'ready and waiting'
zdraw refresh panel
```

`zdraw spansclip window row column columns style text [style text ...]` uses
one budget across all spans. The effective budget is the smaller of `columns`
and the space to the window's right edge. Coordinates must be inside the window,
even for a zero budget. Styles, cursor/background preservation, status codes and
refresh behavior follow `spans`; ordinary `spans` retains its overflow error.
Unused columns and cells after the prefix are left alone, subject to curses'
normal repair of an overwritten wide character. Clearing stale text is the
application's responsibility.

Each nonempty span must start with a positive-width character. Keep a base and
its zero-width suffix in the **same span**, even when styles on adjacent runs
match; this avoids assigning conflicting styles within one curses complex
character. All text and styles are validated before drawing, including clipped
runs. Unrepresentable combining sequences are rejected rather than silently
truncated by curses. Entirely omitted or empty spans allocate no color pairs.
A later allocation failure can retain earlier successful allocations but changes
no cells; a curses write error may partially draw, as with `spans`.

These are **cell-width rules, not grapheme boundaries**. Emoji ZWJ sequences,
regional-indicator flags and skin-tone sequences can be split between their
positive-width characters. Zero-width variation selectors stay with the preceding
character but do not alter the width reported by `wcwidth`. Ambiguous-width
characters follow the system locale's policy. A terminal emulator's shaping or
font policy can differ from this model. The module adds no Unicode tables,
segmentation dependency, terminal-width probing, or promises of grapheme-safe
rendering. Neither query nor drawing consumes input or refreshes the terminal.

Run the headless example using the matching staged shell:

```sh
.build/zsh/Src/zsh -df examples/clipping.zsh
```

## Truecolor

Start the **matching built shell** with a direct-color terminal description that
is appropriate for the actual terminal. For an xterm-compatible terminal that
supports the entry's RGB sequences, and with `xterm-direct` installed:

```sh
TERM=xterm-direct .build/zsh/Src/zsh -df examples/truecolor.zsh
```

Inside an initialized session:

```zsh
zdraw truecolor on || return
zdraw attr panel 'bold' '#80c0ff/#181818'
zdraw bg panel '#e0e0e0/#181818'
zdraw spans panel 1 2 'bold,#80c0ff/#181818' 'RGB text'
zdraw refresh panel
```

The `truecolor` subcommand takes exactly `on` or `off`. It returns 0 on success,
1 for invalid arguments or use outside a curses session, and 2 when `on` cannot
be supported by the current build/library/terminal description. `off` succeeds
within any session. RGB starts disabled; repeated `init` preserves the current
setting, and `end` resets it. `colorinfo` reports support and enabled state
separately. Capability reporting itself does not opt in.

With RGB enabled, either side of a color pair accepts exactly `#RRGGBB`, with
six hexadecimal digits in either case. Quote color arguments. RGB can be mixed
with existing named colors, decimal indices and `default` where supported.
`attr`, `bg` and `spans` share the implementation and cache; subsequent character,
string and border drawing uses the selected pair as usual. `querychar` returns
the cached pair spelling, including hex case. Existing incremental-error behavior
of `attr` and validation behavior of `bg`/`spans` are preserved.

This interface requires optional ncurses extended-color functions, successful
color initialization, exactly 16,777,216 advertised colors, and an `RGB`
capability describing eight bits per channel (Boolean, numeric `8`, or string
`8/8/8`). A library color-content query confirms the encoding without allocating
pairs or writing to the terminal. `COLORTERM`, a large color count alone, palette
redefinition capability, and a guessed `TERM` name do not establish support.
A listed compiled `truecolor` feature can still be unavailable at runtime.

**Reserved low values:** some direct-color entries, including `xterm-direct`,
interpret values 0–7 as ANSI palette indices. The module reads the entry's `CO`
reservation, defaulting conservatively to eight when absent. RGB values below
`rgb_min` are rejected, including `#000000` when the minimum is eight; `black`
still selects the entry's palette black, whose RGB value may differ. An entry
with explicit `CO#0` and corresponding direct RGB setters can represent the
entire range, including exact black and `#000001`. The module trusts the selected
terminal description; it does not probe or rewrite it. Test fixtures cover both
encodings and inspect their emitted SGR bytes.

RGB values are carried as integers to `init_extended_pair`; allocated pair IDs
retain the existing `SHRT_MAX` bound. Decimal color indices retain their existing
`color_limit` even while RGB is enabled. Background, span and readback paths keep
their additional pair-ID limits. Different spellings can allocate distinct pairs;
pairs are never recycled and exhaustion fails normally. No palette approximation
or palette redefinition is performed. Applications choose their own fallback
when enabling RGB or requesting a particular color fails; drawing commands return
status 1 for rejected RGB arguments or allocation failure.

`truecolor off` rejects further RGB arguments, including cache hits, but leaves
existing cells, pairs and window styles intact. It does not recolor the screen;
normal drawing can still use an existing window style until the application
changes it. Re-enabling can reuse retained pairs. `end` releases the session's
pair cache and restores terminal state through the existing curses cleanup.

The subcommand and capability checks do not consume input, emit terminal replies,
refresh pending drawing, or alter input ownership. Input stays with the existing
`zdraw input` API. There is no additional negotiation or reply parser. All
screen output remains within curses and its retained-screen refresh machinery.

## Structured input

```zsh
typeset -A event
zdraw timeout stdscr 100
if zdraw event stdscr event; then
  case $event[type] in
    character) text=$event[text] ;;
    key)       key=$event[key] ;;
    resize)    rows=$event[rows] columns=$event[columns] ;;
  esac
fi
```

`zdraw event window association [mouse] [norefresh]` requires an initialized session and
returns one record through an ordinary writable associative parameter. It creates
an absent parameter and replaces an existing association, so fields from a
previous event do not linger. Invalid targets (including readonly, special,
scalar/array and subscripted parameters) are rejected before reading input or
acknowledging a pending size change. No implicit `REPLY` parameter is used.

| Field | Meaning |
| --- | --- |
| `type` | `character`, `key`, `resize` or `mouse` |
| `source` | `curses` for decoded input; `terminal` for a detected size change |
| `text` | One decoded character, or one raw byte on a narrow input build; empty for other events |
| `key` | Empty for characters; curses name without `KEY_` for named keys (such as `UP`, `F5`, `RESIZE`, `MOUSE`); decimal code for an unrecognized key |
| `code` | Numeric decoded character or curses key code; `unknown` for a synthesized terminal-size event |
| `encoding` | `multibyte` with wide curses input, `byte` otherwise; `none` for a synthesized size event |
| `modifiers` | `unknown` for characters/keys/resizes; a space-separated set of `SHIFT`, `CTRL`, `ALT` for a mouse event, empty if none were reported |
| `rows`, `columns` | Present only on resize; see the source distinction below |
| `id`, `x`, `y`, `z`, `buttons` | Present only on mouse events |

A `character` record can contain a control character or NUL; it does not claim
that the value is printable or came from an unmodified physical key. Wide input
uses the current locale and returns the numeric wide-character value in `code`;
narrow input returns bytes 0–255. Curses key codes are library-specific, not a
portable enumeration. Legacy decoding cannot reliably distinguish modifiers,
physical keys, paste, press/repeat/release or focus changes. Those are later
[roadmap milestones](docs/roadmap.md).

**Ownership and timing:** `event` and the existing `input` share one curses
input queue and decoder. Applications choose which call consumes the next item;
there is no background reader or additional protocol parser. Do not concurrently
read the terminal through `read`, ZLE or a subprocess. `event` enables keypad
decoding and inherits `zdraw timeout window milliseconds`. Zero polls; a finite
positive timeout is useful for observing size changes without keypresses.
Curses escape-sequence timing and inherited EINTR retries can extend a wait;
this is not a strict overall deadline. By default, curses may refresh a modified
window during a read, as with legacy input.

With `norefresh`, the call reads through a private one-cell ncurses pad and
**does not refresh drawing windows or present pending drawing**. It still uses
the same input queue, decoder and selected window's timeout; it leaves that
window's cursor and dirty state alone. Present the completed frame explicitly
with `zdraw refresh`. Keypad/mouse setup can emit terminal control sequences:
this is a presentation guarantee, not a promise of zero terminal output.
The pad is allocated lazily, is absent from `zdraw_windows`, and is released by
`end` or module unload. No additional terminal protocol or reader is enabled.

Check `norefresh_events` before requesting the flag. This path is currently
enabled only for ncurses, whose pad input behavior supports the guarantee;
other curses builds return status 2 before consuming input or acknowledging a
resize. The two flags may appear in either order, once each. For example:

```zsh
zdraw event stdscr event norefresh mouse
```

Terminal dimensions are checked before reading and after a failed read. A change
from the last acknowledged size returns `source=terminal`, `key=RESIZE` and
`code=unknown`, without consuming input, resizing windows or refreshing. Changes
between observations can coalesce; dimensions of zero or an unavailable query
are ignored. The initial comparison size comes from session initialization.
A decoded curses `KEY_RESIZE` returns `source=curses` and curses' current screen
dimensions instead. Applications can receive both kinds of notification and
should handle resizing idempotently. `event` installs no signal handler; a size
change during an indefinite read need not wake it immediately.

The optional literal `mouse` requests the existing curses mouse mask. It must
be supplied on each read that wants mouse reporting; an actual curses read
without it disables reporting. A synthetic resize record does not alter the
input modes. `zdraw mouse` configures the mask as before. Mouse `x` and `y` are
zero-based screen coordinates, not coordinates relative to the input window;
`id` and `z` are library-reported values. `buttons` is a space-separated list
such as `PRESSED1`, `RELEASED1` or `CLICKED1`; it may contain multiple states or
be empty for motion. No hit-testing or shortcut policy is added.
Mouse enable/mask flags now use distinct bits and reset at `end`, correcting
legacy bookkeeping so reporting disables and re-enables across sessions.

Status 0 means a record was assigned. Status 1 covers invalid arguments, a
failed read (including timeout/interruption), unavailable mouse data or failed
assignment, or input-pad allocation failure. Status 2 means a requested flag
(`mouse` or `norefresh`) lacks compiled support.
Failed reads leave the target unchanged; input already consumed cannot be
restored if subsequent record assignment fails. An absent target is not created
on an empty poll. Check `structured_events`, `wide_events` and `resize_events`
in `zdraw_features`; the last reports compiled geometry-query or curses resize
notification support, not a guarantee of runtime notification delivery.

Run the [event inspector](examples/events.zsh), which also reuses a prepared
heading, in the matching built shell and a UTF-8 locale:

```sh
.build/zsh/Src/zsh -df examples/events.zsh
# Opt in to mouse input:
.build/zsh/Src/zsh -df examples/events.zsh --mouse
```

Press `q` to exit. Unicode display needs the wide drawing path. The example uses
`always` for session cleanup; module unload also invokes the existing cleanup.

## Prepared styled rows

```zsh
# Within an initialized session:
zdraw prepare heading 'bold,cyan/black' 'CPU ' 'green/black' '23%'
zdraw draw stdscr 0 0 heading
zdraw draw stdscr 1 0 heading 6  # clip to six columns

typeset -A row
zdraw rowinfo heading row
zdraw unprepare heading
zdraw refresh
```

The `prepared_rows` feature adds:

```text
zdraw prepare name style text [style text ...]
zdraw draw window row column name [columns]
zdraw rowinfo name association
zdraw unprepare name
```

`prepare` validates and decodes a complete row, allocates its nonempty spans'
color pairs and copies the resulting cells into an immutable named object.
Names must be identifiers without subscripts and belong to a module namespace,
not shell parameters. A duplicate name is rejected; release it before reusing
it. Changing the original shell strings does not change a prepared row.
Preparation requires an initialized session and is independent of any window's
size. Empty rows are allowed and still have their styles validated.

Text, complete styles, combining-character storage, color validation and status
2 for unsupported non-ASCII drawing follow `spans`. They share the same compiler
and the same window-state-preserving writer. All text and styles are checked
before allocating colors. A failed later allocation can leave earlier color
pairs cached, but creates no named row and changes no cells. Preparation does
not read input or emit drawing output.

`draw` writes the prepared cells without reparsing styles/text or allocating
colors. Without `columns`, the whole row must fit. With a budget, it draws the
longest prefix fitting that budget and the window's right edge. A base and its
stored combining marks stay together; a double-width cell is never split. This
is still the existing cell-width contract, not full grapheme segmentation.
Unused cells are unchanged, subject to curses' repair of overwritten wide
characters. Coordinates must be in the window even for an empty row or zero
budget. Drawing neither wraps, scrolls, reads input nor refreshes; it preserves
the cursor, window attributes, color pair and background. A curses write error
can leave partial drawing.

Prepared cells are bound to the session, the `LC_CTYPE` locale name and the
`MULTIBYTE` option at preparation. `draw` rejects a changed locale/option even
for an ASCII row; restore the original setting or prepare another row. Cells
hold already allocated color-pair IDs. Like existing window styles, prepared
RGB cells remain drawable after `truecolor off`; preparing new RGB rows still
requires `truecolor on`. Preparation allocates colors for the complete row,
including cells that a later clipped draw might omit.

`rowinfo` reports `width` (terminal columns), `cells` (stored spacing-character
groups, not columns), `bytes`, `session_bytes`, `session_limit`, `locale` and
`multibyte`. Its target follows `colorinfo`'s ordinary-association rules and is
unchanged for an unknown row. The session allows 16 MiB of accounted prepared
row storage, including object records, names, locale names, cells and widths.
Hash-table/allocator overhead, transient compilation buffers and the shared
color cache are not included. Preparation checks a conservative capacity bound
based on column width before allocating colors; a wide row can therefore be
rejected even if its eventual stored-cell count would use fewer bytes.

`unprepare` frees the named row without changing drawn cells or reclaiming its
color pairs. `end` and module unload free every prepared row; a subsequent
session starts empty. Repeated `init` within the same session keeps rows.
All four commands require initialization. Status 0 is success, 1 is invalid
input, unknown/duplicate name, locale mismatch, storage/color failure or curses
failure, and 2 is unavailable compiled drawing support (including non-ASCII text
on the narrow preparation path).

Run `python3 benchmarks/spans.py --prepared` to compare repeated drawing with
legacy calls and ordinary spans. See [the benchmark notes](benchmarks/README.md)
for the reuse workload and measured results.
