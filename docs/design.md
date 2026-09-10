# Scope and project direction

`zdraw` develops portable, general-purpose terminal and curses primitives for
Zsh. Derived from `zsh/curses`, it has its own loadable module, builtin and
parameter namespace. Each extension should solve a shell-level problem and
preserve existing operation behavior. The project can experiment and evolve
independently while keeping useful fixes and extensions suitable for adaptation
to the official Zsh distribution. No application repository, developer
workstation, or specific distribution is a project dependency.

The rename preserves the inherited subcommands and their semantics under
`zdraw`; stock `zsh/curses` is built from its original sources and is not
replaced. No compatibility aliases are registered. A process should use only
one active curses owner and end and unload it before switching modules.

Applications such as [zcoder.zsh](https://github.com/ZaguanLabs/zcoder.zsh) own
layout, themes, command routing, model state and event-loop policy. The module
owns terminal and curses operations that are awkward or expensive to express
in shell code.

## First extension: terminal geometry

Curses window dimensions may lag behind a terminal resize until input or a screen
update is processed. Shell applications that need the current terminal size can
otherwise end up repeatedly spawning a utility such as `stty`.

`zdraw geometry array` reads the controlling terminal's dimensions directly.
It does not require curses initialization, trigger a refresh, change terminal
modes, or take ownership of input. Platforms without `TIOCGWINSZ` return status 2.
The API and a standalone example are in the [README](../README.md).

## Compiled feature discovery

The read-only `zdraw_features` array exposes optional compiled support using
the same parameter interface as `zdraw_attrs` and `zdraw_colors`. Its initial
vocabulary is `geometry`, `resize`, `mouse`, and `default_colors`, gated by the
same compile-time conditions as the corresponding implementations.

Zsh's existing `zmodload -F -e zdraw +p:zdraw_features` check discovers the
interface without calling an unknown subcommand on an older module. A missing
or disabled parameter means information is unavailable; an omitted documented
name in an available array means that support was not compiled in. A listed
feature is not a promise that the operation can succeed at runtime.

The query works headlessly, before initialization, during a session and after
`end`. It performs no terminal I/O, initialization or protocol negotiation.
Callers test individual names and ignore unfamiliar additions. Feature presence
provides the compatibility contract for this small interface; build identity,
ABI metadata and a broader error contract remain separate design work. Existing
command statuses are unchanged.

Terminal capabilities and negotiated state need distinct future interfaces.
They must represent unavailable information explicitly rather than converting an
unanswered query into a claim of unsupported hardware or protocol behavior.

## Runtime color information

`zdraw colorinfo association` reports color information separately from the
compiled feature array. It assigns an ordinary associative parameter so fields
can be added without changing positional output. Before initialization and after
cleanup only `initialized=0` is known; other fields are `unknown`.

During a session, recorded capability and initialization results distinguish
`has_colors` from successful `start_color` and successful `use_default_colors`.
Library counts remain distinct from module limits. Pair allocation and reporting
share the same bound, and the query exposes the additional limits of narrow
background and cell-readback paths. Allocations are counted without assigning
or recycling pairs. These are upper bounds, not a resource reservation.

The command reads cached state and does not touch terminal modes, input, screen
updates or protocol negotiation. It preserves existing color commands and legacy
count parameters. The [API](../README.md#runtime-color-information) describes
the fields and a standalone example. Opt-in direct RGB drawing is now
implemented; see the rendering phases below.

## Design constraints

Use Zsh's platform feature checks, parameter assignment, memory management and
module build rules. Keep OS-specific behavior behind compile-time feature checks
with defined failure behavior. Avoid hard-coded library paths, module suffixes,
compiler/linker flags and assumptions about the installed Zsh ABI.

Keep ncurses' retained screen and physical-screen diff. The existing
`zdraw refresh win1 win2 ...` uses `wnoutrefresh` followed by `doupdate` to
perform one screen update. Applications can cache visible rows and styled spans
without adding their layouts or a second screen model to the C module.

New terminal protocols must be opt-in, with explicit input ownership, bounded
reply handling, and cleanup. Preserve the existing `input` API. Never evaluate
shell command strings as a drawing or event protocol.

## Exploration roadmap

The [checklist](roadmap.md) records twelve candidate directions and their
individual milestones. The first implementation adds structured input records
and reusable styled rows; modern protocol negotiation and broader drawing
batches remain separate work.

Structured input shares the existing curses decoder and window timeout. Targets
are checked before reading. Because Zsh can own SIGWINCH, terminal size polling
provides resize records independently of curses key notifications. Polling does
not consume input or resize/refresh windows. Curses reads retain their existing
possible refresh behavior by default. Opt-in `event ... norefresh` uses a private
one-cell input pad on ncurses, preserving drawing-window state and deferring
presentation until an explicit refresh. The selected window's timeout is copied
onto the pad for each read; there is still only one curses input queue. The pad
is lazy, session-owned and released on end/unload. Other curses implementations
return unsupported until their input behavior can provide the same guarantee.
Mouse bookkeeping uses actual bit flags and resets activation on session cleanup.

This choice follows ncurses' [pad contract](https://invisible-island.net/ncurses/man/curs_pad.3x.html)
and its explicit exclusion of pads from automatic refresh in the
[input implementation](https://github.com/mirror/ncurses/blob/master/ncurses/base/lib_getch.c).
PTY barriers verify that dirty prepared rows and child windows stay hidden while
polling and reading queued keys, then appear on explicit refresh. Legacy input
still refreshes. Tests also cover per-window waits, failure before consumption,
mouse/resize decoding, narrow input, end/reinit and unload/reload.

Prepared rows share the span compiler and state-preserving row writer. They
store immutable decoded cells, widths and already allocated color pairs in a
session-scoped namespace, with explicit release and a 16 MiB accounted-storage
limit. Locale/option changes are rejected during reuse, and end/unload releases
all rows. This caches drawing data, not another screen or application layout.
The README and native manual define the detailed contracts. The event inspector
and prepared-row benchmark are the first standalone demonstrations.

## Candidate work

The [btop rendering review](btop-review.md) maps concrete implementation patterns
to these candidates, identifies existing correctness gaps, and proposes a patch
sequence without committing to new APIs.

`geometry`, compiled feature discovery, custom borders and runtime color
information, styled-span batching, opt-in truecolor and cell-aware clipping, structured input records and prepared styled rows
are implemented.
The initial drawing changes also correct wide-character buffers and guard
numeric color parsing and pair allocation. Custom borders preserve the original
form and expose eight glyphs without adding title or layout policy. The
`custom_borders` and `wide_borders` feature names distinguish ASCII support from
the optional wide curses path. A configuration patch checks optional curses drawing functions in
the disposable build tree and is included in patch exports.

The remaining areas require
independent use cases, standalone examples, measurements where relevant, and
compatibility tests before an API is chosen:

| Area | Questions to resolve |
| --- | --- |
| Cursor visibility and window operations | Define ownership and restoration; test repeated resize and overlay dismissal |
| Drawing helpers | Styled spans are implemented; measure application workloads before adding further helpers |
| Extended colors and capabilities | RGB values are implemented; wider pair IDs or additional encodings require a separate end-to-end audit |
| Structured input | Initial records are implemented; define modern protocol ownership, deadlines, bounded buffers and lossless paste handling |
| Unicode | Cell-aware measurement/clipping is implemented; full grapheme segmentation remains outside the current contract |
| Terminal protocols | Require a concrete benefit, opt-in negotiation, input ownership and terminal/multiplexer tests |

## Verification and upstream path

Build from publicly available Zsh sources in `.build/` and run PTY tests against
the shell from the same build. A supplied configured tree is an optional build
input, never an implicit dependency. Builds and tests must leave the original
source tree and installed modules untouched.

The geometry tests distinguish current terminal size from stale curses size,
check output and terminal modes, and cover failure paths. Feature discovery is
tested headlessly, across the module lifecycle, during pending screen changes,
and against builds with optional support removed and the preserved stock module.
Existing text, color, window and refresh operations are also exercised. Expand
verification across Zsh versions and build configurations, Linux and BSD/macOS,
and alternative curses libraries. A PTY does not establish rendering correctness
across real terminals or multiplexers.

Preserve the original sources and licence attribution. The integration patch
adds `zdraw` alongside stock curses. Upstream feature contributions should be
focused patches adapted to `zsh/curses`, including manual changes. Before
submission, adapt tests to Zsh's native harness and review/rebase the patch against the maintainers'
current source. The standalone tests and patch export support that work; they do
not imply upstream acceptance.

## Phased rendering work

Phase one adds `spans`: complete styles and bounded single-row drawing through
curses character arrays. It preserves cursor, attributes and background; wide
curses paths temporarily neutralize window/background state because array writes
can merge that state into supplied cells. Validation precedes color allocation
and drawing. Failed allocation can retain newly allocated pairs; a library write
error can partially draw. See the [API](../README.md#styled-span-batching) and
[benchmark](../benchmarks/README.md).

Phase two adds opt-in truecolor through ncurses' extended pair initialization.
RGB color values use integers while pair IDs stay within their existing short
bounds. This allows the existing attribute, background, span and readback paths
to share RGB pairs without changing their representations. Capability detection
checks the terminal description and library encoding; it does not probe the
terminal, negotiate replies, or allocate colors. Decimal indices remain bounded
as before. Reserved palette indices are reported and rejected for RGB requests,
not silently approximated. Off disables new RGB arguments and leaves existing
cells and styles valid until changed or the session ends.

The [API](../README.md#truecolor) documents terminal setup, color ranges and
fallback. PTY tests compile private terminfo entries and verify exact foreground
and background SGR bytes, mixed/default colors, pair IDs beyond 255, input and
refresh ownership, optional builds, allocation failure and session cleanup.
The [example](../examples/truecolor.zsh) keeps gradient generation in Zsh.

Phase three adds cell-aware measurement and clipping. `textinfo` works headlessly
and returns a byte-preserving prefix/remainder plus retained and total widths.
`spansclip` applies one budget to a sequence of complete style/text runs. Both
use the same decoder and system `wcwidth`; there is no new Unicode table or
segmentation dependency. A positive-width character and its following zero-width
characters form the unit. A base and its marks stay within one styled span.

The complete input is validated even after the prefix ends. Measurement does not
impose curses' combining-character capacity, while drawing validates every unit
against it and allocates pairs only for visible spans. The existing `spans`
overflow behavior and its state preservation remain intact. The
[contract](../README.md#cell-aware-clipping) states how this differs from grapheme
boundaries and terminal-specific emoji shaping. Padding, ellipses and layouts
remain in Zsh; a [headless example](../examples/clipping.zsh) shows the results.

Full grapheme segmentation, wider pair IDs and alternative RGB encodings remain
separate work. No commitment to maintaining a Unicode segmentation database is
introduced by cell-aware clipping.

Primary references: [ncurses color functions](https://invisible-island.net/ncurses/man/curs_color.3x.html)
[the RGB terminfo capability](https://invisible-island.net/ncurses/man/user_caps.5.html),
and [ncurses' direct-color entries](https://github.com/mirror/ncurses/blob/master/misc/terminfo.src).
The implementation follows the library's distinction between integer RGB values
and bounded pair identifiers, and checks the declared per-channel encoding.


## Text positions

`textpos` bridges source byte offsets and displayed columns using the shared
printable-text decoder and `textinfo` clipping units. It scans the whole input
before assigning output, retaining one matching range rather than a full map.
Byte counts exclude Zsh's internal Meta escaping. Either column of a wide cell
and all bytes of its following combining characters select the same range.
An exact end offset returns an empty range for insertion; offsets beyond it fail.

The query is independent of curses initialization and storage limits. It makes
no grapheme or emoji-shaping claim. Callers retain original text and own scrolling,
selection policy and conversion from screen coordinates. The standalone
`examples/hit-test.zsh` shows this composition with prepared headings, styled
spans and structured keyboard/mouse events, redrawing only after a relevant event.


## Wrapped source ranges

`textwrap` scans one printable logical line using the shared text decoder. A
positive-width character that would overflow the current row closes that row
before its own source bytes. Zero-width suffixes therefore remain attached even
when the preceding base exactly filled the row. No units, spaces or bytes are
discarded. Overwide units and controls fail instead of introducing implicit
replacement, word-breaking or multiline policy.

Each completed row contributes its original metafied substring, decoded source
byte endpoints, unwrapped column endpoints and width to a temporary list. Byte
counting skips internal Meta escapes. The single pass needs no per-character map
or repeated rescanning of suffixes. Source bytes are capped at 1 MiB and rows at
4096, bounding text and per-row metadata independently. Assignment happens only
after successful validation, so failures cannot publish partial rows. All storage
is per-call; end/unload has no new persistent state to release.

Headless tests compare rows to repeated `textinfo` clipping, rejoin the input and
check every boundary through `textpos`. Explicit cases cover exact-width combining
suffixes, wide units, empty text, ASCII fallback, locale changes, byte/row limits,
target validation and discarded partial results. A PTY composition test calls
the query while a frame is queued and verifies input/presentation remain unchanged.
The reflow example keeps a selection attached to an original byte while width
changes move its row boundaries. Layout and scrolling policy stay in Zsh.

## Retained-cell inspection

`cellinfo` reads the current cursor cell without moving it. This avoids changing
curses' internal moved/touched state just to inspect another location. The wide
path reads the complete complex character through `win_wch` and `getcchar`, then
converts the full string with `wcstombs`, whose conversion starts in the initial
state rather than changing the shell's shared multibyte decoder state. Failed
reads and conversions happen before parameter assignment. The narrow path
reports the packed byte representation explicitly.

Known attributes and original cached color spellings support readable assertions;
raw non-color attribute bits and pair IDs are diagnostics tied to the library
and session. Cache provenance is explicit, including unknown colors. This first
inspection milestone deliberately leaves continuation identity and stable whole-
screen serialization to the snapshot design. It already lets prepared-row tests
assert that combining marks survived drawing, which `querychar` cannot show.

Reference: ncurses' [complex-character API](https://invisible-island.net/ncurses/man/curs_getcchar.3x.html).


## Bounded window snapshots

`snapshot` and `cellinfo` share a reader that returns a cell record without shell
parameter assignment. A snapshot validates its target and dimensions, duplicates
the window, traverses only that copy, and assembles a flat association. It deletes
the copy before assigning the complete result. Copy/read/conversion/budget failures
leave caller data unchanged; no hidden window is registered in `zdraw_windows`.
Cell and key/value byte bounds limit captures without creating persistent objects.

The versioned layout records what each coordinate returns through the public
curses API. In particular, it retains repeated wide-character text at continuation
columns rather than trying to identify leading cells from adjacent equal text or
current-locale width guesses. This works for subwindows beginning inside a wide
cell. Explicit continuation metadata and portable restore/serialization remain
separate work. Snapshot comparisons can already catch lost combining marks,
changed styles, stale cells and unexpected cursor positions.

Reference: the public [window-copy API](https://invisible-island.net/ncurses/man/curs_window.3x.html).


## Styled rectangle fills

`fill` reuses the span compiler to validate one single-column tile, then repeats
that compiled cell in a temporary row and sends it through the existing row
writer for each rectangle row. Positive dimensions and complete in-window bounds
are checked first. This removes shell row loops and repeated style/text decoding
without adding retained surfaces, application layouts or a second renderer.

Space/background behavior, color pairs and cursor/style restoration come from
the same writer as spans and prepared rows. Existing wide characters intersected
by a boundary retain curses' repair semantics, which can affect cells beyond the
rectangle; snapshot tests compare against span writes rather than guessing a
new clipping rule. Library write errors can leave partial drawing and are not
transactional. The example keeps movement and selection policy in Zsh.

Reference: the [curses complex-cell array writer](https://invisible-island.net/ncurses/man/curs_add_wchstr.3x.html).

## Retained rectangle copying

`copy` stages the requested rectangle in a private `newpad` and uses opaque
`copywin` for both transfers. Staging is unconditional because differently
named parent/subwindows can alias storage. Coordinate and extent validation
precedes allocation; subtraction checks avoid overflowing coordinate sums.
The temporary rectangle is capped at 65,536 cells and is released after success
or either copy failure. It is never registered or refreshed.

The operation transports existing curses cells, without decoding strings,
merging destination background styles or allocating color pairs. It preserves
live cursors and drawing state. Invalid input and failed source staging cannot
modify the destination; a destination failure can leave partial writes.
Subwindow change-marker synchronization remains the caller's responsibility.

The contract deliberately requires applications to align wide-character edges
for portable results. `copywin` does not offer a portable repair guarantee for
split glyphs. This milestone provides opaque copying; transparent blanks and
attribute-only region updates remain separate experiments. Tests compare full
snapshots for all overlap directions, shared windows, literal spaces, styles,
combining marks and complete wide characters, with injected allocation/staging/
write failures and builds lacking either optional function.

## Retained rectangle restyling

`restyle` shares the complete span-style parser independently of array-writer
availability. It validates literal geometry and the whole style before allocating
a single shared color pair, then calls optional `wchgat` once per row. The pair
is passed separately from attribute bits, with a guard against truncation on
older ncurses ABIs. No cell buffer, text conversion or second screen model is
introduced. Current attributes/background remain unchanged; cursor restoration
is attempted on success and after an update failure.

Style replacement is absolute: absent attributes are cleared and absent color
means pair zero. This includes clearing the ACS marker and unsupported attribute
bits, so retained code points alone do not guarantee unchanged border appearance.
Wide edges follow curses' occupied-column semantics and should align to complete
characters. Partial updates and allocated pairs survive errors; no transaction or
style-history stack is implied. Application selection state and restoration
styles live in the Zsh example, outside the C module.

## Offscreen pads and frame composition

Public pads use the existing `ZCWin` registry with a pad flag and owned cell
count. Allocation checks literal positive dimensions, a per-dimension cap,
per-pad cells and aggregate public-pad cells before calling optional `newpad`.
Only successful creation registers a handle and consumes budget. Deletion
releases budget on success; failed pad deletion retains ownership for retry.
End/unload free pads with the other registered windows. Private input/copy pads
remain outside this public-pad accounting. There are no subpads in this milestone.

`viewport` validates pad/screen rectangles using subtraction before converting
their extents to inclusive curses coordinates. It touches only the source row
range and calls `pnoutrefresh`. `stage` validates its entire ordinary-window list,
touches each window and calls `wnoutrefresh` in order. Explicit touching makes
unchanged surfaces usable when recomposing overlaps. `present` only calls
`doupdate`. Nothing resets the virtual screen or remembers application viewport
mappings. Wide-cell overlap and clipping belong to the curses implementation.

Pads share drawing and inspection operations but are rejected as input targets,
ordinary refresh/stage targets and addwin parents. Input rejection occurs before
resize delivery or queue consumption. Position queries report no screen origin.
Terminal resize leaves pad dimensions fixed. Existing window refresh/input
behavior remains available, including its ability to present queued work;
applications requiring explicit presentation use no-refresh input where supported.

Tests inspect retained pad cells and, in a test-only variant, curses' virtual
screen to verify layering, multiple views and restaging unchanged content. PTY
barriers independently verify that staging is silent, rejected pad input leaves
queued characters untouched, and only explicit presentation reveals queued
content. Budget and failure variants cover allocation, deletion, viewport,
staging and final update paths. The Zsh example owns scrolling and overlay policy.

## Public pad resizing

`resizepad` reuses the public-pad dimension and cell caps. Its budget check credits
the existing allocation, allowing same-area replacement even at the session
limit. Only successful replacement changes the live cell count. The temporary
surface and native reallocation need additional memory outside that accounting.

A fresh `newpad` at the original dimensions receives the saved complex background
and all original cells via opaque `copywin`. Native `wresize` then changes the
extent, fills growth from the background and repairs native wide edges during
shrink. Copying the full original first avoids introducing a separate clipped-copy
edge policy. Using `newpad` guarantees a pad: some libraries' `dupwin` returns an
ordinary window for a pad source. The public `copy` limit does not apply to this
internal transfer, which is bounded by the larger pad cap.

Full current style, clamped cursor and scrolling mode are restored before releasing
the original and replacing its registered pointer. Preparation and original-release
failures keep the original handle, cells and accounting. Background getter/setter
and attribute getter/setter support are required for the capability; silently
dropping complex backgrounds or high pair IDs is not a fallback. No text decoding
or color allocation occurs, so retained RGB survives opt-out.

PTY tests compare ASCII overlap and growth to independently populated reference
pads and cover Unicode edges, large retained areas, current/background styles,
scrolling, quotas and failure isolation. Presentation barriers verify resize is
silent and that staged cells survive even when their original rows are truncated.
The viewport example grows or truncates its pad explicitly and populates new rows
from application data. Pad resize does not alter terminal geometry, input ownership
or viewport mappings.

## Independent window geometry

`movewin` moves a top-level ordinary window after strict coordinate and screen
bounds validation. `resizewin` optionally changes both extent and origin. Both
reject permanent windows, pads, subwindows and windows with children, leaving
shared-storage geometry for a separate design. No presentation is performed.

Resize bounds apply to the requested rectangle, permitting a simultaneous move
when recovering from a smaller terminal. Old and new areas are capped at 262,144
cells and requested dimensions at 32,767. A private duplicate receives `wresize`,
`mvwin`, full current-style restoration, cursor clamping, scrolling mode and
timeout. Only after all steps succeed and the original can be deleted does the
registered pointer change. This avoids changing live geometry/cells on recoverable
allocation or preparation errors. No named temporary surface is exposed.

Explicit `wattr_get`/`wattr_set` is necessary because a duplicate can lose a
window's separate extended color-pair field while retaining packed attribute
bits. Background cell storage is preserved by duplication; curses supplies new
cells from that background during expansion and performs native wide-edge repair
during shrink. Previously queued screen cells are independent of window pointers
and are not rewritten or erased by a geometry change. Applications recompose
backgrounds and affected surfaces before presenting.

## Final application integration batch

Bracketed paste uses a temporary, noncolliding curses key definition for the
start delimiter. Native escape timing applies before that delimiter is decoded.
Payload reads use `wgetch` with keypad disabled on the same input window/queue,
preserving arbitrary bytes independently of the locale. A small prefix matcher
is paired with explicit raw input ownership for the entire enabled period, so
the line discipline cannot intercept signal or flow-control bytes before parsing.
Disabling paste restores pre-enable modes; foreground handoff restores shell modes.
The matcher
holds at most five end-delimiter bytes. Work and output per call are bounded;
reads after the first byte poll instead of waiting to fill a chunk. False prefixes
are emitted and a complete terminator ends the paste without consuming subsequent
keys. Cleanup owns the mode request, key definition and parser state. No raw fd
reader competes with curses.

Suspension retains every drawing resource while saving program modes and releasing
the terminal. Active paste prevents handoff. The dispatcher blocks operations that
could accidentally re-enter curses while suspended. Resume restores modes, updates
geometry where available, repaints the retained virtual screen, and re-enables
configured protocols. Explicit state also permits end/unload while suspended.
Already-ended native screens are handled when suspending a newly reinitialized
session that has not presented yet. A small `always` wrapper owns foreground-command
execution and status propagation; application job-control policy stays outside C.

Per-call event polling temporarily changes only the initial timeout. Native escape
decoding still has its own delay; an explicit setter saves/restores that policy.
Input introspection reports queue readiness as unknown. The example drains bounded
event batches and waits on stdin plus a worker pipe with a short `zselect` tick,
accounting for internal queued input and geometry changes. It reads only the worker
descriptor through `sysread` and removes it at EOF.

The SGR parser is a companion Zsh state machine with caller-owned state. Pending
text, CSI bytes, input chunks and emitted records are bounded. Control-string
payloads are discarded without storage. Text runs are accumulated in blocks and
validated through the existing headless decoder before publication. A call builds
private state/output copies, so a malformed-text or limit failure publishes neither.
The output is complete styles plus text/control records; colors are allocated only
by later drawing operations. The example owns tabs, carriage returns, clipping and
bounded history, keeping application layouts out of the C module.

PTY barriers exercise binary/large/fragmented paste, following-key preservation,
deferred presentation, original terminal modes during handoff, geometry, interrupted
foreground commands, retained drawing, cleanup, worker readiness and optional/error
builds. Headless decoder tests cover every split of a styled stream, UTF-8 splits,
control-string filtering, malformed SGR and resource bounds. The combined example
is exercised in UTF-8/C locales and small terminals through worker EOF and handoff.
