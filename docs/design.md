# Direction and first milestones

The primary consumer is `~/dev/ai/zaguan/labs/zcoder.zsh/`. The secondary objective
is a series of generally useful changes that can be reviewed independently by
Zsh maintainers. The application owns interaction and layout. The module exposes
terminal and curses operations that are awkward or expensive to implement in Zsh.

## What already exists

Inspection of zcoder on 2026-09-07 found the following:

| Capability | Existing implementation |
| --- | --- |
| Dirty-window scheduling and one refresh per frame | `lib/ui.zsh`: `_ui_draw_window`, `ui_flush` |
| Cached transcript layout and folding | `lib/ui.zsh`, `lib/transcript.zsh` |
| Command palette and context/model inspectors | `lib/commands.zsh`, `lib/overlays.zsh` |
| Activity states and restrained animation | `lib/ui.zsh`: `ui_set_status`, `ui_status_update` |
| Synchronized-output negotiation and balanced frame delimiters | `lib/terminal.zsh` |
| Bracketed paste and enhanced newline decoding | `lib/terminal.zsh`, `lib/input.zsh` |
| Cell-width clipping, padding, and wrapping | `lib/util.zsh`, `lib/input.zsh` |

The local Zsh manual documents that `zcurses refresh win1 win2 ...` makes one
screen update. The supplied `curses.c` implements this using `wnoutrefresh` and
`doupdate`. We already have a useful frame boundary.

There are still costs above that boundary. `_ui_paint_chat` clears and repaints
the visible chat window when invalidated, even though its transcript layout is
cached. Ncurses can suppress unchanged terminal output, but the Zsh calls, text
clipping and attribute parsing still run. Measure those costs separately from
bytes sent to the terminal.

At baseline, `ui_poll_resize` ran `stty size` on a 0.25-second polling interval
because curses and shell geometry can be stale. This is the first concrete
module improvement: a read-only native geometry query.

## Ownership

```text
model / network / tools -> application events -> UI state and layout
                                               |
                                  changed rows and styled spans
                                               |
                                 zcurses windows and operations
                                               |
                              ncurses virtual screen -> terminal
```

Keep tool cards, folding, fuzzy matching, context visualization, responsive
sidebars, themes and command routing in the application or reusable Zsh functions.
They can evolve without adding application-specific concepts to a C module.

Use ncurses' retained screen and physical-screen diff. Start with cached visible
rows and spans in the application if profiling warrants them. A second full
terminal cell grid in Zsh would add allocations and Unicode bookkeeping that
need a demonstrated benefit.

## Priorities

| Order | Work | Benefit and completion criterion |
| --- | --- | --- |
| 1 | Matching source baseline, isolated build, PTY tests, native geometry | Implemented locally; fresh dimensions without spawning `stty`, including while curses still holds the old size |
| 2 | Cursor visibility and ownership; investigate window move/resize and partial drawing helpers | Remove terminal escape workarounds and unnecessary window reconstruction; test overlay dismissal and repeated shrink/grow cycles |
| 3 | Profile streaming; reduce Zsh calls with changed-row rendering and, if justified, a structured drawing batch | Same final screen with fewer shell-to-module calls; compare CPU time, frame latency and terminal bytes independently |
| 4 | Explicit capability reporting and stronger color handling | Distinguish compiled library features, terminal capabilities, and negotiated protocol state; exercise monochrome, indexed color and pair exhaustion |
| 5 | An opt-in structured event API | Paste payloads, modifiers, focus, resize and bounded protocol replies, with legacy `input` behavior preserved |
| 6 | Selective terminal protocols | Add only with a clear owner, negotiation, cleanup and terminal/multiplexer tests |

Apart from `geometry`, these are candidate work areas, not committed API names.
Each needs a concrete zcoder use case, a minimal example independent of zcoder,
and a compatibility test before it becomes a module extension.

For drawing batches, pass structured argument arrays: never evaluate a string of
shell commands. Define validation, clipping, cursor advancement and partial-error
behavior before implementing the API. Keep rendering and presentation separate;
the existing multi-window `refresh` remains the default presentation operation.

For colors, the current source stores color and pair identifiers in `short` and
uses `init_pair`. Audit overflow and exhaustion before exposing richer palettes.
Do not recycle pairs still referenced by retained windows. Truecolor requires
support throughout the curses/terminfo path; inserting SGR escapes into window
text does not provide that support.

For input, ncurses already consumes and decodes part of the stream. A new decoder
must have explicit ownership of that stream, deadlines for incomplete sequences,
bounded buffers, and lossless treatment of pasted data. `timeout` is not an
explicit escape-sequence disambiguation setting. Measure bare-Escape and modified
key latency rather than inheriting timing claims from the original discussion.

For Unicode, the existing Zsh width helpers are a useful starting point. Combining
marks, wide characters, emoji sequences and ambiguous-width policy need explicit
tests across the library and terminal. Do not advertise complete grapheme support
on the strength of `wcwidth`-style accounting alone.

Synchronized output already has an application implementation. Keep it there
until there is a concrete benefit to moving it. OSC 8 hyperlinks are more involved:
ncurses does not model hyperlink identity in its cells, so an isolated escape
write cannot establish correct retained redraw behavior. Clipboard writes should
be explicit user actions; they are not a rendering feature.

## First zcoder integration

The local zcoder `ui_poll_resize` now uses native geometry while retaining its
event-loop scheduling, dimension validation, and resize/layout behavior.
`UI_NATIVE_GEOMETRY` tracks the backend for the current UI session:

- `-1`: unprobed; the next due poll tries the extension.
- `0`: the first probe failed; use `stty` for the remainder of this UI session.
- `1`: native query succeeded; use it on subsequent polls.

`ui_init` resets the selection. A later native-query failure skips that poll,
preserves the current layout, and retries natively at the next poll. The first
probe cannot distinguish an old module's unknown-command error from a temporary
query failure, so either selects the fallback for the session. A future capability
API could make that distinction explicit.

The zcoder tests cover polling gates, resize signals, invalid dimensions and
native-query recovery with mocks. A real UI fixture performs grow/shrink/grow and
UI reentry with the stock module and, when `ZCODER_TEST_CURSES_PATH` is provided,
the fork. It counts subprocess calls and native probes. The fork path must invoke
no `stty` during polling; the stock path must probe the extension only once per
session. Existing required checks remain `make test` and `make compile`.

## Verification and upstream path

The current automated checks load the built module into the installed Zsh in a
real PTY. They distinguish fresh terminal geometry from stale curses geometry,
check no output or mode changes during the query, and cover failure paths.
They also smoke-test existing text, color, window and refresh operations.

Before wider distribution, add the matching Zsh versions and build configurations,
Linux plus BSD/macOS, supported alternative curses libraries, and the unsupported
geometry compile branch. Terminal protocol work additionally needs real terminals
and tmux/SSH cases; a PTY alone cannot verify terminal rendering semantics.

Keep original sources and licence attribution. Export one patch per independent
feature, including manual changes and upstream-harness tests. Rebase against the
maintainers' current source before proposing inclusion. The current local
geometry patch is a starting point for that review, not an upstream-ready release.
