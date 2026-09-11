# zdraw second opinion: the good, the bad and the ugly

Assessed on 2026-09-11 at commit `00e8fac`. This review starts from the premise
that `zdraw` is a `zsh/zcurses` derivative whose purpose is to make TUI
applications easier to write in and for Zsh. It also accounts for the earlier
evaluation and the maintenance response; it does not repeat pre-maintenance
claims as current facts. No implementation code was changed for this review.

## Verdict

`zdraw` is now a credible terminal primitive layer and a useful component
library, not merely an experimental fork. The native module solves problems that
interpreted Zsh cannot solve efficiently or safely: cell geometry, styled row
batching, retained surfaces, structured input, terminal handoff and explicit
presentation. The recent maintenance pass also addressed several real product
defects: licensing, README focus, Linux CI, table batching, component
diagnostics, selection-state preservation and curses screen lifecycle.

The remaining problem is not technical competence. It is the gap between
laboratory quality and usable, distributable product. `zdraw` has excellent
evidence and correctness infrastructure, but an application author still faces
a from-source Zsh build, no version contract, no completion, substantial event
loop boilerplate, no cross-component focus or hit-testing helper, and incomplete
diagnostics in parts of the library. At the same time, the project carries a
very broad supported-looking surface for a toolkit with no consumers outside
its own examples.

The best next phase is therefore not another feature family. It is compatibility,
distribution, ergonomics and reviewability work on what already exists.

### Current shape

| Area | Current size or result | Assessment |
| --- | ---: | --- |
| `Src/Modules/zdraw.c` | 5,974 lines, 58 subcommands | Strong but difficult to review as one unit |
| Upstream `curses.c` | 1,835 lines | `zdraw` is more than three times the baseline |
| Generated Unicode table | 1,682 lines | Correct and bounded, but permanent maintenance |
| Zsh module manual | 1,660 lines | Thorough, but duplicated by a 1,369-line guide |
| Companion libraries | about 2,668 lines, 46 public functions | Useful core, broad optional tail |
| Current documentation | about 6,842 lines outside `docs/history/` | Too much repetition for the supported surface |
| Historical documentation | 1,468 lines | Properly archived, but still large |
| Tests | 131 tests, about 9,934 lines of test code | Excellent breadth and realism |
| Linux CI | pinned Zsh 5.9.2 and full suite | Good, but only one platform |

## The Good

### 1. The native boundary is mostly right

The important additions generally belong in C:

- `spans` and `spansclip` remove per-segment shell calls while preserving
  cursor, style and clipping semantics.
- `prepare`, `draw`, `rowinfo` and `unprepare` provide explicit immutable row
  reuse with session budgets, rather than an implicit cache with unclear
  invalidation.
- `textinfo`, `textpos` and `textwrap` solve width, byte offset and wrapping
  problems that are easy to get wrong in shell code.
- pads, viewport staging and `present` provide a real retained composition
  model without taking over the application event loop.
- `geometry`, `event`, `inputinfo`, `suspend` and `resume` remove common uses
  of external commands or unsafe terminal ownership assumptions.

This is not padding around `zcurses`. Most of the native surface addresses work
that shell code cannot do cheaply or correctly.

### 2. Ownership and safety are taken seriously

The strongest architectural property is explicit ownership. Bracketed paste,
focus reporting, kitty keyboard input, synchronized output and capability
queries are opt-in. They use the curses input owner rather than a competing
reader, and they document cleanup on `end`, suspend and module unload. Raw-mode
consequences such as Ctrl-C becoming input are stated instead of hidden.

The shell layer is also disciplined. Component text is data, not evaluated Zsh.
Loaders are passive and disable aliases while parsing. Public outputs are
ordinary caller-owned parameters. Input and paste limits are bounded. The SGR
decoder filters unsupported terminal commands rather than forwarding active
escape sequences to drawing.

### 3. The inherited contract is respected

The project keeps stock `zsh/curses` separate, exposes inherited operations under
a distinct `zdraw` builtin, and documents migration without pretending that a
module built for one Zsh configuration is universal. The public-source build
does not overwrite the supplied Zsh tree, installed modules or the user's shell.
This is the right relationship to the upstream module.

### 4. Evidence quality is unusually high

The benchmarks distinguish retained-cell drawing from terminal paint, use real
PTYs, warmups and recorded samples, and do not generalize one workload into a
universal speed claim. The capability model distinguishes compiled support,
terminal evidence, application overrides and enabled state, and treats unknown
as unknown. The portability records distinguish tested configurations from
untested ones.

