# Scope and upstream direction

This project develops portable, general-purpose terminal and curses primitives
for Zsh. Each extension should solve a shell-level problem, preserve existing
`zcurses` behavior, and be reviewable as an independent patch for the official
Zsh distribution. No application repository, developer workstation, or specific
distribution is a project dependency.

Applications such as [zcoder.zsh](https://github.com/ZaguanLabs/zcoder.zsh) own
layout, themes, command routing, model state and event-loop policy. The module
owns terminal and curses operations that are awkward or expensive to express
in shell code.

## First extension: terminal geometry

Curses window dimensions may lag behind a terminal resize until input or a screen
update is processed. Shell applications that need the current terminal size can
otherwise end up repeatedly spawning a utility such as `stty`.

`zcurses geometry array` reads the controlling terminal's dimensions directly.
It does not require curses initialization, trigger a refresh, change terminal
modes, or take ownership of input. Platforms without `TIOCGWINSZ` return status 2.
The API and a standalone example are in the [README](../README.md).

## Compiled feature discovery

The read-only `zcurses_features` array exposes optional compiled support using
the same parameter interface as `zcurses_attrs` and `zcurses_colors`. Its initial
vocabulary is `geometry`, `resize`, `mouse`, and `default_colors`, gated by the
same compile-time conditions as the corresponding implementations.

Zsh's existing `zmodload -F -e zsh/curses +p:zcurses_features` check discovers the
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

`zcurses colorinfo association` reports color information separately from the
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
`zcurses refresh win1 win2 ...` uses `wnoutrefresh` followed by `doupdate` to
perform one screen update. Applications can cache visible rows and styled spans
without adding their layouts or a second screen model to the C module.

New terminal protocols must be opt-in, with explicit input ownership, bounded
reply handling, and cleanup. Preserve the existing `input` API. Never evaluate
shell command strings as a drawing or event protocol.

## Candidate work

The [btop rendering review](btop-review.md) maps concrete implementation patterns
to these candidates, identifies existing correctness gaps, and proposes a patch
sequence without committing to new APIs.

`geometry`, compiled feature discovery, custom borders and runtime color
information, styled-span batching, opt-in truecolor and cell-aware clipping
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
| Structured input | Define coexistence with curses decoding, deadlines, bounded buffers and lossless paste handling |
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

Preserve the original sources and licence attribution. Export one focused patch
per independent feature, including manual changes. Before submission, adapt tests
to Zsh's native harness and review/rebase the patch against the maintainers'
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
