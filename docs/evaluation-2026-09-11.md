# zdraw evaluation: the good, the bad and the ugly

Assessed 2026-09-11 against the premise that `zdraw` is `zsh/zcurses` plus many
new features intended to make TUI applications easier to write in and for Zsh.
This is a design and product critique, not a defect list. It is written to be
acted on, so it is blunt where being polite would hide the point.

## Summary verdict

`zdraw` is an unusually strong **terminal primitive layer** and a
**notably weak toolkit**. The C module is the best part of the project by a wide
margin: it is disciplined, well-documented, honest about its limits, and it
genuinely removes work that shell code cannot do well. The Zsh layer above it —
the part that is supposed to deliver the stated goal of "easing the development
of TUI apps" — is thin, unergonomic, silent on failure, and does not consume the
performance primitives the C module was built to provide.

Put differently: the project has repeatedly solved the *hard* problem (native
terminal behavior) and repeatedly declined to solve the *tedious* one
(application ergonomics). The stop line in `docs/scope.md` is the right decision
at the right time, but it froze the project at the moment the interesting work
was about to start.

### Measured shape

| Layer | Size | Assessment |
| --- | ---: | --- |
| `Src/Modules/zdraw.c` | 5,903 lines, 58 subcommands (upstream `zcurses`: 20) | Strong |
| `Src/Modules/zdraw_grapheme_data.h` | 1,682 lines generated | Justified but a maintenance liability |
| `lib/ui/*.zsh` | 2,237 lines, 46 public functions | Weak relative to ambition |
| `Doc/Zsh/mod_zdraw.yo` | 1,660 lines | Strong |
| `README.md` | 1,621 lines | Too big to serve any single reader |
| `docs/*.md` | 5,320 lines across 25 files | Over-produced; heavily overlapping |
| `tests/` | ~9,800 lines, PTY-based | Strong |
| CI | none | Missing |

Documentation is roughly 8,600 lines against roughly 8,100 lines of shipped
implementation. That ratio is a real signal, and it is discussed under "ugly".

---

## The good

### 1. The native surface is the right native surface

The jump from 20 to 58 subcommands is not padding. Nearly every addition targets
something that is genuinely expensive or impossible to express in shell:

- **`spans` / `spansclip`** — one module call for a full styled row instead of
  `move` + `attr` + `string` per segment. The measured 4.4–6.0x improvement in
  `benchmarks/README.md` is exactly the right kind of justification, and the
  benchmark methodology (fresh session per trial, alternating backend order,
  warmup frames excluded, byte counts captured from a real PTY rather than
  estimated) is more rigorous than most projects of this size manage.
- **`prepare` / `draw` / `unprepare`** — immutable decoded rows with
  pre-allocated color pairs and a 16 MiB accounted budget. This is the correct
  answer to "shell string processing per frame is the bottleneck."
- **`textinfo` / `textpos` / `textwrap`** — headless cell measurement, hit
  testing and wrapping with byte *and* column ranges. Wide characters and
  combining marks in a shell TUI are a classic source of silent corruption;
  solving this once in C is obviously correct.
- **`addpad` / `viewport` / `stage` / `present`** — offscreen composition with
  an explicit single presentation point. This is the single most valuable
  addition for anyone building a real application, and it is the thing stock
  `zcurses` most conspicuously lacks.
- **`geometry`** — reading `TIOCGWINSZ` directly instead of forking `stty`.
  Small, obvious, and immediately useful.
- **`suspend` / `resume` / `inputinfo`** with `lib/zdraw-run.zsh` — running a
  foreground command from inside a TUI without corrupting terminal state is
  something almost every real application needs and almost every hand-rolled
  shell TUI gets wrong.

### 2. Capability honesty is exemplary

The separation in `capabilities`, `colorinfo`, `resourceinfo` and `zdraw_features`
between *compiled support*, *terminal report*, *application override* and
*enabled state* — with `unknown` as a first-class value distinct from
"unsupported" — is better engineering than most terminal libraries in any
language. `docs/portability/README.md` continuing this into the test matrix
("no response from a multiplexer is not a negative support claim", untested
configurations recorded as untested rather than omitted) is a genuine strength
and should be preserved unchanged.

### 3. Protocol additions have a real ownership model

Bracketed paste, focus reporting, the kitty keyboard subset and synchronized
output are all opt-in, all route through the single curses input owner rather
than a competing reader, all define cleanup on `end`/unload/suspend, and all
document what happens when the terminal never answers. `docs/application-integration.md`
is explicit that raw mode means Ctrl-C becomes an input byte rather than a
signal. Very few projects state that; most just break.