The test suite is similarly serious. It exercises PTY input, resize, narrow
layouts, lifecycle, reload, interrupted sessions, alternate compiled feature
sets, Unicode boundaries, visual fixtures and terminal restoration. The recent
CI `--as-needed` failure was a useful catch, and the screen ownership fix is
covered by tests for reload, failed initialization and a pre-existing inactive
curses screen.

### 5. The recent maintenance response is real

The response to the first evaluation was not cosmetic. Licensing is now clear,
the README is a useful entry point, the table renderer batches each row through
one native `spans` call, selection associations preserve application-owned
fields, diagnostics have a safe opt-in sink, and Linux CI runs the full suite.
The measured table improvement from 16.18 ms to 6.90 ms per draw, with matching
cell snapshots, is credible evidence that the fix addressed the claimed problem.

## The Bad

### 1. The adoption path is still the largest barrier

Building a matching Zsh from source is the technically correct development
path, but it is not a product path. A prospective application author must obtain
and verify Zsh sources, regenerate configuration, build the shell and module,
and then use a checkout-specific shell and `module_path`.

The project also lacks a version and compatibility contract. `zdraw_features`
is useful for compiled capability discovery, but both the guide and manual state
that it is not an ABI identifier. An application can probe whether a feature
name exists, but has no versioned statement about feature semantics or supported
compatibility ranges.

There is no completion for the 58 subcommands or the 46 public component
functions, no packaged launcher for a matching shell and no distribution
guidance beyond building from source. The missing pieces are all Zsh-native
conveniences, not framework features.

### 2. The component API still requires too much ceremony

Return-by-`reply` and caller-owned associations are idiomatic Zsh and are not
inherently bad. The problem is breadth. A nontrivial application must know many
exact dynamic-scope names: `reply`, theme, style, layout, list, table, headers,
tracks, alignments, form, input, document, chart, canvas, motion, error and
others. Function-local parameters make this manageable, but the setup cost is
visible in every recipe.

The event loop is the larger ergonomic cost. Each recipe repeats terminal
initialization, color-profile selection, timeout policy, dirty tracking,
resize handling, key decoding, state updates, rendering and `always` cleanup.
This is defensible policy ownership, but policy ownership does not require every
application to copy the same operational boilerplate.

Cross-component interaction is also missing above individual components. A form
can move focus among its own fields, but an application with a list, table,
sidebar and detail pane still invents its own focus model. Mouse events and
`textpos` exist, yet no list, table or tab component exposes a geometry-to-item
mapping. There are no default, overridable keymaps. These are the routine parts
of a TUI toolkit.

### 3. Diagnostics are improved but incomplete

The new diagnostic helper is well designed: it is opt-in, caller-owned, does not
open files or evaluate the descriptor, cannot turn a logging failure into an API
failure, and preserves status codes. It covers themes, styles, labels, panels,
layout, lists and tables.

It does not yet cover the remaining component families consistently. In
particular, input, form, document and presentation helpers still contain many
bare validation returns. Their documented status distinctions are sometimes
important, but a missing association, invalid action, bad rule and native
failure are still hard to distinguish without reading source. This is a smaller
problem than before, but it remains the highest-friction part of component
development.

### 4. The C implementation is hard to review as one artifact

`zdraw.c` now combines inherited curses operations, wide-character drawing,
grapheme policy, SGR and protocol parsing, resource accounting, snapshots,
pads, presentation and lifecycle in one 5,974-line translation unit. The code
is disciplined and tested, but the shape works against two stated goals:

- a contributor or reviewer cannot easily hold the state model in their head;
- an upstream Zsh maintainer cannot review the whole module as one patch.

Splitting files should not be a line-count exercise, and preserving a diffable
relationship to upstream has value. But the current monolith needs a concrete
reviewability plan: separate subsystems where boundaries are real, retain
upstream-named inherited code where it aids comparison, and stage upstream
submissions as independently justified patches.

### 5. Documentation is better organized but still duplicated

The README fix was correct. The remaining documentation set is still too large
and repetitive. The 1,660-line `.yo` manual is the authoritative API reference,
while `docs/native-api.md` repeats nearly the same contract in 1,369 lines.
Feature guides, research notes, milestone records and evaluation reports all
sit at the same level as product documentation.

