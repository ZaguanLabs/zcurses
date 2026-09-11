# zdraw design direction — guidance for future agents

**Status:** direction agreed with the maintainer, 2026-09-11.
**Audience:** agents and contributors deciding what to build, where it belongs,
and whether it is good enough.

Read this together with [scope.md](scope.md). This document records the intended
design and developer experience. Scope supplies the hard boundaries and the
quality requirements for additions. Approval of this direction is not approval
to execute an old roadmap, implement every idea below, or add new feature
families without a bounded task.

## The objective

Help developers create exceptional, powerful, beautiful terminal interfaces
using Zsh and curses.

Give them independently useful functions and components they can select,
combine, customize and understand. Translate the complexity underneath into
an interface that is pleasant to use and economical to run.

Working promise:

> Choose the pieces, give them your data, establish your design language, and
> retain the freedom to make something recognizably your own.

This is a creative toolkit. Technical capability, correctness and portability
support that purpose. A larger API or a completed checklist is not the outcome.

## The maintainer's two images

### An upside-down funnel

Small, understandable surface at the top; broader implementation detail below.
The developer encounters complexity progressively, when they need control.

```text
                    Developer intent
                 “Show this selectable list”
                            |
                Components and compositions
             Lists, panels, previews, status displays
                            |
             Shared design and interaction contracts
        Themes, styles, states, geometry, clipping, ownership
                            |
                  Drawing and text primitives
          Styled rows, surfaces, measurement, input, presentation
                            |
                    C / curses / terminal
```

- The common path should be short and understandable.
- Defaults should produce an intentional, usable result.
- Advanced control should remain reachable without abandoning the toolkit.
- Developers may enter at different levels. A custom component can use native
  drawing alongside standard components.
- Layers describe responsibilities. Do not create a new subsystem merely to
  make every box in this diagram correspond to code.
- Complexity is managed, not hidden behind an expensive or unpredictable call.
- Internal optimization must preserve the public behavior and ownership rules.

### Discovering what a constrained machine can really do

The maintainer invoked the C64: people discovering unexpectedly impressive
results within a constrained medium.

For zdraw, investigate what cells, characters, colors, emphasis, geometry and
well-timed updates can express. Seek results that exceed ordinary expectations
of a TUI. Push the medium without spending the project fighting it.

- Be visually ambitious. Basic boxes plus a different palette are a starting
  exercise, not the ceiling.
- Invent through composition and the meaningful use of constraints.
- Restraint, clarity and density can be as impressive as a conspicuous effect.
- The maintainer's “3D” exclusion means GPU-rendered graphics. Depth illusions
  and simulated 3D effects made from terminal cells are welcome to explore in
  bounded design studies: for example, shadows, layering and raised surfaces.
  Judge them by legibility, usefulness, cost and fallback behavior. This is not
  authorization for a general 3D engine or a new rendering feature family.
- A surprising result must remain readable, interactive and reusable.
- Effects must earn their space. Shadow thickness and layout spacing are
  separate concerns: a partial-cell glyph can look thinner while still using
  a full layout row. Prefer a restrained default and give developers a compact
  option that actually recovers rows; do not paint over neighboring content.
- Fragile terminal tricks, disproportionate complexity or an impractical
  dependency are costs, not badges of ingenuity.
- Images and scaled text remain outside scope. This analogy does not reopen
  them or imply a multimedia engine.

## Independent pieces, connected through shared contracts

“Module” in this design discussion can mean an optional Zsh library or component;
it does not mean that every element becomes another compiled `.so`.

Each piece should:

- Have one clear purpose and a documented public interface.
- Load only the dependencies needed for that purpose.
- Be useful without adopting a whole application framework.
- Accept caller-owned data and state through an explicit contract.
- Participate in shared styling, geometry and lifecycle conventions.
- Be replaceable or customizable without rewriting adjacent components.
- Expose useful errors at its public boundary.

Connections should come from common contracts, not hidden knowledge of sibling
components or application globals. Loading a companion library remains passive:
define functions without starting a terminal session, reading input or enabling
protocols.

A developer should be able to combine a selection treatment from one design,
a frame treatment from another, and a status display from a third. Those pieces
should look coherent under the developer's chosen theme while keeping their
individual purpose and character.

