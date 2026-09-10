# Overlays, shared windows and transparent copying

Applications own stacking order, visibility, clipping and focus. The native
module supplies retained cells and explicit composition operations. Two examples
make that division concrete:

```sh
.build/zsh/Src/zsh -df examples/stacking.zsh
.build/zsh/Src/zsh -df examples/overlays.zsh
# Optionally negotiate synchronized presentation:
.build/zsh/Src/zsh -df examples/overlays.zsh --sync
```

The first uses independent windows and existing `stage`/`present`: Space hides or
shows the upper surface, `r` changes order, and arrows move it. Each frame restores
the background and stages all visible surfaces from bottom to top. Omitting a
surface from the next frame is how this example hides it. Deletion or movement
alone does not erase its previous screen footprint.

This exposes the main limits: applications must remember order, recompose revealed
areas and avoid an ordinary refresh that covers their overlays. Independent window
movement/resizing deliberately rejects shared trees. Staging a window is opaque;
its blank cells cover earlier contributions. Native windows must fit the screen
for geometry changes; clipping belongs to an explicitly selected source region.

The second example adds a shared child view, `treewin`, and `overlay`. Arrows move
a logical floating surface; `+`/`-` resize it, Space hides it, `r` changes order,
`t` toggles transparency, `c` clips it at the screen edge, `w` moves the backing
tree, and `v` moves the child view. `f` attempts invalid geometry and shows the
rejection. It intersects each desired rectangle with the screen before calling
`copy` or `overlay`, then stages `stdscr` and presents once. Native code contains
none of these key bindings or layout decisions.

The richer recipe releases its surfaces when the screen becomes too small and
recreates them from its application state on growth. Curses can alter window
geometry during terminal resize; a previously valid tree is not a promise of
unchanged geometry after arbitrary terminal shrink. Applications can inspect
positions and explicitly repair a valid tree, or rebuild it from their model.

## Shared-tree geometry

```zsh
zdraw addwin frame 8 30 2 4
zdraw addwin body 4 24 4 7 frame
zdraw addwin detail 1 12 5 8 body

# Grow and move the complete backing tree; descendants keep relative offsets.
zdraw treewin frame 10 34 3 6
# Reshape one view using absolute screen coordinates, keeping its descendants.
zdraw treewin body 3 20 5 9
```

`treewin target rows columns row column` rebuilds the target's entire owning tree.
All arguments are literal nonnegative decimal integers; dimensions are positive.
The target can be its independent root or any descendant. The root must be an
owned ordinary window: pads, `stdscr`, and trees rooted in `stdscr` are excluded.
Existing `movewin` and `resizewin` keep their independent-window restrictions.
Inherited `addwin ... parent` continues to create shared views.

Every result must fit the current curses screen. Each child must fit its immediate
parent; descendants retain their relative offsets and dimensions unless they are
the target. There is no automatic child clipping, scaling, reparenting or deletion.
Grow parents before growing children; shrink descendants before shrinking parents.
Moving a parent moves its descendants, while siblings outside the target's subtree
keep their geometry.

Content belongs to the root's backing cells. Root resizing preserves the overlap
and fills newly exposed root cells with its background, following native curses
wide-edge behavior. Shrinking discards cells. Moving or resizing a child selects
a different view into the same parent cells; it does **not** carry the child's old
text to a new location. Child backgrounds remain drawing defaults, not private
backing storage. Writes through a rebuilt grandchild still affect all ancestors.

Each window retains its name, registry position, current attributes/color pair,
background, scroll setting and input timeout. Cursors are clamped independently to
the new dimensions. The module does not expose or promise retention of arbitrary
curses settings outside its API. Geometry changes do not stage, consume input or
present; restore old footprints and recompose explicitly. Native wide-glyph cuts
are not repaired by an independent Unicode layer.

The tree is limited to **64 windows** including its root, with target dimensions at most
32767 and old/new areas at most **262144 cells per window**. Collection is iterative,
not recursive. A private duplicate backs the replacement tree, with new shared
views created parent first. This needs temporary backing and view metadata in
addition to live windows; cell limits are not exact byte/RSS limits.

All validation and replacement construction happen before live handles change.
Invalid geometry, allocation and setup failures leave live geometry/content intact.
Zsh traps are deferred during construction/publication and retirement. After all
replacements are ready, their handles are published together; old views are freed
child first, and a parent is retained while any child remains.

