# Exploration checklist

This roadmap records the ideas discussed after the rename to `zdraw`. It is a
set of candidates, not a promise to implement every item. Check an item only
when its implementation, documentation and relevant verification are complete.
A completed first milestone does not complete the broader direction.

The [incremental implementation plan](implementation-plan.md) orders the remaining
work by usefulness and dependencies, and records companion-layer work that already
covers some older entries below. Use that plan for the next milestone checklist.

The native exploration batch stopped after application integration (2026-09-10):
streaming paste, suspend/resume, asynchronous input integration and colored command
output. Remaining unchecked items are deferred candidates, not follow-on work for
this batch. See the [integration contracts and combined example](application-integration.md).

Subsequent visual-toolkit work has its own
[implementation checklist and guide](ui-toolkit.md), informed by the
[beautiful TUI research](beautiful-tuis-research.md). Its first milestone adds
optional Zsh themes, utilities, panels, labels, lists and a gallery above the
existing native primitives. Pure rectangle layout helpers and a responsive
[list/detail recipe](recipes/list-detail.md) extend this companion layer.
Customizable [tables](ui-table.md) and a
[table/inspector recipe](recipes/table-inspector.md) build on those helpers.
[Tabs, badges, meters and help rows](ui-presentation.md) complete the initial
presentation set, demonstrated in a [task monitor](recipes/task-monitor.md).