### 4. The build is genuinely reproducible and non-invasive

`scripts/build.zsh` refuses to touch the supplied source tree, refuses separate
source/build trees rather than half-supporting them, validates that the cache
belongs to the same source root, and stages artifacts under `.build/`. It fails
with an actionable message at every check. The `make patch` export producing a
clean additive patch against upstream Zsh keeps the contribution path open.
This is the work of someone who has been burned by build systems and fixed it.

### 5. Testing is real testing

PTY-driven tests that spawn the matching shell, assert on actual rendered cells,
and cover resize, end/reinit, unload/reload and interrupted sessions are far
beyond the norm for shell projects. `snapshot`/`cellinfo` readback plus
`lib/ui/fixture.zsh` and `scripts/visual_diff.py` give the project a visual
regression story that most TUI libraries lack entirely.

### 6. The scope document is the best document in the repository

`docs/scope.md` is a model of its kind: it names the rejected direction, explains
*why* the output was not good enough, refuses to treat passing tests as evidence
of worth ("If the visible result misses the quality bar, reject the feature
instead of lowering the bar to finish a checklist"), and points at the commits
where the removed work lives. Keeping that discipline is worth more than any
feature in the backlog.

---

## The bad

### 1. The toolkit does not use the module's own fast paths

This is the most important technical finding in this report.

`spans` and `prepare`/`draw` exist because per-segment drawing is slow. Then
`lib/ui/table.zsh` draws through `_zdraw_ui_row`, which issues **`textinfo` +
`spansclip` per cell**. A 20-row × 5-column table therefore costs roughly 220
module calls per frame — one `fill` per row, plus two calls per cell — and
re-measures every cell's width on every frame even when the data has not
changed. The `spans` call in `lib/ui/table.zsh:105` draws the single-character
selection marker; the actual row content does not use it.

`zdraw prepare` is used in exactly one place in the entire library layer
(`lib/ui/screen.zsh:104`), which is restoration tooling, not a component.

The C module's headline optimization is, in practice, unavailable to anyone
using the components the project offers as its front door. Either the components
should batch rows into one `spans` call, or the module needs a clipped
multi-segment row primitive that components can actually target.

### 2. The library layer is silent on every failure

156 `zwarnnam` calls in `zdraw.c`. **Zero** diagnostic messages across all of
`lib/`, against 242 bare `return 1` statements.

A misspelled style token, an out-of-range padding value, an undeclared `reply`
array and a rectangle that does not fit all produce the same thing: `return 1`,
no message, an `|| return` chain that unwinds to a `dirty=0` loop, and a screen
that silently stops updating. The failure surface is worst precisely where the
user is least equipped to debug it, because the terminal is in curses mode and
stderr is not visible anyway.

Compounding it, the status codes are inconsistent: `zdraw-layout-split` returns
2 for "valid constraints that do not fit" versus 1 for malformed arguments
(`lib/ui/layout.zsh`), and `zdraw-input-check` documents 0/1/2 with distinct
meanings — but `zdraw-label`, `zdraw-panel`, `zdraw-table` and most others
collapse everything to 1. A caller cannot distinguish "your arguments are wrong"
from "the window shrank".

**This alone probably costs more application-developer hours than every
performance improvement in the project saves.**

### 3. The calling convention is a trap

Components communicate through dynamically scoped globals the caller must
declare by exact name: `reply`, `zdraw_ui_theme`, `zdraw_ui_style`,
`zdraw_ui_layout`, `zdraw_ui_list`, `zdraw_ui_form`, `zdraw_ui_input`,
`zdraw_ui_tracks`, `zdraw_ui_headers`. Return-by-`reply` is idiomatic Zsh
(`zstyle`, `zparseopts`), but nine distinct well-known names, each with a
type check that returns a bare 1 when you forget it, is a different thing.

`examples/list-detail.zsh` opens with two `typeset` lines of pure ceremony
before any application logic, and `recipe-render` re-declares four more locals.
Worse, several of these are *clobbered* rather than merged:
`zdraw-list-update` ends with `zdraw_ui_list=(selected "$_zui_s" first "$_zui_f")`,
so an application cannot keep its own keys in that association.

### 4. Layout and state are circularly coupled

`zdraw-list-update` requires the visible row count, which is only known after
the panel is drawn. So `examples/list-detail.zsh` calls it in the event loop
with a `visible` value captured during the *previous* render, and calls it a
second time inside `recipe-render` with a different value depending on which
layout branch was taken. On the frame after a resize, selection scrolling is
computed against a stale viewport.

This is not a bug in the example; it is the API forcing the example into it.
A component set that owned "given this rectangle and this state, here is the
resulting scroll offset" — separately from drawing — would remove the hazard.

### 5. Every frame recomputes everything

There is no dirty tracking, memoization or invalidation anywhere in `lib/`.
Each frame re-validates every style token string character by character,
re-resolves the theme, re-runs the layout splitter, and re-measures every string.
`zdraw-ui-style` validates its state vocabulary against a 30-alternative pattern
match *twice* per call (once for inactive variants, once on replay). For a
static frame this is entirely wasted work — and it is the layer where such work
is most expensive, because it is interpreted shell.

### 6. Mouse support stops at the module boundary

The module decodes mouse events and `textpos` provides hit testing, and
`examples/hit-test.zsh` demonstrates both. But **no component accepts a click.**
Grepping `lib/` for mouse or hit-testing returns one match, in a test fixture.
Lists, tables, tabs, forms and documents are keyboard-only, and there is no
helper to map a `(row, column)` back to a list index or a tab. For a project
whose research corpus includes modern TUIs, this is a conspicuous omission —
and it is *cheap* to fix, because the geometry is already computed during layout.

### 7. No distribution story

To use `zdraw` you must download a Zsh release, apply a patch, regenerate
autoconf, and build an entire shell. The README states plainly that a module
built for one Zsh configuration is not portable to another, and `design.md`
concedes that "build identity, ABI metadata and a broader error contract remain
separate design work."

The consequence is that the realistic user population is "people willing to
build Zsh from source," which is close to zero outside this repository. There is
no version parameter, no `zdraw_version`, no ABI marker a script can test, and
no packaging guidance. The upstream-contribution path is documented, but that is
a path for the *maintainers*, not a way for anyone to run an application today.

### 8. No CI

52 commits, a sophisticated PTY test suite with real Xvfb/xterm/tmux drivers,
and nothing runs it automatically. The portability matrix — the project's
strongest evidence artifact — is a JSON file dated 2026-09-10 that will quietly
rot. The README itself lists BSD/macOS and alternative curses libraries as
unverified; without CI that will stay true indefinitely.

---

## The ugly

### 1. Documentation sprawl has become a liability

Twenty-five documents totalling 5,320 lines, plus a 1,621-line README, plus a
1,660-line `.yo` manual, for a project with 46 library functions. The same
material appears in three or four places: `README.md` has the full API, the `.yo`
manual has the full API, `docs/design.md` narrates the phases, `docs/roadmap.md`
checklists them, `docs/implementation-plan.md` re-plans them, and each feature
family has its own guide restating the contract again.

The README in particular tries to be the marketing page, the install guide, the
migration guide, the API reference and the tutorial simultaneously. At 1,621
lines it serves none of those readers. Nobody evaluating whether to try `zdraw`
will read past line 130, and everything that would convince them — the gallery,
the recipes, a screenshot — is buried under a wall of feature paragraphs.

The docs are individually well written. Collectively they are an obstacle.

### 2. The project documents itself far more than it is used

Every feature family has a completion record, a milestone note, a portability
matrix and a benchmark before it has a second consumer. The examples directory
has 24 scripts, but nearly all of them are *feature demonstrations*
(`borders.zsh`, `colors.zsh`, `clipping.zsh`, `copy.zsh`, `restyle.zsh`,
`regions.zsh`, `viewports.zsh`, `windows.zsh`, `truecolor.zsh`,
`cell-inspection.zsh`, `snapshot-diff.zsh`, `spans`, `hit-test.zsh`) rather than
applications. Only three are real recipes.

Feature demos prove a subcommand works. They do not discover that
`zdraw-list-update` has a stale-viewport problem — that took one 148-line
application to expose. The ratio should be inverted.

### 3. The roadmap/plan documents are archaeology presented as navigation

`docs/roadmap.md` (318 lines, 58 checked / 9 unchecked),
`docs/implementation-plan.md` (644 lines, sections 1–13 including "12. Image
previews — removed" and "13. Scaled text — cancelled") and `docs/design.md`
(506 lines) are all now prefixed with a banner saying they are historical and
superseded. Three large, prominently linked documents that open by telling the
reader not to act on them is a signal the repository is carrying its own
development diary as though it were product documentation.

The git history already preserves this. Keeping 1,468 lines of superseded
planning in `docs/` — still linked from the README's second paragraph — means
every new reader spends effort determining what is current.

### 4. Licensing is unresolved

The repository ships **both** `LICENCE` (the Zsh licence, 1.9 KB) and `LICENSE`
(GPLv2, 18 KB), with no statement anywhere about which governs `zdraw`.
`Src/Modules/zdraw.c` still carries the unmodified upstream header reading
`curses.c - curses windowing module for zsh`, Copyright 2007 Clint Adams — with
a one-line comment appended below it noting the derivation. No file in `lib/`
carries any licence header. There are no SPDX identifiers anywhere. The README
never mentions licensing at all.

For a project that explicitly intends to contribute patches upstream and to be
independently distributable, this is the highest-risk item in the repository and
the cheapest to fix.

### 5. Residue from the removed image work

`docs/portability/image-captures/` is now an empty tracked directory. An
untracked `image.png` sits in the repository root. `docs/implementation-plan.md`
retains two sections describing the removed and cancelled features. The stop
line was executed decisively in the code; the sweep afterwards was not finished.

### 6. `zdraw.c` is a 5,903-line single file

Fifty-eight subcommands, the grapheme tables, the SGR parsing, the protocol
negotiation, the input decoder, the resource accounting and the parameter
definitions all live in one translation unit. It follows upstream's structure,
so it is defensible — but upstream's file is 1,600 lines. At nearly four times
that, with three or four distinct subsystems inside, it is now the kind of file
where a reviewer cannot hold the state in their head, and where an upstream
maintainer receiving a patch against it will not be able to review it either.
That directly undermines the stated contribution goal.

---

## Where it does more than necessary

Judged strictly against "ease the development of TUI apps in Zsh":

1. **`scripts/replay.py` + `scripts/replay-recipe.zsh` + the text-screen
   restoration format** (~390 lines plus tests). Deterministic PTY replay is a
   fine testing tool. Shipping it as a documented feature family with its own
   guide, milestone and format specification is testing infrastructure promoted
   to product.
2. **Optional motion** (`lib/ui/motion.zsh`, `docs/optional-motion.md`, 187 lines
   of docs for 129 lines of code). Caller-driven activity markers and a finite
   emphasis transition, with no owned timers, in a toolkit that has no mouse
   support. The priority ordering is hard to defend.
3. **The inline ZLE picker** (`scripts/inline-shell.zsh`,
   `examples/inline-picker.zsh` at 241 lines, `docs/inline-shell.md`,
   `tests/test_inline.py` at 302 lines — the largest single test file). This is a
   *different product*: a completion/prompt widget, not a TUI toolkit. It brings
   ZLE ownership, restoration and async concerns that have nothing to do with
   the rest of the surface. The scope document paused feature families; this one
   should have been the first cut.
4. **Character canvas with Braille rendering** (`lib/ui/canvas.zsh`, 344 lines —
   the largest library file, larger than table, list, form and panel combined).
   Braille plotting is visually appealing and almost never what an application
   needs. Meanwhile `lib/ui/badge.zsh` is 8 lines.
5. **`zdraw_grapheme_data.h`** — 1,682 generated lines, plus a generator script,
   to provide grapheme boundaries that `docs/design.md` itself scopes as "full
   grapheme segmentation remains outside the current contract." The cost is
   permanent (Unicode revisions) and the benefit is opt-in and partial.
6. **The `capabilities` subcommand taking up to 10 arguments** and a four-axis
   evidence model. The model is intellectually correct. For an application
   author the question is "can I use truecolor, yes or no," and there is no
   one-call answer that resolves the four axes into a decision.
7. **`overlay` as a separate subcommand from `copy`** with an identical 8-argument
   signature, differing only in blank transparency. This is a flag, not a command.

## Where it does less than necessary

1. **There is no event loop.** Every application must hand-roll the
   `timeout` / `event` / `dirty` / `case $event[type]` / resize / `always { end }`
   structure. `examples/list-detail.zsh` spends roughly 40 of its 148 lines on it,
   and every other recipe repeats it near-verbatim. `docs/scope.md` deliberately
   assigns event-loop *policy* to applications — correct — but policy is not the
   same as boilerplate. A loop helper that dispatches to caller-supplied render
   and key handlers, owns resize and teardown, and lets the application keep
   control of timing would be the single highest-value addition available, and
   it would not violate the stop line's intent.

2. **There is no focus model above the form.** `lib/ui/form.zsh` has a focus
   index over its own fields. There is nothing that moves focus between a list
   and a table, or a panel and a sidebar. Every multi-pane application invents
   `view=list|detail` by hand, as `list-detail.zsh` does. Tab-order across
   components is table stakes for a toolkit.

3. **No component accepts input.** Components render; the application decodes
   keys and calls an `-update` function. That separation is defensible, but it
   means there is no default keymap anywhere. Every application re-decides that
   `j`/`k`/arrows move a list, and any two `zdraw` applications will disagree.
   A default, overridable key-to-action mapping per component type would cost
   very little.

4. **No component is clickable.** See "the bad" §6. The geometry is already
   computed; only the mapping function is missing.

5. **There is no way to compose components into a screen.** There is no widget
   tree, no container, no z-order helper above raw `stage`, and no notion of a
   "scene" that can be re-rendered. Everything is manual coordinate arithmetic
   from `zdraw-layout-rect` into `reply`. The layout helpers are good; what sits
   on top of them is absent.

6. **No error diagnostics.** See "the bad" §2. At minimum: an opt-in
   `ZDRAW_UI_DEBUG` that writes a message and the offending argument to a file
   descriptor or log path, since stderr is unusable during a session.

7. **No text-entry scrolling model above the single field**, no multi-line
   editor, and no list filtering/search — the three things almost every real TUI
   needs and the three things hardest to get right by hand in Zsh.

8. **No versioning or compatibility contract.** `zdraw_features` reports
   compiled capability but there is no version parameter. An application cannot
   say "I need the `zdraw` that has `textwrap` with source ranges" other than by
   feature-probing each name individually — which is workable, but there is no
   documented guarantee that a feature name's *semantics* stay fixed.

9. **No user-facing entry point.** There is no `zdraw-app`, no starter template,
   no `examples/hello.zsh` of twenty lines. The shortest path from "I want a TUI"
   to "something on screen" currently runs through a 1,621-line README and a
   from-source Zsh build.

---

## Recommendations, in priority order

These are ordered by value per unit of effort. Items 1–4 are all within the
existing scope boundary — they are usability and defect work on the shipped
surface, not new feature families.

1. **Resolve licensing.** Pick one licence, delete the other file, add a
   `Licence` section to the README, add SPDX headers to `lib/` and correct the
   `zdraw.c` header block so it no longer claims to be `curses.c`. One afternoon;
   removes the only item here with legal consequences.

2. **Give the library layer a voice.** Introduce a single internal error helper,
   an opt-in debug sink (a file descriptor or path, since stderr is unusable
   mid-session), and a consistent status vocabulary: 1 for caller error, 2 for
   "valid request, does not fit", other codes for native failure. Apply it
   across all 242 bare returns. This will do more for adoption than any feature.

3. **Make components use `spans` and `prepare`.** Batch table and list rows into
   one `spans` call per row, and cache prepared rows for unchanged content. The
   module already proved this is 4–6x; the components should collect it.

4. **Add hit testing and default keymaps to list, table and tabs.** Both are
   small functions over geometry that already exists, and together they close
   the largest ergonomic gap in the toolkit.

5. **Add a loop helper.** Not a framework — a function that owns
   `timeout`/`event`/resize/teardown and dispatches to caller-supplied render and
   key callbacks, with the application retaining full control of state and
   timing. Delete ~40 lines from each recipe and make the twenty-line
   "hello world" possible.

6. **Fix the list/viewport circularity.** Separate "compute scroll offset for
   this rectangle and state" from "draw". Remove the stale-`visible` hazard.

7. **Restructure the documentation.** Cut the README to roughly 200 lines —
   what it is, install, a twenty-line example, and links. Move the API reference
   out (the `.yo` manual already is one). Archive `roadmap.md`,
   `implementation-plan.md` and the historical half of `design.md` into
   `docs/history/` and unlink them from the README. Keep `scope.md` prominent.

8. **Add CI.** Build against the pinned Zsh release and run the PTY suite on
   every commit; add a second job on macOS or a BSD to convert "unverified" into
   a fact, in either direction.

9. **Finish the image sweep.** Remove the empty `image-captures/` directory and
   the stray `image.png`; excise the removed/cancelled sections from
   `implementation-plan.md` when it is archived.

10. **Consider splitting `zdraw.c`.** Grapheme handling, SGR parsing, input
    protocol negotiation and resource accounting are separable. If the upstream
    contribution path matters, reviewability matters more than matching
    upstream's single-file shape.

11. **Reconsider whether the inline ZLE picker belongs here.** It is a good idea
    in the wrong repository. Splitting it out would shrink the surface, the test
    suite and the documentation set in one move.

## What to protect

Whatever else changes, do not regress these:

- The capability-evidence model and its `unknown`-is-not-`no` discipline.
- The portability matrix's refusal to infer untested results.
- The non-invasive build and the upstream patch export.
- The PTY test suite and visual regression fixtures.
- `docs/scope.md` and the standard it sets for admitting new work.