A retirement failure is different: `treewin` returns 1 and warns that the **new
geometry was applied**, keeping coherent live handles and one bounded retired
allocation for cleanup. Another `treewin` retries cleanup before allocating and
refuses another rebuild while it still fails. End/unload make a best-effort cleanup
attempt. A failed cleanup of an unpublished candidate is retained the same way;
live handles remain unchanged in that case. Persistent library deletion errors
cannot guarantee resource reclamation. Applications inspect geometry after a
reported post-publication cleanup failure rather than assuming rollback.

Check `window_trees` in `zdraw_features`. It requires the existing independent
resize APIs plus wide background get/set functions. Status is 0 for complete
success, 1 for invalid state/bounds/resources or a library error, and 2 when the
compiled implementation is unavailable. Initialization is required.

## Transparent regions

```zsh
zdraw overlay source source_row source_column target row column rows columns
```

`overlay` uses `copy`'s strict rectangle bounds and **65536-cell** temporary budget.
It first snapshots the source rectangle, even when names differ, so overlapping
self-copies and aliased subwindows read the original source. It then copies runs
of opaque cells into the destination:

| Stored source cell | Effect |
| --- | --- |
| Space, no attributes, color pair zero, no combining marks | Transparent: preserve the destination cell. |
| Space with an attribute or nonzero color pair | Opaque: copy the styled blank. |
| Non-space background character | Opaque: copy the character and style. |
| Other character, including supported combining data | Opaque: retain native cell data. |

There is no alpha channel, color blending, background substitution or special
transparent character. A nonzero pair remains opaque even if it visually matches
pair zero. Classification uses retained values, not rendered color appearance.
`copy` remains fully opaque, including plain blanks.

With wide cell readers, classification examines the stored character, combining
suffix, attributes and pair. Narrow readers compare the native packed cell to an
unstyled space; this path supports its native narrow character representation and
does not reconstruct wide Unicode data. The operation uses native `copywin` runs;
align source, destination and subwindow edges to complete wide glyphs. Clipped
wide edges inherit library behavior and may leave partial retained glyphs. Neither
portable repair nor identical emulator appearance is promised.

Source/destination cursors, current drawing styles and backgrounds remain intact.
Shared backing changes normally; stage the owning surfaces explicitly so their
change markers are accounted for. No input, refresh or pair allocation occurs.
Validation, temporary allocation and source-copy failures leave the target intact.
A later read or destination-write failure can leave copied runs; there is no
rollback. Temporary cleanup failure returns 1 even if copying completed. Status is
0 on success, 1 for arguments/resources/library failures, and 2 without `copywin`
and `newpad`; check `transparent_copy` for availability.

## Panel-library decision

The curses panel library tracks overlapping opaque windows and their order,
including hide/show and movement. `update_panels` composes its stack for a later
`doupdate`; mixing its windows with ordinary refresh requires discipline.

For these examples, explicit bottom-to-top staging or clipped copying already
produces the required reveal behavior. A second native stack would add window
lifecycle coupling, replacement bookkeeping and another composition owner without
solving transparent-cell copying or shared-tree geometry. **No native panel API is
added in this milestone.** This is a design evaluation against the working examples,
not a benchmark claiming panels are slower.

If future measurements justify automatic damage tracking for many opaque surfaces,
a panel extension can be considered separately. Its update operation would need
one documented place in frame composition, before explicit `present`; ordinary
refresh could not bypass that owner safely. The current path already works with
optional synchronized presentation and keeps modal/focus policy in the application.
See the [ncurses panel manual](https://invisible-island.net/ncurses/man/panel.3x.html)
and [shared-window semantics](https://invisible-island.net/ncurses/man/curs_window.3x.html).

## Verification

PTY fixtures exercise root/child/grandchild sharing, sibling positions, root
expansion, child view movement, cursor/style/timeout retention, resize constraints,
invalid arguments, limits, allocation/setup failures and failed retirement recovery.
Transparent-copy fixtures cover styled blanks, source/background state, aliasing,
opaque fallback, optional/narrow builds, partial writes and aligned/clipped wide
cells. Interactive recipes cover stacking, hide/show and reveal, clipping, geometry
rejection, resize, and terminal cleanup. None of these observations claims panel
performance or universal behavior at split wide-glyph edges.