## Theme, treatment, state and local choice

Keep these concepts distinct:

| Concept | Responsibility |
| --- | --- |
| Theme / design language | Shared semantic colors and, where supported, consistent spacing, density, border and emphasis choices |
| Component treatment | How a component uses that language: a selection rail, inset frame, badge, understated list, prominent progress display |
| Interaction state | Focused, inactive, selected, disabled, empty, invalid, busy; states relevant to that component |
| Instance override | An intentional local variation chosen by the developer |

Theme inheritance should be useful immediately: establish a theme once and the
selected components use it. A component interprets semantic roles according to
its purpose; inheritance should not make everything look identical.

| Shared choice | List interpretation | Meter interpretation |
| --- | --- | --- |
| Accent | Selected-item marker | Completed portion |
| Muted | Secondary description | Remaining track |
| Emphasis | Selected label | Current value |
| Density | Item spacing | Placement and footprint |

Rules for future design work:

- Prefer semantic roles over hard-coded colors scattered through components.
- Keep theme choice and component treatment independently customizable.
- Define which properties are inherited, which are component defaults, and
  which can be overridden locally.
- Make conflicts and combined states predictable and documented. Do not invent
  a new precedence model per component.
- A local override must not accidentally change unrelated instances.
- Theme changes must preserve selection, data and application meaning.
- Preserve meaning in low-color and monochrome treatments; color is not the
  only signal for selection, errors or progress.
- Inheritance does not require a global singleton, a scene tree or a new
  framework. Use the smallest explicit mechanism that supports the task.

**Current implementation versus direction:** the existing toolkit has theme
associations, utilities, component defaults and state/part overrides. Some of the
broader design-language concepts above are targets, not shipped properties.
Consult [ui-toolkit.md](ui-toolkit.md) and the component manuals before using or
documenting an API. Preserve existing contracts; do not silently change their
precedence to match a conceptual diagram.

## Where the work belongs

| Layer | Put here |
| --- | --- |
| Application | Domain data, commands, navigation policy, approvals, asynchronous work and event-loop scheduling |
| Optional Zsh companions | Reusable components, visual treatments, theme composition, layout and bounded interaction helpers |
| Native C module | General drawing, text/cell operations, input and terminal lifecycle primitives where native implementation is justified |
| Development tools | Real-terminal captures, representative measurements, diagnostics and appropriate regression checks |

- Keep Zsh expressive and useful for application and component authors.
- A native module is conventional Zsh infrastructure; compiled code is not
  itself a failure of the design.
- Moving more work into C is not automatically progress. Require evidence that
  it solves a concrete problem and belongs at that boundary.
- Keep the module general-purpose and changes suitable for adaptation to Zsh.
- Keep runtime dependencies modest and builds reproducible. A test/capture tool
  must not quietly become an application runtime requirement.
- Preserve stock-curses behavior and the documented ABI and portability limits.

## Performance is part of ease of use

A convenient API should not demand that developers understand its internals to
avoid obvious repeated work. Equally, convenience must not conceal uncontrolled
allocation, implicit terminal I/O or surprising state changes.

When relevant to an observed workload:

- Measure repeated text measurement, style resolution and document compilation.
- Reuse valid work when inputs are unchanged.
- Limit repainting and reuse existing batching/presentation primitives.
- For retained or cached work, specify invalidation, limits and cleanup.
- Keep input and presentation ownership explicit; components must not steal
  input or publish an unfinished frame.
- Preserve application control of the final presentation boundary.
- Measure complete interactions as well as individual native operations.

Do not add caching infrastructure, a batch API or an event-loop framework on
the strength of this list alone. First demonstrate the problem. Keep cold/setup
costs, repeated costs, memory, terminal output and emulator painting distinct
when reporting results.

## What exceptional means in practice

Evaluate together:

- **Visual identity:** deliberate choices that can make an application its own.
- **Hierarchy:** content, selection, status and available actions are apparent.
- **Composition:** alignment, spacing, density and responsive behavior hold up.
- **Interaction:** navigation, input, scrolling and transitions remain dependable.
- **Craft:** long labels, populated screens, empty states, errors and small
  terminals receive attention equal to the showcase frame.
