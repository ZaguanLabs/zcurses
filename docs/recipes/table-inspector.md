# Table/inspector recipe

The [example](../../examples/table-inspector.zsh) presents projects in a table
with aligned job counts, status labels and a detail pane that follows selection.
It composes the optional table, panel and layout libraries with application-owned
data and input handling.

After building, run from the repository root:

```sh
.build/zsh/Src/zsh -df examples/table-inspector.zsh
```

Use Up/Down or `k`/`j` to select rows, Home/End and PgUp/PgDn to navigate, `t` to
change theme, and `e` to preview an empty dataset. In a narrow terminal, Enter
switches between table and inspector, while Escape returns to the table.
Escape otherwise exits; `q` always exits. Clearing the dataset resets selection;
restoring it selects the first row.

## Choose what remains visible

The application is centered and capped at 124 columns. At 100 columns or wider,
the body splits into a 56-column table, a two-column gap and a flexible inspector.
Below that threshold, the active pane uses the full body rectangle. Selection
survives resizing, and the last narrow view is remembered when widening.

The table normally shows Project, Jobs and Status. If its panel's usable content
is narrower than 42 columns, it shows only Project and Jobs. The inspector still
exposes status, owner and summary. This illustrates an application choosing which
information belongs in its narrow overview; the table renderer itself does not
hide columns automatically.

```zsh
zdraw_ui_headers=(Project Jobs)
zdraw_ui_tracks=(flex=1 fixed=4)
zdraw_ui_alignments=(left right)
if (( content[4] >= 42 )); then
  zdraw_ui_headers+=(Status)
  zdraw_ui_tracks+=(fixed=12)
  zdraw_ui_alignments+=(left)
fi
```

The application builds matching row-major cells from its project arrays. Header
height is deducted before calling `zdraw-table-update`, keeping page movement and
scrolling aligned with the visible data area. Tables can retain their header even
when no data row fits. Below 8 rows or 24 columns, the whole example shows a
resize/quit hint.

## Customize the composition

Change the theme, panel utilities, column tracks or table state utilities in the
example. For example, choose double borders for the inspector or a different
selected-row background without changing navigation:

```zsh
zdraw-table stdscr "${content[@]}" focus gap=2 \
  header:underline selected:bg=4 selected:fg=7 -- "${cells[@]}"
```

Read the [table contract](../ui-table.md) for alignment, state precedence,
fixed/flexible sizing and validation. Both panes use the same theme and are
presented once after drawing. The example selects a supported color profile,
respects `NO_COLOR`, and keeps session cleanup in its `always` block.

The sample supplies static project data. Real applications own fetching,
sorting, filtering and stable row identity. Inspector text reflows by terminal
columns when native wrapping is available and clips to the pane height; this
recipe does not implement a separate detail scroller.
