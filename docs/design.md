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

Only `geometry` is implemented. These areas require independent use cases,
standalone examples, measurements where relevant, and compatibility tests before
an API is chosen:

| Area | Questions to resolve |
| --- | --- |
| Cursor visibility and window operations | Define ownership and restoration; test repeated resize and overlay dismissal |
| Drawing helpers | Measure shell-call overhead separately from terminal output; specify clipping and partial-error behavior |
| Capabilities and colors | Separate compiled features from terminal capabilities; handle color/pair limits and exhaustion |
| Structured input | Define coexistence with curses decoding, deadlines, bounded buffers and lossless paste handling |
| Unicode | Test combining marks, wide characters, emoji sequences and ambiguous-width policies |
| Terminal protocols | Require a concrete benefit, opt-in negotiation, input ownership and terminal/multiplexer tests |

## Verification and upstream path

Build from publicly available Zsh sources in `.build/` and run PTY tests against
the shell from the same build. A supplied configured tree is an optional build
input, never an implicit dependency. Builds and tests must leave the original
source tree and installed modules untouched.

The geometry tests distinguish current terminal size from stale curses size,
check output and terminal modes, and cover failure paths. Existing text, color,
window and refresh operations are also exercised. Expand verification across
Zsh versions and build configurations, Linux and BSD/macOS, alternative curses
libraries, and the unsupported-geometry compile branch. A PTY does not establish
rendering correctness across real terminals or multiplexers.

Preserve the original sources and licence attribution. Export one focused patch
per independent feature, including manual changes. Before submission, adapt tests
to Zsh's native harness and review/rebase the patch against the maintainers'
current source. The standalone tests and patch export support that work; they do
not imply upstream acceptance.
