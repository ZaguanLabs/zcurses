# Customizable tables

`lib/zdraw-table.zsh` adds a table renderer and a pure selection/scrolling update
function. It uses the existing theme, utility and layout contracts. The
[table/inspector recipe](recipes/table-inspector.md) is a complete application
showing responsive columns, row selection and an accompanying detail pane.

## Data and columns

Load the library and declare caller-owned column arrays and state:

```zsh
source ./lib/zdraw-table.zsh
typeset -A zdraw_ui_theme zdraw_ui_table
typeset -a zdraw_ui_headers=(Project Jobs Status)
typeset -a zdraw_ui_tracks=(flex=1 fixed=4 fixed=12)
typeset -a zdraw_ui_alignments=(left right left)
typeset -a cells=(
  Atlas         12 'In progress'
  'Field notes'  4 Draft
  'Night shift'  8 Ready
)

zdraw-ui-theme dark 16 || return
# Inside an initialized session, with at least 8 rows and 60 columns:
# The first of eight rows is the header, leaving seven visible data rows.
zdraw-table-update 3 7 keep || return
zdraw-table stdscr 0 0 8 60 focus gap=2 -- "${cells[@]}" || return
zdraw refresh stdscr
```

Every array entry is one cell. Rows follow one another in row-major order: all
cells of row one, then all cells of row two. There is no delimiter inside a cell
and no parsing of display strings. Spaces, empty strings, leading hyphens and
wildcards remain data. The number of cell arguments must be a multiple of the
column count; missing cells are errors, not implicitly padded rows.

| Caller parameter | Contract |
| --- | --- |
| `zdraw_ui_headers` | Required array of 1–32 header strings; its length defines the column count. |
| `zdraw_ui_tracks` | Required array with the same length, using `fixed=N` or `flex=N`. |
| `zdraw_ui_alignments` | Optional array with the same length: `left`, `center`, `right` or `inherit` for each column. When unset, every column inherits the resolved `align` utility. |
| `zdraw_ui_table` | Association containing the one-based `selected` and `first` row indexes. |
| `zdraw_ui_theme` | Theme association, as for panels and lists. |

The renderer only reads these parameters, so read-only inputs are allowed. The
update function needs an ordinary writable state association. All parameters can
be local in the application's enclosing function.

## Drawing and navigation

```text
zdraw-table-update count visible-data-rows keep|up|down|home|end|page-up|page-down
zdraw-table window row column height width focus|inactive|disabled \
  [utility ...] [gap=N] [header=on|off] [empty-text=text] -- [cell ...]
```

The update function shares the list's clamping and scrolling behavior. It
atomically replaces `selected` and `first`, dropping extra state fields. It
does not modify `zdraw_ui_list`. An empty table has `selected=0 first=1`.
Call `keep` after data or geometry changes, with the number of **data** rows that
fit. With the default header enabled, subtract one from the allocated height,
clamping at zero. With `header=off`, all allocated rows can hold data.

The renderer keeps the header in the first row and displays data starting at
`first`. A `> ` marker reserves two columns at the left; selected rows also use
the theme's selection colors. In a rectangle narrower than two columns, the
marker area is clamped to the available width. Column tracks divide the remaining
width using the [layout helper rules](ui-toolkit.md#layout-with-rectangles).

`gap` is the number of blank columns between cells, default 1 and range 0–16.
Fixed columns do not shrink. A valid column layout that cannot fit returns two
before painting, leaving retained cells unchanged. An application can omit a
column, change widths, or choose another presentation. Flexible columns can
receive zero width; their cells are then omitted safely.

Cells occupy one row and clip at complete native text units. Alignment applies
independently to each cell, including headers. `px` adds padding on each side
inside a column's allocated width. A table rejects borders and nonzero `py`;
compose it inside a panel for a frame and outer padding.

No rendering call reads input or changes selection. Applications map keys to
update actions and decide when inactive or disabled tables accept interaction.
Sorting, filtering, stable row IDs, editable cells and multi-row cells remain
application concerns. Preserving selection by identity after reordering requires
mapping that identity to its new row index before normalization.

## Style individual parts

Tables add the shared `header` and `alternate` state tags. Alternation follows
even, one-based source row indexes, so scrolling keeps each row's stripe stable.
Default styles are:

| Part | Defaults |
| --- | --- |
| Ordinary row | `fg=text bg=surface`. |
| Alternate row | `alternate:bg=canvas`. |
| Header | `header:fg=accent header:bold`. |
| Selected row | `selected:bg=selection selected:fg=on-selection selected:bold`. |
| Inactive selection | `selected+inactive:bg=inactive selected+inactive:fg=on-inactive`. |
| Disabled content | `disabled:bg=surface disabled:fg=muted disabled:no-bold disabled:no-reverse`. |
| Empty message | `empty:fg=muted`, text `No rows`. |

Monochrome adds `selected:reverse`. A selected row keeps its marker when inactive
or disabled. Headers and row backgrounds span the complete table width, including
gaps and trailing space. The empty message styles the first data row; a
header-only rectangle has no room for that message.

```zsh
typeset -a table_style=(
  header:fg=text header:bg=canvas header:underline
  alternate:bg=surface
  selected:bg=4 selected:fg=7
)
zdraw-table stdscr 0 0 8 60 focus "${table_style[@]}" -- "${cells[@]}"
```

The existing two-pass utility ordering applies: unconditional properties first,
then matching conditions in argument order, with component defaults before
caller utilities. A selected even row has both `selected` and `alternate` tags.
For example, an instance's `alternate:bg=surface` can override the default
selected background on even rows; put an explicit `selected:bg=...` afterward,
as above, when selection should win. Combined conditions do not gain automatic
specificity. A column alignment other than `inherit` takes precedence over the
resolved `align` utility for that column.

## Validation and ownership

The passive loader includes common styling, layout and selection helpers. It
does not load panel or list renderers, initialize curses, read input or enable
protocols. The shared selection helper also defines `zdraw-list-update`.

Every header and cell is validated before clearing retained content, including
hidden headers and offscreen rows. Native `textinfo` rules apply: no tabs,
newlines, control sequences or leading combining characters. Data is bounded
to 32,767 cells and 262,144 total characters, including headers and the empty
message. Column geometry and all style variants are validated before drawing.
Utility limits include the component defaults.

On success, drawing preserves the window's cursor and current attributes, as
well as the caller's `reply`, `zdraw_ui_layout`, `zdraw_ui_style` and selection
state. It refreshes nothing; present after composing the frame. As with other
components, multiple native drawing calls are not transactional: a native failure
such as color-pair exhaustion can leave partial output. Invalid toolkit arguments
return one; insufficient column space returns two; native failures propagate.