Implemented first milestones (2026-09-09): [structured input](../README.md#structured-input)
and [prepared styled rows](../README.md#prepared-styled-rows), followed by opt-in
`event ... norefresh` on ncurses and headless text geometry. The 58-test suite passes against the matching
Zsh 5.9.2 shell, including optional builds. The new paths also pass ASan/UBSan checks
with leak detection disabled. The native manual
builds and the exported patch applies in a dry run. See the
[event inspector](../examples/events.zsh) and
[reuse measurements](../benchmarks/README.md#prepared-row-reuse).

The aim is to make sophisticated terminal programs natural to write in Zsh:
responsive input, reusable drawing operations, predictable presentation and
useful diagnostics. Keep application layout, themes and event-loop policy in
Zsh. Preserve inherited operations, portable fallbacks and original sources.
New protocols require explicit opt-in, a single input owner and cleanup.

## 1. Structured events — first priority

One association describing a decoded event should replace application-specific
interpretations of positional output variables. Modern protocols can build on
that contract without putting a second reader beside curses.

- [x] First milestone: character, function-key and resize records using the
  existing curses decoder plus terminal geometry checks; opt-in mouse records
  and the inherited `input` interface. Mouse activation bookkeeping was repaired
  so reporting disables and resets between sessions.
- [x] Validate output targets before consuming input; document timeouts,
  encoding, unavailable modifier information and input ownership.
- [x] Provide a standalone event inspector and PTY tests.
- [x] Add bounded streaming paste through the curses input owner, with explicit
  opt-in, binary chunks, fragmented end delimiters and end/unload cleanup.
  Start delimiters use the documented native escape-decoder timing window.
- [ ] Add focus events and negotiated keyboard press/repeat/release reporting.
- [x] Add per-call polling, explicit escape delay and input-state queries for
  `zselect` composition. Report internal queue readiness as unknown, document
  native wait limits, and demonstrate bounded event batches with a worker pipe.
- [ ] Test protocols across terminals, multiplexers and interrupted sessions.

References: [kitty keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/),
[xterm paste, focus and mouse protocols](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html).

## 2. Frame presentation

Applications should be able to receive events, update state, draw and present
without an input call accidentally revealing an unfinished frame.

- [x] Add opt-in `event ... norefresh` with an explicit presentation guarantee
  on ncurses, feature discovery, timeout inheritance and end/unload cleanup.
  PTY tests verify hidden dirty rows/windows and explicit presentation; default
  input retains its refresh behavior.
- [ ] Validate no-refresh input on other curses implementations before enabling
  the feature there.
- [ ] Explore synchronized-output markers around the final curses update.
- [ ] Define opt-in detection, flushing, timeout and cleanup behavior.
- [ ] Verify partial-frame behavior with real terminals and slow connections.

Keep curses' screen diff. Synchronized output supplements it; it does not
promise atomic presentation on every terminal.
References: [curses input](https://invisible-island.net/ncurses/man/curs_get_wch.3x.html),
[synchronized output](https://github.com/contour-terminal/vt-extensions/blob/master/synchronized-output.md).

## 3. Viewports and overlapping surfaces

Offscreen surfaces and rectangular views support scrolling documents. Movable,
stacked windows support temporary overlays without exposing layout policy in C.

- [x] Expose bounded offscreen pads and viewport staging, with explicit ordinary
  window staging and final presentation. Verify budgets, lifecycle, shared drawing
  operations, composition order and input ownership in PTYs.
- [x] Move and resize independent ordinary windows, including combined resize
  and repositioning, retained state, cursor clamping, failure isolation and
  documented native wide-edge behavior. Provide a [floating-window example](../examples/windows.zsh).
- [x] Resize public pads with retained overlap, background/style preservation,
  cursor clamping, credited live budgets, failure isolation and explicit
  presentation. Extend the viewport example with growth and truncation.
- [ ] Define geometry changes for shared window trees.
- [ ] Explore optional panel-library support for stacking, hiding and showing.
- [ ] Specify how panel updates and existing refresh operations coexist.
- [x] Provide a [panning document and overlay example](../examples/viewports.zsh)
  with terminal resizing and overlap tests. Independent window movement and
  resizing are now covered by the floating-window example above.

A pad is not automatic virtualization: applications still own large datasets
and choose how much content to render.
References: [pads](https://invisible-island.net/ncurses/man/curs_pad.3x.html),
[panels](https://invisible-island.net/ncurses/man/panel.3x.html).

## 4. Reusable drawing data — first priority

Prepare immutable styled rows once and reuse their decoded cells and styles.
This can avoid repeated text decoding, style parsing and shell argument traffic
for headers, labels and repeated content. It adds no second screen model.

- [x] First milestone: prepare, draw, inspect and release named styled rows.
- [x] Share span validation and window-state-preserving rendering with `spans`.
- [x] Define clipping, locale binding, color allocation, resource accounting,
  immutability, session cleanup and module unload behavior.
- [x] Verify cell equivalence, invalid input, optional builds and lifecycle,
  including prepared RGB reuse after opt-out and color-pair IDs above 255.
- [x] Benchmark repeated rows against ordinary spans; report measured limits.
- [ ] Consider multi-operation batches only after representative measurements.

Reference: [existing span benchmark](../benchmarks/README.md). Its speedup does
not establish a benefit for all workloads; measure representative reuse.

## 5. Text geometry for interaction

Drawing and hit-testing should use the same geometry. This supports editors,
selection, highlighting and scrolling without implementing editor policy in C.

- [x] Map displayed columns to original source byte ranges and vice versa
  with headless `textpos` queries, end boundaries and complete clipping units.
- [x] Define wide-cell hit-testing: either occupied column selects the complete
  clipping unit and its source bytes.
- [x] Return source ranges for column-wrapped printable logical lines, with
  complete clipping units, byte/row limits and atomic result assignment.
  Verify reconstruction and hit-testing boundaries; provide a source-anchored
  [reflow example](../examples/wrapping.zsh).
- [ ] Consider word-breaking and multiline source-range policies separately.
- [ ] Explore optional grapheme-aware cursor/clipping boundaries.
- [x] Keep clipping units, terminal width policy and curses storage limits
  distinct; document that `textpos` does not provide grapheme segmentation.
- [x] Test combining marks, multibyte byte offsets, wide-cell selection, locale
  changes, ASCII fallback and byte/column round trips; provide a keyboard/mouse
  [hit-testing example](../examples/hit-test.zsh).
- [ ] Test emoji shaping and width discrepancies across actual terminals.

References: [Unicode segmentation](https://www.unicode.org/reports/tr29/),
[Unicode width](https://www.unicode.org/reports/tr11/).

## 6. Colored command output as spans

A controlled streaming decoder could convert colored command output into text
and style runs for curses windows.

- [x] Provide a deliberately limited SGR-only decoder in a companion Zsh library.
- [x] Handle escape sequences split across input chunks with bounded storage.
- [x] Specify malformed/unsupported sequence handling; never pass arbitrary
  terminal commands through to the terminal or evaluate input as shell code.
- [x] Demonstrate colored diagnostic worker output in a pad, through a pipe,
  with explicit EOF handling and independently owned parser state.

Full interactive subprocess emulation is a separate, much larger project.

## 7. Capabilities with evidence

Extend compiled-feature/runtime-state separation with the origin of each claim.

- [ ] Define capability status, evidence source and enabled-state fields.
- [ ] Distinguish build checks, terminfo, replies and application overrides.
- [ ] Preserve `unknown` for unanswered or ambiguous queries.
- [ ] Route opt-in queries through the input owner with bounded reply handling.
- [ ] Test fallbacks through multiplexers and remote connections.

## 8. Suspend and resume

Hand the terminal to an editor, pager or foreground command, then return to the
interface. This should preserve the shell's ability to compose existing tools.

- [x] Define release/restoration of terminal modes and configured paste/mouse reporting.
- [x] Recheck geometry and repaint the retained virtual frame on resumption.
- [x] Provide a Zsh wrapper using `always`, preserving foreground command status.
- [x] Test handoff, interrupted/failed foreground commands, retained resources,
  terminal resize, repeated calls, end/unload and injected library failures.
- [ ] Expand real-shell job-control coverage; applications currently suspend
  explicitly and own their signal/job-control traps.

## 9. Inspectable screens and replay

Turn a failing interaction into a fixture: start at a known size, paste data,
resize, send keys, then compare logical cells and styles.

- [x] Add `cellinfo` for complete stored complex-character text, structured
  attributes and cached color evidence, without moving or refreshing a window.
  Preserve the inherited first-character `querychar` interface.
- [x] Test stored combining marks, wide occupied columns, locale failures,
  optional readers, high RGB pair IDs and query state preservation.
- [x] Capture whole retained windows into versioned `zdraw-snapshot-1`
  associations, with owned strings, explicit readback semantics, cell/byte bounds,
  private-copy cleanup and atomic assignment. Provide a readable diff example.
- [ ] Add explicit wide-character continuation metadata and a portable screen
  serialization format beyond coordinate-by-coordinate readback.
- [ ] Represent styles independently of session-specific color-pair numbers.
- [ ] Extend the existing PTY harness with scripted events and readable diffs.
- [ ] Define explicitly enabled recording, replay and timing behavior.
- [ ] Add useful rendering/resource diagnostics without promising unmeasurable
  terminal-emulator paint times.

Start with curses inside a PTY; a separate headless renderer risks behavioral
drift and needs its own justification.

## 10. Region drawing primitives

- [x] Fill styled rectangles and horizontal/vertical runs with single-column
  tiles, shared span validation and cursor/style preservation.
- [x] Copy bounded opaque regions with staged overlap handling, strict bounds,
  optional-function discovery and explicit native wide-edge limitations.
  Verify aliased subwindows, full cell/style preservation and failure paths;
  provide a [retained-row scrolling example](../examples/copy.zsh).
- [x] Replace region styles while retaining character data, for selection/focus.
  Share complete-style parsing, preserve current drawing state, define native
  wide/ACS behavior, and test optional builds, RGB and update failures. Provide
  a [moving-highlight example](../examples/restyle.zsh).
- [x] Define fill bounds and existing-wide-character overlap behavior through
  the shared array writer; verify equivalence to ordinary span writes.
- [ ] Define transparent-cell semantics for future region copying.
- [x] Measure fill against ordinary/prepared row loops and verify surrounding
  cells with snapshots. Record [workload-specific results](../benchmarks/README.md#rectangle-fills)
  and provide a keyboard-driven region example.

These operations understand cells and rectangles, not application layouts.

## 11. Graphics experiments

- [x] Prototype points/lines encoded as Braille or block characters in a
  companion Zsh library; move only measured bottlenecks into C.
- [x] Demonstrate ASCII/Braille alternatives for the same waveform or plot.
  Delivered by the [character canvas](character-canvas.md), with a waveform
  recipe and [recorded redraw/memory measurements](../benchmarks/README.md#character-canvas).
- [ ] Explore an optional image-upload and placement interface.
- [ ] Investigate Unicode image placeholders against curses character capacity,
  widths, clipping, scrolling, multiplexers and resource cleanup.

Reference: [kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/).
Image placements are an experiment, not a promise that arbitrary raw graphics
can coexist with curses' retained-screen state.

## 12. Interaction within the shell session

A bounded interactive region below the prompt could finish by leaving a useful
result in scrollback. Short-lived interactions could be as useful as full-screen
programs, but this is an architectural experiment.

- [ ] Prototype explicit handoff between ZLE and a bounded interaction.
- [ ] Define screen/scrollback ownership before exploring simultaneous display.
- [ ] Compose asynchronous examples with `zselect` and `zle -F` where appropriate.
- [ ] Test prompt redisplay, terminal resizing and descriptor cleanup.

Use the ZLE and zselect documentation shipped with the selected Zsh release.
Do not add another event-loop framework without a demonstrated gap.

## Suggested order and experimental evidence

1. Structured events: greatest improvement to application interaction.
2. Snapshots/replay: strongest support for reliable experimentation.
3. Prepared drawing: a focused performance experiment.
4. Viewports/regions: broadly useful primitives with familiar building blocks.
5. Inline interaction: a distinctive longer-term direction.

Initial demonstrations: an event inspector, a prepared-row benchmark, and later
one movable/scrollable surface. Choose broader APIs from those experiments,
standalone use cases and measurements rather than checking off every candidate.