- **Developer usefulness:** another developer can adopt, restyle and combine it.
- **Practical cost:** implementation, runtime and maintenance remain proportionate.

Do not grade a result more generously because it was written in Zsh. Do not call
it exceptional, faster or superior merely because tests pass or a screenshot
looks promising. Compare relevant alternatives when making those claims and
follow the quality bar in [scope.md](scope.md).

## Working method for bounded design tasks

1. Name the developer task and user-visible experience being improved.
2. Choose a concrete element or composition and a stopping point.
3. Inspect existing primitives and components before proposing new APIs.
4. Explore a small number of substantially different treatments. Palette swaps
   alone do not demonstrate the range of composition.
5. Build runnable prototypes using realistic content and existing APIs first.
6. Inspect actual terminal output; exercise populated, empty, busy/error and
   narrow states as relevant. Check keyboard use, resize and cleanup.
7. Critique the result. Identify whether a shortcoming comes from design, API
   friction, Zsh execution, curses behavior or the terminal.
8. Demonstrate reuse: change the theme, apply a local variation, and combine the
   element with another component. Record what had to be copied or worked around.
9. Measure the relevant workload before proposing lower-level acceleration.
10. Package the successful result with a clear example and the smallest justified
    interface. Record limitations and rejected directions as well as successes.

Use proportionate checks. Do not turn a small visual adjustment into a mandatory
research program or build a generic system before the experiment earns it.

The unit of progress should be a useful, convincing piece developers can use.
An exploratory demo is evidence and a learning tool; it is not automatically a
supported component or proof that a new feature family should ship.

## First customer and current evidence

`zcoder.zsh` is the first real customer. Its review/transcript surfaces, model
pickers, multiline drafts, approvals, streaming input and terminal handoff give
us concrete tasks. Use those tasks to ground decisions, while keeping zdraw's
examples and tests independent of the zcoder repository and any user's machine.

The [first visual study](design-study.md) demonstrates three compositions using
existing APIs. Its real captures and timing record are useful evidence. The
maintainer's subsequent clarification asks for substantially more visual
invention and reusable treatments than that study established.

- Do not treat quiet/workbench/expressive as the final design language.
- Do not make their palettes or layouts mandatory application defaults.
- The [linked-detail prototype](linked-detail.md) now concentrates on one reusable
  treatment: two-line entries, a selection rail, a connecting line and adjustable
  entry spacing. It demonstrates shared themes, local overrides and
  reuse with two datasets. It remains an example for review, not a new supported
  component family or a decision to expand the toolkit.
- Selection rails, connected regions, layered surfaces, readable change gutters
  and compact activity displays are investigation ideas, not an approved backlog.

The maintainer explicitly selected **change gutters** as the next bounded task
after closing the shadow experiment. The [change-gutter prototype](change-gutter.md)
now demonstrates fixed old/new line numbers, compact numbering, explicit `+`/`-`
markers and horizontal text navigation using existing primitives. It accepts
application-supplied review rows and remains an example for visual review.
This approval does not authorize a diff engine or automatic progression to
the remaining investigation ideas above.

### Rejected shadow treatment

The maintainer rejected both the full-cell and adjustable thin/half-cell shadows
on 2026-09-11. They looked poor and would not be used in the maintainer's apps.
Shadow drawing and controls are removed from the linked-detail prototype.
Do not mistake configurability, passing tests or a clever glyph for design quality.
Do not continue tweaking these variants or start an unbounded search for tricks.
Reopening this requires a substantially different technique with a visibly
excellent real-terminal result, within scope, followed by maintainer review.
Until then, keep shadows disabled and work on useful, convincing composition.

## Before choosing the next change

Ask:

- What does the developer gain, and what does their user actually see or feel?
- Can it inherit a theme and still retain its intended character?
- Can it stand alone and also compose with other pieces?
- Is the easy path short? Is advanced control still available?
- Does it work beyond the ideal screenshot?
- Is the complexity in the correct layer, and is its cost justified?
- Is this the bounded task we were asked to do?

If the only gain is another capability, another abstraction or another checked
box, reconsider the work against this direction.
