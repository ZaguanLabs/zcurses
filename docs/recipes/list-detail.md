# Responsive list/detail recipe

The [complete example](../../examples/list-detail.zsh) combines layout helpers,
panels, a scrolling list and labels into a small project browser. Copy it as a
starting point, replace its data and styling arrays, and keep the interaction
policy that suits your application.

After building from the repository root:

```sh
.build/zsh/Src/zsh -df examples/list-detail.zsh
```

| Input | Behavior |
| --- | --- |
| Up/Down or `k`/`j` | Select a project; details follow the selection. |
| Home/End, PgUp/PgDn | Jump or scroll through the list. |
| Enter | Switch list/details when only one pane fits. |
| Escape | Return from narrow details to the list; otherwise quit. |
| `t` | Switch dark/light theme. |
| `q` | Quit and restore terminal settings. |

Selection remains caller-owned in `zdraw_ui_list`; it survives resizing and pane
switches. Navigation also works while narrow details are open. The example
retains the last narrow view when expanded, so shrinking again returns to that
view. Terminals smaller than 8 rows or 24 columns show a resize/quit hint.

## Compose the layout

The example caps the application at 104 columns and centers it. A vertical split
reserves two rows each for the header and footer, giving the middle track the
remaining height. At 72 columns or wider, the middle rectangle splits into a
28-column list, a two-column gap, and flexible details. Below that width, the
active pane receives the whole middle rectangle.

```zsh
zdraw-layout-center 0 0 "$rows" "$columns" "$rows" 104 || return
frame=("${reply[@]}")
zdraw-layout-split "${frame[@]}" rows 0 fixed=2 flex=1 fixed=2 || return
zdraw-layout-rect 2 || return
body=("${reply[@]}")

if (( body[4] >= 72 )); then
  zdraw-layout-split "${body[@]}" columns 2 fixed=28 flex=1 || return
  # Extract both tracks before starting any further nested splits.
fi
```

These are choices in the example, not breakpoints imposed by the toolkit. Change
the maximum width, fixed sidebar size, gap or threshold to suit your content.
`flex=1 flex=2` would share space proportionally instead of reserving a fixed
sidebar. See the [layout contracts](../ui-toolkit.md#layout-with-rectangles) for
rounding, empty rectangles and insufficient-space handling.

## Draw into the available space

Each pane uses `zdraw-panel`, whose returned rectangle accounts for the title,
border and padding. The list calls `zdraw-list-update ... keep` with that content
height before drawing. The details pane uses the selected project's heading,
status, owner and summary. Native `textwrap` reflows the summary by terminal
columns when available; the label renderer clips each displayed row safely.
Content below a short pane is omitted. This small example has no detail scroller.

The application clears its canvas before repainting, removing the previous pane
when switching views. It presents once after composing the complete frame and
redraws for handled input or resizing. The libraries neither read input nor
present intermediate drawing.

For a different appearance, change the application's theme or panel utilities:

```zsh
zdraw-ui-theme light 256 accent=25
zdraw-panel stdscr "${detail_frame[@]}" ' Project notes ' normal \
  border=double border-fg=muted px=2 title:fg=accent title:no-bold
```

Changing padding also changes available content dimensions. Use the returned
rectangle instead of assuming that a particular border always leaves the same
space. If padding consumes the entire interior, skip content drawing.

## Adapt the example

The sample arrays are application data, separate from component state. Replace
them with your own values while keeping list labels as quoted array entries.
After changing the data, normalize selection with `zdraw-list-update`; preserve
selection by a stable ID yourself when reordering or filtering items.

The example selects a basic, 256-color or monochrome profile from `colorinfo` and
respects `NO_COLOR`. It enables no additional terminal protocol. Cleanup remains
in the application's `always` block. Run it with the matching built shell and
module, as in the command above.
