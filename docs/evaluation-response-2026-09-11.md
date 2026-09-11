# Review response and maintenance checklist

The [external evaluation](evaluation-2026-09-11.md) identifies the right priority:
make the existing toolkit easier to use, diagnose and maintain. The
[scope boundary](scope.md) remains in force. This response distinguishes verified
problems from product proposals; it does not restart either historical roadmap.
Both the original report and the [second opinion](second-opinion-2026-09-11.md)
are preserved unchanged. Their findings describe the commits each report assessed,
not necessarily the current tree.

## Addressed in this maintenance pass

- [x] Resolve licensing with the project owner's decision: original contributions
  use the Zsh licence. Remove the competing GPLv2 file, explain the governing
  terms, add library identifiers and correct the derived C file's title.
  Preserve upstream notices and the separate Unicode data licence.
- [x] Add opt-in diagnostics for themes, styles, labels, panels, layout, lists and
  tables. Report invalid values, missing output parameters and native failures
  through a caller-owned descriptor. Preserve existing status codes and output
  parameters on validation failure. Test absent, valid, closed and malformed sinks.
- [x] Preserve application-owned keys in list/table selection associations.
  Test preservation through navigation, empty data and rejected updates.
- [x] Batch each table header/data row into one native `spans` call, including
  its padding, background and selection marker. Keep per-cell Unicode clipping,
  alignment, offscreen validation and cursor/style preservation.
- [x] Avoid a redundant `textinfo` call for left-aligned shared row drawing;
  `spansclip` already performs the required clipping.
- [x] Reduce the README to an entry point with setup, a small example and task
  links. Move detailed setup and the native API guide out; archive the three
  superseded planning/design documents under `docs/history/` and repair links.
- [x] Add a Linux CI workflow for pushes and pull requests: verified Zsh 5.9.2
  archive, matching built shell and the complete PTY suite. This does not automate
  the graphical terminal matrix or establish macOS/BSD support.

- [x] Fix the first CI failure: release the owned curses SCREEN on end/unload,
  using `newterm`/`delscreen` where available, and restore previous shell terminfo
  state. Reproduce the old color-allocation failure with an `--as-needed` shell;
  test reload capacity, failed initialization, a preloaded terminfo module and
  a pre-existing inactive stock curses screen.

## Second-opinion maintenance pass

The second opinion correctly identifies a provenance regression introduced by the
licence clarification, and confirms the remaining diagnostic gaps. This pass is
bounded to those two outcomes. It introduces no native API or feature family.

- [x] Preserve the original Zsh licence as `upstream/LICENCE`, verified against
  the digest already recorded in the manifest. Make `upstream/SHA256SUMS` cover
  only the immutable baseline files under `upstream/`. Keep the project owner's
  Zsh licence decision and the root declaration intact.
- [x] Add a portable manifest regression check to the ordinary test suite, so a
  later project-licence edit cannot silently break baseline verification again.
- [x] Extend diagnostics across input editing, streaming paste, validation,
  forms, document compilation/reflow/navigation/drawing, tabs, meters, badges
  and help rows. Preserve validation statuses, native failure propagation and
  existing API-specific status mappings.
- [x] Verify absent, enabled, closed and malformed sinks; writable output
  requirements; rejected edit/reflow atomicity; paste drain and cleanup state;
  validation messages; rendering preflight; and injected native failures.
  Do not log input values, paste payloads or document contents.
- [x] Clarify diagnostic coverage and status mappings in the toolkit guide.

The report's broader recommendations are valuable, but accepting a review does
not approve every proposed helper or an indefinite distribution project. The
remaining work below stays subject to the scope boundary and a bounded task.

## Accepted maintenance work still open, in priority order

- [ ] Extend diagnostics to the remaining chart/canvas, motion and screen/fixture
  helpers when working on those existing contracts. Input/form/document and the
  small presentation components are covered by the second-opinion pass.
- [ ] Simplify geometry/state reconciliation in the recipes. Compute the current
  viewport before applying navigation, then draw; cover queued resize/navigation
  events and page-step behavior at narrow sizes. Avoid making renderers own input.
- [ ] Measure unchanged-content workloads before adding caches. Any prepared-row
  reuse needs explicit ownership, bounded storage, theme/width/content invalidation
  and end/reinit cleanup. The current batching fix does not implement that cache.
- [ ] Define compatibility/version and packaging guidance against concrete consumer
  needs. Preserve ABI matching; do not imply a universal loadable module exists.