Individually the documents are clear. Collectively they create a synchronization
burden: every contract change must be reflected in the manual, guide, component
guide, examples and tests. The project needs a smaller set of task-oriented
guides plus one canonical reference.

### 6. Portability evidence is honest but narrow

Linux CI is valuable, and the NetBSD curses probe is good primitive-level
evidence. Still, BSD and macOS remain unverified, alternative curses builds are
not fully integrated, and the real terminal matrix is a dated manual
investigation rather than automated CI. The project is right not to claim
untested support; it now needs actual second-platform results.

### 7. There is no external product validation

The examples and recipes are much better than bare feature demos, but all
consumers are still in this repository. No external application has yet proved
that the component contracts survive real data models, weird terminal sizes,
user preferences and maintenance over time. Passing tests establishes the
contract; it does not establish that the contract is the right product surface.

Accessibility is a related gap. Optional motion and reduced-motion support are
good, but there is no screen-reader or plain-output story beyond research
discussion. A TUI toolkit should at least document what it does and does not
provide, and recipes should show an application-level fallback where the task
permits one.

## The Ugly

### 1. The upstream checksum manifest is now wrong

The recorded upstream sources match the public Zsh 5.9.2 files, but
`upstream/SHA256SUMS` still checksums the root `LICENCE` as though it were the
unmodified upstream file. The root licence was intentionally amended with
zdraw-specific terms, so:

```sh
sha256sum -c upstream/SHA256SUMS
```

now fails on `LICENCE`. This is not a licensing ambiguity; the governing terms
are clear. It is a provenance defect. The manifest should cover only immutable
files under `upstream/`, or the unmodified upstream licence should be preserved
separately and checksummed there.

### 2. The upstream contribution path is a monolith

`make patch` is useful for building this project's integrated Zsh tree, but it
adds the complete module, generated Unicode data and a very large manual in one
change. That is not a realistic upstream feature submission. If adaptation to
official Zsh remains a goal, the project needs a patch taxonomy: inherited
compatibility, small standalone drawing improvements, text measurement,
structured input, optional protocols and so on. Each slice needs its own tests,
portability statement and stopping point.

### 3. Optional breadth is disguised as one support level

The scope stop is correct, but stopping expansion does not shrink the existing
surface. The project still carries:

- a 346-line character canvas and several chart components;
- optional motion helpers;
- an inline ZLE picker;
- replay and screen restoration tooling;
- sophisticated terminal protocol negotiation;
- generated Unicode grapheme data.

Some of this is justified. Charts and bounded canvases are explicitly in scope,
motion improves visual feedback, and grapheme boundaries are necessary for
correct editing. The problem is presentation and expectation: everything looks
equally supported, while the core path to a form, list, table or responsive
multi-pane application still has gaps. Support tiers would clarify maintenance
without deleting existing consumers' contracts.

### 4. The project documents more surface than it has consumers

This is the same disease in three layers: broad native commands, broad optional
components and broad documentation. Each individual decision has a rationale.
Together they create a maintenance liability before an external application has
validated the priorities. The scope document's admission bar should now apply
retroactively to communication: label what is core, optional, development-only
or experimental.

## Where It Does More Than Necessary

1. **Protocol sophistication exceeds current consumer demand.** The four-axis
   capability model, explicit DECRQM lifecycle and kitty subset are excellent
   engineering, but only a few repository examples consume them. Keep the
   ownership model; stop broadening the protocol surface until an application
   needs a specific missing behavior.

2. **The inline ZLE picker is a separate product.** It is well tested, but it
   concerns ZLE ownership, inline presentation and asynchronous choice, not the
   full-screen text-and-cell toolkit. It should be explicitly experimental or
   separated rather than presented as a normal toolkit component.

3. **Charts, bars, sparklines and canvas form a large visual tail.** They are
   bounded and in scope, but they currently outweigh interaction ergonomics in
   attention and documentation. Freeze them rather than grow them.

4. **Replay and restoration are development tools first.** They are valuable,
   but their product-level documentation and feature vocabulary are larger than
   their current role justifies.

5. **The generated Unicode 17 table is a permanent dependency.** Grapheme-aware
   editing justifies it, but every Unicode revision now has a cost. The data and
   test policy are good; the feature should remain opt-in and narrowly scoped.

6. **The native command count is near the limit of a single builtin.**
   Fifty-eight subcommands are individually defensible, but without completion
   and support tiers they create a manual-lookup experience rather than a
   discoverable Zsh API.

