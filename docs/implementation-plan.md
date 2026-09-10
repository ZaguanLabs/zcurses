# Incremental implementation plan

Recorded 2026-09-10, after completion of the visual toolkit. This is the ordered
follow-up plan for the [native exploration roadmap](roadmap.md) and the graphics
ideas in the [TUI research](beautiful-tuis-research.md). The order reflects
expected developer value, dependencies and implementation uncertainty; it is not
a delivery-date estimate or an instruction to start every experiment at once.

Use this file to track the next implementation milestones. The original roadmap
remains the inventory of ideas and historical native work. The completed
[toolkit checklist](ui-toolkit.md#implementation-checklist) remains its own record.

## Completed foundation

- [x] Themes, utility styles, layout, panels, lists, tables, tabs, badges, meters
  and help rows, with interactive application recipes.
- [x] Editable single-line fields and forms: selection, bounded streaming paste,
  validation, focus navigation and resize behavior.
- [x] Semantic documents: block styling, word wrapping, multiline source ranges,
  scrolling and named anchors preserved through reflow.
- [x] Portable readback fixtures with normalized styles, text/HTML diffs,
  theme/density baselines and scripted PTY interactions.
- [x] Native structured events, prepared rows, text geometry, pads, independent
  window geometry, region operations and explicit presentation primitives.
- [x] Streaming paste, explicit suspend/resume, asynchronous input integration and
  the companion SGR decoder for colored command output.

The recorded baseline is 75 passing tests against the matching Zsh 5.9.2 build.
It is a starting point, not a substitute for running checks on future changes.

Three older roadmap entries already have companion-layer solutions: styles
independent of color-pair IDs, scripted visual comparisons, and document
word-breaking/multiline ranges. Extend those implementations when a demonstrated
need arises. Do not recreate them in C merely to close an older checkbox.
Readback fixtures still do not provide wide-cell continuation metadata or a
screen-restoration/replay format.

## Order at a glance

| Order | Milestone | Useful result | Main layer | Dependency |
| --- | --- | --- | --- | --- |
| 1 | Compact charts | Trends and comparisons in dashboards | Zsh | Existing toolkit |
| 2 | Character canvas | Points, lines and small diagrams with ASCII fallback | Zsh | 1's data/style conventions |
| 3 | Capability evidence and portability | Applications choose enhancements from explicit evidence | Native + test tooling | Existing feature/input APIs |
| 4 | Focus and richer keyboard events | Better shortcuts and interaction state | Native | 3 |
| 5 | Frame presentation | Fewer visibly incomplete updates where supported | Native | 3 |
| 6 | Overlays and region composition | Reliable stacked, movable surfaces | Zsh, targeted native work | Existing windows; 5 integration if enabled |
| 7 | Diagnostics and measured optimization | Explain costs and improve proven bottlenecks | Tooling, targeted native work | Representative examples from 1–6 |
| 8 | Unicode interaction accuracy | Better documented and tested editing boundaries | Native + Zsh | Existing text/input APIs; 3's test matrix |
| 9 | Interaction recording and replay | Reproduce failures from bounded recordings | Tooling + native metadata | 3, 4 and 8 contracts |
| 10 | Optional motion | Useful activity and transition feedback | Zsh | 1, 5 and 7 |
| 11 | Inline shell interaction | A bounded UI below the prompt | Zsh + lifecycle investigation | 3's job-control coverage |
| 12 | Image previews | Optional previews with explicit fallbacks | Adapter + native experiment | 3, 5, 6 and 7 |
| 13 | Scaled text | Larger headings on suitable terminals | Native experiment | 3, 5, 8 and placement findings from 12 |

This is a default sequence, not a dependency chain through every row. For example,
frame presentation does not depend on completing the richer keyboard protocol.
Each milestone should leave a usable, documented result and a natural stopping
point. The first two deliver visible improvements without protocol negotiation;
the next milestones strengthen interaction and presentation for many applications.

## 1. Compact charts

Start with a small chart vocabulary that fits the existing styling model. This
adds more value initially than collecting many graph types. Reuse existing meters
for single-value progress rather than building a duplicate meter component.

- [x] Define bounded numeric-series input, literal numeric validation, missing
  samples, fixed versus automatic scale, constant ranges and negative values.
- [x] Implement independently loadable sparklines and compact bar charts, with
  shared theme roles and per-instance color/marker overrides.
- [x] Provide ASCII and Unicode renderings of the same data, with deliberate
  empty, one-sample, narrow-viewport and out-of-range behavior.
- [x] Add a task-monitor recipe view showing bounded history, current values,
  units and scale labels; keep sampling and history ownership in the application.
- [x] Verify geometry and scaling headlessly, add retained-cell/visual fixtures,
  and exercise resize, monochrome and fallback modes in the recipe.

**Completion:** the same bounded series can be displayed and restyled in a small
or large rectangle without changing application data or enabling a protocol.

**Completed 2026-09-10 — implementation commit `cb7a0f7`.**
The [compact-chart guide](compact-charts.md) documents the bounded signed-integer
series, zero-inclusive automatic scales, fixed-scale clipping, missing samples,
customizable ASCII/Unicode markers and projection helper. The task monitor's
History tab owns a maximum of 96 samples and shows per-task gains with units.

Verification: all 78 tests passed using `ZSH_BUILD_ROOT` set to the selected
public Zsh 5.9.2 source tree and its matching built shell. Coverage includes an
ASCII-only module variant, monochrome, new dark/light chart fixtures, PTY resize
and reset, and clipping at a zero endpoint or one-column viewport. The final run
is recorded locally in `.build/charts-final-make-test.log`; logs under `.build/`
are not required to reproduce the tests. Changed Zsh files passed parse checks.

## 2. Character canvas

Build on the chart conventions to support small plots and diagrams. Keep the
initial rasterization algorithms in the companion library.

- [x] Define a bounded logical canvas, coordinate transform, clipping rules,
  point collisions and mapping from logical pixels to terminal cells.
- [x] Implement points, line segments and rectangles with Braille/block markers
  and an explicit ASCII alternative. Keep marker selection separate from geometry.
- [x] Define clear/replace behavior and composable output using existing spans or
  prepared rows, preserving window cursor/style and application-owned refreshes.
- [x] Demonstrate one waveform or scatter plot with equivalent data and scales
  in ASCII and Braille; include labels outside the plot area.
- [x] Verify clipped edges, degenerate shapes, overlapping points, resize and
  unsupported characters; measure representative redraw cost and memory use.

**Completion:** a reusable canvas renders the example correctly in both modes.
Native acceleration is not required to finish this milestone; retain measurements
for milestone 7.

**Completed 2026-09-10 — implementation commit `7c66c90`.**
The [character-canvas guide](character-canvas.md) documents retained source
coordinates, clipped points/lines/rectangles, set/erase operations and a shared
2×4 logical-pixel grid per terminal cell. ASCII, block and Braille profiles reuse
the same raster; exported rows also work with native prepared drawing. The
waveform recipe demonstrates cached geometry, marker/theme changes and resize.

Verification: all 82 tests passed using the selected public Zsh 5.9.2 source tree
and matching built shell. Coverage includes clipping and reversed endpoints,
work/storage limits, atomic output failures, prepared-row reuse, ASCII-only
builds, monochrome, locale fallback, visual fixtures and PTY lifecycle/resize.
Changed Zsh files passed parse checks. The final test log is local to
`.build/canvas-make-test.log`; it is not needed to reproduce the suite.

[Recorded benchmarks](../benchmarks/README.md#character-canvas) compare raster
compilation, cached drawing and full rebuilds, with whole-shell peak RSS and
logical resource counts. At 16×64 cells, the measured Braille medians were
28.319 ms for cached drawing and 45.041 ms for rebuild plus drawing; these exclude
refresh and terminal paint latency. Retain this evidence for milestone 7.

## 3. Capability evidence and portability

Establish trustworthy reporting before introducing more negotiated protocols.
Read-only inspection and active negotiation must be distinct operations.

- [x] Define capability records separating support status, evidence source and
  enabled state. Preserve `unknown`; distinguish compiled support, terminfo,
  observed replies and explicit application overrides.
- [x] Implement passive inspection using existing evidence without writing
  queries, consuming input or enabling terminal modes.
- [x] Define and implement bounded, explicit query handling through the existing
  input owner: fragmented replies, timeouts, unsolicited/late replies, unrelated
  keystrokes, cancellation, suspend/resume and cleanup.
- [x] Create a reproducible compatibility matrix recording terminal, multiplexer,
  curses, Zsh and locale versions. Record untested combinations honestly; include
  a remote/slow connection scenario and interruption cases.
- [x] Expand real-shell job-control tests around explicit suspend/resume, including
  foreground/background transitions and applications' signal/trap ownership.
- [x] Investigate no-refresh input on another curses implementation; enable it
  only with equivalent presentation evidence, otherwise retain the unsupported
  result and document the tested limitation.

**Completion:** an inspector explains both what is known and why, while failed or
unanswered negotiation preserves usable input and cleanup. This does not imply
support for every terminal or curses implementation.

**Completed 2026-09-10 — implementation commit `5601ecb`.**
The [capability guide](capabilities.md) specifies passive records with independent
compiled support, evidence, record-only overrides and module activation. Explicit
DECRQM requests for paste, focus and synchronized output use exact reply keys in
the existing curses decoder; there is one pending request and one attempt per
mode per session. Unanswered requests stay unknown. No focus or synchronized-output
activation was introduced. The inspector begins passively and lets applications
exercise queries and overrides deliberately.

Verification: all 89 tests passed against the selected public Zsh 5.9.2 source
release and matching built shell. Coverage includes fragmented/late/invalid
reports, all five reply values, registration rollback, optional builds, paste,
cleanup, inspector resize and application-owned signal traps through interactive
`bg`/`fg`. Background resume now refuses to change terminal modes where terminal
process groups are available. Changed Zsh files passed parse checks; the native
manual builds and the exported integration patch passes a dry run against the
public source release. Final local log: `.build/capabilities-final-make-test.log`.

The [portability record](portability/README.md) includes reproducible real xterm,
tmux and screen observations plus controlled slow/unresponsive PTY scenarios.
Actual SSH sessions and other emulator configurations are explicitly untested.
The separate pinned NetBSD curses build passed byte and wide-character input-pad
presentation probes. Full alternate-library module integration, resize and the
retained-window suite remain unverified, so the native no-refresh gate stays
ncurses-only (status 2 elsewhere). This completes the requested investigation;
widening that gate is a separately bounded portability follow-up, not a claim of
shipped NetBSD module support.

## 4. Focus and richer keyboard events

Ship focus reporting first, then add one bounded negotiated keyboard protocol.
Preserve the inherited decoder behavior when the new feature is disabled.

- [x] Extend the structured event schema for focus changes and define activation,
  deactivation, ownership and cleanup; implement opt-in focus reporting.
- [x] Specify the supported keyboard-protocol subset: key identity, modifiers,
  text, press/repeat/release and explicit unknown/unsupported fields.
- [x] Implement negotiation and decoding within the single input owner, defining
  coexistence with legacy keys, mouse, paste and capability replies.
- [x] Extend the event inspector and form recipe to demonstrate richer shortcuts
  and focus behavior while retaining the existing keymap as a fallback.
- [x] Test fragmented/ambiguous input, timeouts, paste collisions, opt-out,
  suspend/resume, unload and the compatibility matrix from milestone 3.

**Completion:** supported enhanced events are demonstrable, and unsupported or
unnegotiated sessions keep working with the existing input API.

**Completed 2026-09-10 — implementation commit `9c207f4`.**
The [enhanced-input guide](enhanced-input.md) specifies opt-in focus ownership and
a negotiated kitty keyboard subset with key identity, modifiers, associated UTF-8
text and press/repeat/release actions. Both use the existing curses queue alongside
legacy keys, mouse, paste and capability replies. The keyboard tail is bounded to
256 bytes and 250 ms, with at most 16 associated Unicode scalars; unknown data is
reported explicitly. Suspend/resume, off, end and unload have documented mode
restoration and partial-packet rules. Legacy records retain their existing shape.

The event inspector and form accept `--focus --keyboard`, negotiate in their own
event loops and retain their legacy keymaps. The form preserves selection through
terminal focus changes, ignores release events for editing and demonstrates
Ctrl+Shift+S validation. Application shortcut and rendering policy stays in Zsh.

Verification: all 93 tests passed against public Zsh 5.9.2 and its matching built
shell, including narrow/unavailable builds, fragmented and interrupted packets,
scalar and byte limits, timeouts, paste/mouse/query coexistence, balanced mode
cleanup, enhanced recipes and focus across interactive `bg`/`fg`. Changed Zsh files
passed parse checks, the native manual builds, and the exported integration patch
passes a dry run against the selected public source release. Final local log:
`.build/enhanced-final-make-test.log`.

The [expanded terminal matrix](portability/README.md#enhanced-input-follow-up)
records direct xterm focus activation, conservative fallback through the tested
tmux/screen configurations, and kitty 0.44.0 shortcut press/release and associated
text from synthetic keys on a private Xvfb display. Other terminal versions,
physical keyboard/IME behavior and actual SSH remain untested. Alternate-layout
identities and arbitrary future protocol extensions are outside this subset.

## 5. Frame presentation

Use synchronized output as an optional addition to curses' existing screen diff.
Keep application frame boundaries explicit.

- [x] Define where synchronization begins and ends around the final update,
  including staging, ordinary refreshes, nested attempts and an empty frame.
- [x] Implement opt-in activation with milestone 3's evidence model; leave the
  ordinary presentation path available when support is unknown or absent.
- [x] Bound the owned region to the final update and define flushing, failed
  updates, interrupted frames, suspend/resume, end and unload cleanup; document
  blocking-write and emulator-timeout limits.
- [x] Exercise a redraw-heavy chart/table example with hidden intermediate state.
- [x] Verify emitted ordering in PTYs and observable partial-frame behavior on
  recorded terminal/slow-link configurations. Separate byte-order guarantees from
  actual emulator rendering observations.

**Completion:** the explicit frame path has a documented cleanup contract and
measured evidence of improvement where supported, without promising universal
atomic terminal painting.

**Completed 2026-09-10 — implementation commit `808aa2f`.**
The [frame-presentation guide](frame-presentation.md) specifies `sync on|off`,
requiring an accepted mode-2026 reset report. Activation configures explicit
`present` calls without opening a terminal region between commands. Each call
queues Zsh traps, flushes preceding output, brackets one curses update and attempts
reset before releasing deferred traps. Ordinary refresh and resume repaint retain
their existing paths. Empty frames, nesting, failed updates and failed-reset
recovery are documented and tested. Configuration survives suspension and clears
on end/unload.

The bound is one update plus marker writes, **not a hard wall-clock deadline**:
blocking terminal I/O can delay reset, and the protocol specifies no universal
emulator timeout. No watchdog, application trap replacement or nonblocking
descriptor mutation is introduced. This is an explicit implementation limit.

The task monitor accepts `--sync`, negotiates in its event loop and composes its
table/chart views before presenting. It retains ordinary presentation on rejected
or unanswered negotiation. All 96 tests passed against public Zsh 5.9.2 and the
matching built shell. Coverage includes non-reset evidence, unavailable builds,
empty frames, nested calls, injected update/reset failures, deferred SIGINT traps,
off/suspend/unload recovery, and more than 100 monitor frames with resize and
chart/table changes. Changed Zsh files passed parse checks; the native manual
builds and the integration patch passes a dry run against the selected release.
Final local log: `.build/sync-final-make-test.log`.

The [rendering matrix](portability/README.md#frame-presentation-follow-up) records
actual Xvfb pixels while native output is paused midway through a frame. In kitty
0.44.0, a roughly 181 ms pause exposed partial changes without synchronization and
zero changes with it; both complete frames became visible afterward. The tested
xterm, tmux and screen paths declined activation. The probe separates native byte
ordering, relay delay and sampled emulator pixels; physical display latency,
actual SSH and arbitrary terminal versions remain untested.

## 6. Overlays and region composition

Make transient surfaces predictable while retaining application control of modal
behavior, focus, commands and layout.

- [x] First demonstrate explicit stacking and hide/show using existing independent
  windows and presentation order; document the limitations this exposes.
- [x] Specify shared window-tree geometry: parent/child constraints, retained
  content, cursor clamping, resize ordering and failure behavior; implement and
  test the supported operations without changing independent-window semantics.
- [x] Evaluate optional curses panel-library support against the first example.
  Record whether it solves a demonstrated gap and how its updates would coexist
  with stage/present, refresh and optional synchronized output.
- [x] Define transparent-cell copying separately from opaque region copying:
  transparent versus styled blank cells, overlap, backgrounds and wide-glyph edges.
  Implement the bounded operation once these semantics are testable.
- [x] Add overlapping-surface fixtures and an example covering move, resize,
  hide/show, reveal, clipping and injected failure paths.

**Completion:** the supported composition path and tree/region operations have
clear behavior and tests. If panel-library integration proves unnecessary, record
that decision rather than adding a second stacking mechanism by default. A native
panel API, if justified, becomes a separately tracked extension.

**Completed 2026-09-10 — implementation commit `e1d6706`.**
The [composition guide](overlays-and-trees.md) documents independent stacking,
shared-tree geometry and transparent regions. The first recipe uses existing
independent windows and stage order to demonstrate hide/show, reveal and movement.
The richer recipe adds clipped composition, child views, geometry changes,
transparent/opaque selection, rejected geometry and optional synchronized output.
Application visibility, layout, key bindings and focus policy remain in Zsh.

`treewin` reconstructs a bounded owning tree with independent root backing and
shared descendants, preserving relative offsets, handle names, drawing/input
state and clamped cursors. Children must fit their parents; moving a child selects
parent cells rather than carrying separate content. Preparation failures preserve
the live tree. Post-publication retirement failure reports the applied geometry
and retains coherent handles plus one bounded cleanup obligation. Pads and trees
rooted in `stdscr` are outside this API; existing independent-window operations
retain their restrictions. Drastic terminal shrink can require application-driven
surface recreation, as the richer recipe demonstrates.

`overlay` snapshots the source before copying opaque runs. Only an unstyled,
color-zero space is a hole; styled blanks and non-space backgrounds are opaque.
It retains `copy`'s rectangle budget and aliasing semantics. Split wide-glyph edges
remain subject to native curses behavior, and a failed run write can leave partial
output. No alpha blending or portable wide-edge reconstruction is claimed.

The panel-library evaluation concludes that these working explicit composition
paths do not justify another native stack. Its lifecycle and refresh ownership
costs, potential future damage-tracking value, and required relationship to
`present` are recorded. No panel API or performance advantage is claimed.

Verification: all 102 tests passed against public Zsh 5.9.2 and the matching built
shell. Coverage includes parent/child/grandchild sharing, sibling geometry,
resource limits, cursor/style/timeout retention, optional implementations,
construction and retirement failures, aliased transparent copies, styled blanks,
wide/narrow paths, recipe stacking/reveal, clipping and resize cleanup. Changed
Zsh files passed parse checks, the native manual builds, and the integration patch
passes a dry run against the selected public release. Final local log:
`.build/overlays-final-make-test.log`.

## 7. Diagnostics and measured optimization

Measure the new applications before adding batching or moving algorithms to C.

- [x] Define meaningful diagnostics: live resource counts, documented budgets,
  prepared-row reuse and elapsed work at observable boundaries. Distinguish shell
  work, native work and output from unmeasurable emulator paint time.
- [x] Add passive resource inspection where missing, with no input reads,
  protocol activation, hidden refreshes or session-specific path dependencies.
- [x] Benchmark charts, canvas, forms, document reflow and overlapping surfaces
  at representative sizes, including repeated and changing data.
- [x] Optimize demonstrated companion-layer costs first, such as redundant
  measurement, style resolution or rebuilding unchanged rows; preserve semantics.
- [x] Publish before/after results and decide whether native batching or canvas
  acceleration has enough benefit to justify a separate API proposal.

**Completion:** reproducible measurements explain the important costs, and any
claimed optimization preserves output and resource behavior. Multi-operation
batches remain conditional future work unless these measurements justify them;
record their validation, partial-failure and budget contract before implementation.

**Completed 2026-09-10 — implementation commit `2b77290`.**
The [diagnostics guide](diagnostics.md) defines passive `resourceinfo` counts and
budgets, prepared-row creation/draw counters, shared-window accounting and retained
tree handles. Inspection works headlessly, while suspended and after cleanup,
without consuming input, presenting a frame or retrying failed retirement.

The [component measurements](../benchmarks/README.md#component-boundaries) cover
charts, canvas, forms, document reflow, overlapping surfaces and ordinary/prepared
rows at 8×32 and 16×64, with repeated and changing data. Five trials of twenty
measured frames separate component work, staging and presentation; all raw samples
and final retained-cell hashes are checked in. Removing one redundant raster
validation pass reduces repeated large-canvas work from 28.733 to 17.613 ms
(38.7%) and changing-canvas work from 56.139 to 45.265 ms (19.4%). Every public
call still validates the whole raster. All 28 before/after cases retain matching
snapshot hashes and terminal-output lengths across all five trials.

Decision: defer generic native batching. Native composition is small in these
workloads; larger/frequently changing canvas scenes warrant a separate measured
acceleration proposal, distinguishing raster compilation from row encoding.
No new batch or native canvas contract is introduced. Recorded times include
shell dispatch and native calls, and do not measure emulator paint latency.

Verification: all **104 tests passed** against the selected public Zsh 5.9.2 source
release and matching shell. Coverage includes unavailable prepared-row builds,
failed writes, retained-tree cleanup failures, destination validation, suspension,
release/reset/reload, queued input and hidden-frame preservation, unchanged
resources on canvas redraw, malformed final-cell rejection and ASCII fallback.
Changed Zsh files pass parse checks, the native manual builds, and the additive
integration patch passes its dry run. Final local log:
`.build/diagnostics-final-make-test.log`.

## 8. Unicode interaction accuracy

Improve evidence and editing behavior without equating segmentation with terminal
shaping. Keep the current clipping-unit contract available.

- [x] Add a documented corpus covering combining sequences, emoji modifiers,
  joiners, flags, variation selectors and ambiguous-width characters.
- [x] Compare native geometry, retained curses cells and actual rendering on the
  recorded compatibility matrix; distinguish segmentation, width and storage gaps.
- [x] Specify an optional grapheme-boundary policy, its Unicode-data version,
  dependency/build implications and relation to native cell-width calculations.
- [x] Prototype the policy in text queries and companion field movement/deletion,
  preserving source byte anchors and the existing default behavior.
- [x] Test selection, clipping, document reflow, narrow builds, locale changes and
  unsupported cases; publish the supported boundary policy and remaining limits.

**Completion:** a tested corpus and bounded optional segmentation implementation
exist. Do not claim that every emoji shapes correctly merely because its source
sequence is treated as one editing unit. Existing companion word wrapping remains
in place; a new native multiline API requires a separate demonstrated need.

**Completed 2026-09-10 — implementation commit `124ccfa`.**
The [Unicode boundary guide](unicode-boundaries.md) specifies the optional
Unicode 17.0.0 terminal profile. `textpos` accepts a final `cell|grapheme` policy;
`textinfo` accepts it after an explicit column budget. The default is unchanged.
Opted-in fields move, select, delete and clip complete units, preserve byte
anchors after splices and streamed paste, and retain per-field policy in forms.
Document reflow keeps its existing source-byte and word-wrapping behavior.

The engine passes all **766** official Unicode 17 extended-grapheme test vectors.
The terminal adapter preserves native zero-width clipping units and printable
validation, explicitly requires UTF-8 and `MULTIBYTE`, and bounds optional queries
to one MiB of original bytes. Checked-in generated tables, source hashes, license
and a reproducible generator add no runtime library or download dependency.

The [18-case corpus](../tests/unicode/corpus.json),
[recorded terminal matrix](portability/unicode-matrix-2026-09-10.json) and eight
[raw/native captures](portability/unicode-captures/) compare system widths,
retained curses cells, cursor replies and actual pixels in xterm 407,
xterm/tmux next-3.3, xterm/Screen 5.0.1 and kitty 0.44.0. Observed emoji-width,
combining-storage and Screen rendering gaps are documented. Grapheme grouping
does not claim correct glyph shaping or reconcile emulator and curses widths.
Other emulator versions, actual SSH, IMEs and bidi interaction remain untested.

Verification: all **109 tests passed** against the public Zsh 5.9.2 source release
and matching shell, including corpus byte/column queries, clipping, selection,
splice resegmentation, split UTF-8 paste, source anchors, unavailable builds and
locale/option changes. Generated tables reproduce exactly, changed Zsh files
parse, the native manual builds, and the additive integration patch passes its
dry run including both headers. Final local log:
`.build/unicode-final-make-test.log`.

## 9. Interaction recording and replay

Extend the existing fixtures and scripted PTY tests into reusable recordings.
Separate replaying application events from restoring a saved screen.

- [x] Define a versioned, bounded recording with initial geometry, relevant
  capability/locale context, event order and timing policy. Recording must be
  explicit and document that input/paste content may be included.
- [x] Replay scripted input and resize sequences against examples using a
  deterministic timing mode and the current portable fixture comparisons.
- [x] Add native wide-character continuation metadata with explicit unknown
  behavior for clipped/shared-window edges; preserve existing snapshot consumers.
- [x] Specify a separate screen-serialization/restoration contract for text,
  styles and wide-cell occupancy, with validation and resource budgets. Retain
  readback fixtures as the comparison format rather than silently changing them.
- [x] Implement the supported text-screen restoration subset and verify round
  trips, corrupt/oversized input, unsupported cells, allocation failures and cleanup.
- [x] Turn an input/resize failure into a saved recording with a readable diff,
  and document when timing-dependent failures still need a real terminal.

**Completion:** an explicitly recorded interaction is reproducible, and the
supported restoration subset is distinct from raw readback. Future image/text-size
placements are not implicitly included in this version.

**Completed 2026-09-10 — implementation commit `038b347`.**
The [recording and restoration guide](recording-and-restoration.md) defines two
separate bounded formats. Explicit `zdraw-interaction-1` recordings drive the form,
document and canvas recipes through real PTYs, retain native events and capability
context, and compare existing portable fixtures at presentation barriers. Input,
geometry, traffic and waits have explicit limits. A checked-in split-UTF-8 paste
and resize recording matches; a deliberate expected-cell mutation demonstrates
saving and reporting a failed assertion without claiming a new application defect.

Optional `snapshot ... occupancy` adds conservative native metadata while keeping
default snapshot consumers unchanged. Interior wide runs are explicitly inferred
from public readback; ambiguous clipped/shared edges remain unknown. The companion
`zdraw-screen-1` format supports single-column text cells and stored combining marks,
with symbolic styles independent of session pair IDs. Wide cells, unsupported
attribute bits and uncached nonzero pairs are rejected. All rows are validated and
prepared before drawing; temporary resources are released on failures. Curses write
failures can leave partial output, and allocated color pairs remain session-cached.
Images, scaled text and arbitrary wide-cell restoration are outside this subset.

Verification: all **115 tests passed** against the selected public Zsh 5.9.2 source
release and matching built shell. New coverage includes all three replay recipes,
fragmented paste, resize, saved readable mismatches, malformed/oversized recordings,
a saturated input queue with deadline/child/descriptor cleanup, screen round trips,
corrupt/oversized data, wide/shared edges, injected allocation/write failures,
prepared-name collisions and restoration after module reload with changed pair
allocation order. Existing snapshot schemas and visual baselines still pass.
Changed Zsh files pass parse checks, the native manual builds, and the additive
integration patch passes its dry run. Final local log:
`.build/replay-final-make-test.log`.

## 10. Optional motion

Begin with activity feedback. Decorative transitions should remain easy to omit.

- [x] Implement bounded activity-indicator frames and caller-driven advancement;
  the component must not start a background timer or own the event loop.
- [x] Define reduced-motion behavior, cancellation, off-screen behavior and
  immediate completion for disabled effects.
- [x] Prototype one finite transition using existing region/restyle operations,
  preserving focus position and meaningful content throughout.
- [x] Use bounded frame/shade sets and resource accounting; avoid allocating an
  unbounded stream of RGB color pairs for fades.
- [x] Verify deterministic frames, resize, interruption, cleanup and idle cost;
  demonstrate both animated and immediate-state versions in the task monitor.

**Completion:** motion supplies useful state feedback with a tested nonanimated
alternative and explicit resource limits.

**Completed 2026-09-10 — implementation commit `e289926`.**
The [optional-motion guide](optional-motion.md) specifies caller-owned, validated
`zdraw-motion-1` state, explicit advancement and cancellation, hidden-frame freezing,
and immediate finite-transition completion in reduced/off modes. The passive Zsh
loader owns no clock, event loop, native object, input or terminal protocol.
Activity uses four fixed ASCII or optional Braille frames, with static pending,
paused, complete and cancelled markers. A finite emphasis transition uses existing
`restyle` over at most 4,096 cells: bold, underline, then the caller's uniform base
style. Content and cursor positions remain in place; no RGB fade palette is built.

The task monitor defaults to no motion and accepts `--motion`, `--reduced-motion`
and `--no-motion`, alongside `--sync`. Its `a` key cycles policies. Status words,
progress and selection remain available in every mode. The existing simulation
timeout drives frames; paused/completed work uses blocking input after visible
transitions settle. INT/TERM record interruption and leave through `always`,
cancelling both instances and restoring the terminal with status 130/143.

Verification: all **120 tests passed** against the selected public Zsh 5.9.2 source
release and matching built shell. New headless/PTY tests cover deterministic frame
sequences, static alternatives, invalid data, hidden/paused/completed behavior,
state and cursor preservation, combining/wide content, rectangle budgets, resize,
Queue selection, interruption at presentation and during blocking input, and
terminal cleanup. One hundred transition repetitions allocate zero additional
color pairs after warmup in 256-color and monochrome profiles; prepared-row count
remains zero. A settled paused monitor makes zero further input calls or
presentations during a 400 ms observation, exceeding the old polling interval.
These are scheduling/resource observations, not emulator paint or CPU-time claims.
Changed Zsh files pass parse checks; the native module is unchanged. Final log:
`.build/motion-final-make-test.log`.

## 11. Inline shell interaction

Start with explicit handoff to one bounded interaction, not simultaneous ZLE and
curses ownership.

- [x] Document ownership of the cursor, screen region, scrollback, input and
  redisplay before choosing an implementation path.
- [x] Prototype one short picker below the prompt, using an explicit ZLE handoff
  and returning a value to the shell with a defined retained-output policy.
- [x] Integrate asynchronous data using existing `zselect`/`zle -F` mechanisms
  where appropriate; keep one input owner and bounded callback work.
- [x] Test prompt redisplay, resize, cancellation, command failure, job-control
  transitions, descriptor cleanup and return to normal shell editing.
- [x] Record the architectural result and either extract a reusable companion
  helper or document the concrete blocker and retain the prototype as research.

**Completion:** a repeatable shell integration example exists with known limits.
A prototype or documented blocker does not mean a general inline UI API has shipped.

**Completed 2026-09-10 — implementation commit `eb437e7`.**
The [inline-shell guide](inline-shell.md) records ownership and the architectural
result. The [picker prototype](../examples/inline-picker.zsh) uses ZLE
`POSTDISPLAY`, a private recursive-edit keymap and an explicit returned scalar.
Native `textpos` and `textinfo` supply headless validation/clipping; no curses
session starts. The disposable [launcher](../scripts/inline-shell.zsh) demonstrates
optional quoted insertion and removes its temporary startup configuration when
the child shell exits, preserving the child's status.

Optional async choices use a caller-owned pipe, one owned duplicate, and
`zle -F -w`. Each callback reads at most 1,024 bytes without waiting; the protocol
allows at most 16 KiB and 32 total choices of up to 256 bytes each. Partial UTF-8
records accumulate until newline. Completion, invalid data, excess input, read
failure and cancellation remove the watcher before closing its duplicate. The
caller retains responsibility for its original descriptor and producer process.
Selection returns literal data without changing the command buffer. Cancellation
restores cursor, mark, selection, keymap, `POSTDISPLAY` and highlights.

Verification: all **127 tests passed** against the selected public Zsh 5.9.2
source release and matching built shell. Seven new PTY tests cover selection,
cancellation, emacs/vi insertion, existing display state, ignored bracketed paste,
fragmented async input, byte/item limits, invalid/truncated records, descriptor
and watcher cleanup, repeat invocation, unchanged terminal modes, command failure,
and stop/background/foreground job transitions after cancellation. The launcher
test covers its insertion guard, quoted result, nonzero exit and temporary-file
cleanup. Changed Zsh files pass parse checks. Final log:
`.build/inline-final-make-test.log`.

Limits are explicit: ZLE reflows immediately on resize, while the picker remeasures
on the next widget dispatch or complete async update. Ctrl-Z cancels the picker;
suspend the shell only after cleanup. Concurrent writers of `POSTDISPLAY` require
coordination, and ZLE scrolling can leave historical fragments in scrollback.
The prototype remains research in `examples/`. A general native inline API is
deferred because full-screen curses initialization supplies no shared prompt
origin, scrollback policy or coordinated ZLE redisplay lifecycle. This milestone
completes the bounded experiment and records that blocker; it does not claim to
solve native inline drawing.

## 12. Image previews

Separate a portable character-based preview from terminal image placement. Each
can ship independently if its own contract is satisfied.

- [x] Prototype an optional adapter for bounded Unicode/ASCII image mosaics using
  a documented external converter; do not make it a core runtime dependency.
- [x] Define maximum input/output sizes, palette limits, invalid output handling,
  placeholder/alt text, clipping and cancellation for the adapter.
- [x] Design one opt-in terminal image-placement experiment with explicit upload,
  placement, replacement, deletion and ownership of resources.
- [x] Investigate Unicode image placeholders against curses storage and width
  limits; test redraw, scrolling, overlays, resize and multiplexer behavior.
- [x] Verify suspend/resume, end/unload, interrupted uploads and resource cleanup;
  retain the text preview when terminal support is unavailable or uncertain.
- [x] Publish a working preview example and the evidence for accepting, narrowing
  or deferring the native placement API.

**Completion:** the text-preview adapter is usable on its documented baseline.
Native image placement remains experimental until its retained-screen lifecycle
is demonstrated; merely emitting an image escape sequence is not completion.

**Completed 2026-09-10 — implementation commit `187c39b`.**
The [image-preview guide](image-previews.md) documents the optional ImageMagick 7
converter and caller-owned `zdraw-image-1` raster. The
[preview example](../examples/image-preview.zsh) decodes once before curses starts,
then draws retained colored half blocks or ASCII density cells. It supports
monochrome/theme colors, viewport cropping on resize, a missing-image placeholder,
suspend/resume and cancellation. Drawing/export owns no converter, timer,
descriptor or terminal protocol. The native module is unchanged.

Input is limited to regular PNG/JPEG files of 8 MiB, at most 4096 pixels per side
and 4,194,304 pixels total. Output is at most 4096 cells, 8192 sampled pixels and
24,576 raw RGB bytes. A five-second conversion deadline, private decoder policy,
bounded stdout reader and signal cleanup constrain the optional worker. A fixed
16-color palette bounds half-block drawing to 256 ordered color pairs; warmed
redraws allocate no additional pairs. Invalid packets leave prior raster state
unchanged. Alt text is required and limited to 256 encoded bytes.

The separate opt-in [placement fixture](../scripts/portability/image-source.zsh)
uses one private image ID and quiet, bounded kitty graphics transfers in fresh
terminals. The [recorded matrix](portability/image-matrix-2026-09-10.json) includes
48 captures across Kitty 0.44.0, Kitty through tmux `next-3.3`, Kitty through
Screen 5.0.1 and XTerm(407). Full row/column/high-ID combining marks round-trip
through the selected ncurses cells at one column per placeholder. Direct Kitty
and tmux display copied, covered, replaced and resized images. Direct Kitty
resumes successfully; the tmux profile does not restore the image after resume.
Neither restores visible image data after the interrupted-transfer reupload.
Screen/direct-APC and xterm show no test-image pixels. Every profile has zero
test-image pixels at suspend, end and unload capture points; this is visible
cleanup evidence, not proof of all terminal-side memory being released.

**Native placement API deferred:** quiet uploads do not establish acknowledged
readiness/error ownership; interruption recovery and multiplexer redisplay remain
unreliable. Curses has no image-resource registry or automatic image cleanup at
session boundaries. The fixture coordinates deletion explicitly, and its fixed
ID is only suitable for a fresh private terminal. These are concrete lifecycle
gaps, so the experiment stays research and the ordinary text preview remains
the usable baseline. Completing this milestone does not claim native image
placement support in `zdraw`.

Verification: all **137 tests passed** against the selected public Zsh 5.9.2 source
release and matching built shell. Ten new tests cover conversion/byte/dimension
limits, literal filenames, PNG/JPEG decoding, cancellation and worker reaping,
atomic data loading, palette allocation, ASCII-only builds, resize, missing-image
fallback, suspend/resume, terminal restoration, full placeholder storage and
owned protocol cleanup on interruption/signals. Changed Zsh files pass parse
checks. All 48 capture hashes were verified. Final log:
`.build/image-final-make-test.log`.

## 13. Scaled text

Keep this last: it affects geometry, repainting, hit-testing and retained-screen
representation while benefiting a narrower set of interfaces.

- [ ] Define one bounded use case, such as a large section heading, together
  with its ordinary single-cell text alternative.
- [ ] Investigate support/activation evidence and representation of occupied
  rows/columns, clipping, overlap, baselines and source-byte hit-testing.
- [ ] Prototype placement and removal without allowing curses to repaint through
  the region incorrectly; document whether a separate placement model is necessary.
- [ ] Test resize, selection boundaries, overlays, suspend/resume, cleanup and
  unavailable support, reusing findings from images and Unicode experiments.
- [ ] Publish the prototype and a decision on a reusable API; keep the ordinary
  text path as the portable default.

**Completion:** the feasibility result and limitations are reproducible. A general
scaled-text API requires a proven retained-screen contract beyond this experiment.

## Working and completion rules

Check implementation items only when code, documentation, an example where useful,
and relevant verification are complete. A design decision or experiment can be
checked when its stated evidence is recorded; do not mark a corresponding feature
implemented if the decision was to defer it. Record deferred work and its reason
beside the affected milestone so it does not become an endless open-ended task.

Keep components, styles, layouts and application policy in optional Zsh libraries.
Add C only for a demonstrated general-purpose gap or measured bottleneck. Preserve
inherited `zdraw` behavior, separate stock `zsh/curses`, and the original sources.
New protocols stay opt-in with one input owner and explicit cleanup.

For code changes, use the Zsh expertise skill where Zsh semantics matter and run
`make test` with `ZSH_BUILD_ROOT` selecting the public Zsh source release and the
matching built shell. Build in `.build/`; never change an installed module or
source tree during normal verification. Extend PTY tests and visual fixtures for
meaningful behavior, and record actual terminal coverage separately from simulated
coverage. Native API changes also need native manual and integration-patch checks.

Commit and push each completed implementation milestone, recording its commit and
verification evidence here. Stop at its completion boundary before beginning a
later experimental branch of work unless that work is part of the active request.