- [ ] Establish a second platform CI target from actual results, then expand
  coverage. Keep the graphical terminal matrix dated and distinguish it from
  the ordinary PTY suite.

- [ ] Add native-command and recipe-component completion without loading curses
  or initializing a terminal during completion. Check grammar against the command
  table and manual, and exercise completions in a clean matching Zsh.
- [ ] Clarify core, optional and development-tool roles in the documentation.
  Keep shipped contracts and cleanup obligations; describing an existing feature
  as optional must not silently downgrade its compatibility guarantees.
- [ ] Consolidate the native guide into task examples with the `.yo` manual as
  the full reference. Preserve useful links rather than creating another manual.
- [ ] Document accessibility limits and an application-owned plain-output
  pattern, without claiming screen-reader compatibility that has not been tested.
- [ ] Write an upstream patch taxonomy around independently useful fixes and
  tests. `make patch` remains an integrated build export, not a proposed upstream
  submission. Split C files only to serve one of those concrete reviews.

These are maintenance candidates, not an instruction to proceed indefinitely.
A subsequent task should select a bounded outcome and its acceptance checks.

For adoption work, start with an explicit API compatibility policy and packager
requirements, then consider a verified matching-shell bootstrap/launcher. Keep
module ABI matching separate from API versioning. Actual second-platform results
and a bounded external application pilot would provide better prioritization
than another expansion roadmap; none is claimed by this maintenance pass.

## Proposals requiring a separate decision

Default keymaps and hit testing may improve the existing list/table/tab APIs,
but require demonstrated application behavior and a small agreed contract.
Focus management, a dispatch loop, a widget tree and a multiline editor are not
approved by accepting the review. They need the scope document's admission
checks; an event-loop abstraction must not quietly become an application framework.

Splitting the C implementation should serve a concrete review or upstream patch,
not a line-count target. Removing the inline picker, motion, canvas or grapheme
support would change existing consumers' contracts. No such removal is approved
by this review; the image rejection does not extend to them automatically.

## Corrections to the report

- Git does not track empty directories. No image implementation or capture files
  remain tracked. The untracked `image.png` is the owner's test input and remains
  untouched. It is not distributable residue.
- The list/detail recipe reconciles `keep` with the new content height before
  drawing after resize, and exits through cleanup if rendering fails. Its flow
  deserves simplification, but the report's stale visible selection and silent
  dirty-flag failure are not established defects in that recipe.
- Layout's status 2 already propagates through tables. `zdraw-input-check` already
  returns a user-facing validation message; malformed API calls still need better
  diagnostics. Reassigning every status 2 to "does not fit" would break this API.
- The report's "no SPDX identifiers anywhere" claim overlooks Unicode-derived
  tables. Those notices must survive the project's licensing cleanup.
- `overlay` is an already shipped zdraw extension, not an inherited zcurses
  command. Replacing it with a flag would change its public calling contract
  without an established usability benefit; retain the subcommand.

## Validation

The local 20-row, five-column table comparison used the matching Zsh 5.9.2 shell,
`xterm-256color`, a 24x80 PTY, a warm-up draw and five alternating before/after
trials of 50 draws each. The baseline was commit `47273a8`. Median time per draw
fell from 16.18 ms to 6.90 ms (about 2.34x); all final cell snapshots matched.
This measures component drawing, excluding presentation and application work.
It is not a claim about every component or terminal.

Initial maintenance validation: all 128 tests passed using `ZSH_BUILD_ROOT` set to the
selected Zsh 5.9.2 sources and the matching built shell. The README example was
exercised in a PTY through greeting, quit and terminal restoration; local Markdown
file links and anchors passed. Full-suite log: `.build/evaluation-make-test.log`.
The first Ubuntu CI run caught a pre-existing native reload defect: with
`--as-needed`, libtinfo can stay loaded while libncurses unloads, leaving cached
screen state inconsistent with reloaded color globals. The follow-up owns and
releases that screen using the standard lifecycle APIs; libraries without those
APIs retain the previous initialization path. CI explicitly keeps `--as-needed`
so the reload regression remains exercised.

Second-opinion maintenance validation: all 133 tests passed with the selected
Zsh 5.9.2 sources and their matching built shell, including the new diagnostic
and provenance checks. `sha256sum -c upstream/SHA256SUMS` passes for all five
recorded baseline files. Changed Markdown file links and `git diff --check`
also pass. Full-suite log: `.build/second-response-make-test.log`.