## Where It Does Less Than Necessary

1. **Compatibility and versioning.** Define a `zdraw` version parameter or
   equivalent read-only contract, state which feature names are stable, and
   explain how semantic changes are surfaced. Do not overload `zdraw_features`
   into an ABI claim.

2. **Distribution.** Provide a reproducible bootstrap or launcher that verifies
   and builds the matching Zsh in a cache, then starts an application with the
   correct shell and `module_path`. Also document how a distribution or Zsh
   packager would build the module. This must not pretend that a universal
   loadable binary exists.

3. **Zsh completion.** Add completion for native subcommands and public
   component functions. This is one of the cheapest high-value improvements for
   a project whose target users are Zsh developers.

4. **Uniform diagnostics.** Finish the diagnostic migration across input, form,
   document and presentation helpers without erasing documented status
   distinctions.

5. **Geometry and state reconciliation.** Provide a pure way to compute the
   current viewport and resulting scroll state before navigation and drawing.
   The recipes are correct after the recent fixes, but they still make the
   application coordinate render-time geometry with event-time state.

6. **Interaction mappings.** Lists, tables and tabs should expose bounded
   geometry-to-item helpers and optional default keymaps. Mouse events and
   `textpos` already exist; the missing work is the small pure mapping above
   them.

7. **Cross-component focus.** A small application-owned focus list or helper
   would remove repeated `view` and `tab` special cases without becoming a
   widget tree.

8. **A bounded loop helper.** A helper that owns init/end, timeout, resize
   reconciliation and dirty-frame dispatch, while the application supplies
   render and event callbacks, would remove the largest repeated boilerplate.
   It must remain policy-neutral and should be admitted only after a concrete
   recipe pilot, because it is close to the scope boundary.

9. **Accessibility guidance.** Document the accessibility model, limits and an
   application-level plain-output pattern. Do not claim screen-reader support
   without testing it.

10. **Second-platform CI.** Convert at least one BSD or macOS claim into a
    tested result, in either direction.

## Recommendations

1. **Fix the provenance manifest now.** Remove the modified root `LICENCE` from
   `upstream/SHA256SUMS`, or preserve and checksum the unmodified upstream
   licence separately.

2. **Define compatibility and a real distribution path.** Version the API,
   document stable feature names, provide a matching-shell launcher or
   bootstrap, and explain packager integration without overclaiming ABI
   portability.

3. **Finish diagnostics and geometry reconciliation.** These are existing-surface
   usability and defect work, fully allowed by the stop line.

4. **Add Zsh completion.** Prioritize the native command table and the component
   functions used by the recipes.

5. **Introduce support tiers.** Separate core primitives, core components,
   optional components and experiments. Keep existing contracts, but stop
   presenting every feature as equally central.

6. **Consolidate documentation.** Make the `.yo` manual the single full native
   reference. Reduce `docs/native-api.md` to task-oriented examples, and move
   evaluations and research records out of the main product path after they have
   been acted on.

7. **Pilot two or three real applications.** Use them to decide default keymaps,
   hit testing, cross-component focus and whether a loop helper is justified.
   These should be small, bounded decisions, not a new framework.

8. **Plan C reviewability.** Split only where a real subsystem boundary exists,
   and prepare staged upstream patches rather than one giant additive module.

9. **Add a second platform to CI.** Start with one concrete target and record
   the actual result.

10. **Freeze the optional tail.** Do not expand canvas, charts, inline picking,
    motion or protocol families until an external application demonstrates a
    specific defect or missing outcome.

## What To Protect

- The `unknown`-is-not-`no` capability model.
- The non-invasive public-source build and preserved upstream files.
- The separation from stock `zsh/curses`.
- Explicit terminal input ownership and cleanup.
- Bounded text, paste and resource contracts.
- The PTY, resize, lifecycle, Unicode and visual regression tests.
- The scope document's requirement that passing tests is not enough to prove a
  feature is worth shipping.

## Verification

The complete suite was run with:

```sh
export ZSH_BUILD_ROOT="$PWD/.build/sources/zsh-5.9.2"
export ZSH_TEST_SHELL="$PWD/.build/zsh/Src/zsh"
make test
```

Result: 131 tests passed in 242.009 seconds. The log is
`.build/second-opinion-make-test.log`. The upstream source files match the
public Zsh 5.9.2 copies, but `sha256sum -c upstream/SHA256SUMS` fails on the
intentionally modified root `LICENCE`, as noted above.
