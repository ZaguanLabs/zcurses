# Rendering and resource diagnostics

Use passive queries at application boundaries to inspect live state. Time model
updates, layout/reflow, drawing, staging and presentation separately when deciding
where to optimize. None of these observations measures when an emulator finishes
painting pixels.

```zsh
zmodload zdraw
typeset -A resources
zdraw resourceinfo resources  # Also works before init and after end.
print -r -- "$resources[session]: $resources[prepared_rows] prepared rows"
```

`resourceinfo` advertises `resource_info` in `zdraw_features`. It creates or replaces
an ordinary writable association. Readonly/special parameters, other parameter
types and subscripts fail without replacing the destination. Inspection works
without `TERM` or a controlling terminal and during suspension. It does not read
input, activate protocols, touch or refresh windows, allocate drawing surfaces, or
retry cleanup. The query walks the live window list; its own result allocation
and traversal are outside the reported resource counts.

| Field | Meaning |
| --- | --- |
| `format` | `zdraw-resources-1` |
| `session` | `inactive`, `active`, or `suspended` |
| `windows` | Public non-pad windows, including `stdscr` and shared children |
| `owned_windows` | Independent application windows, excluding `stdscr` |
| `child_windows` | Public shared subwindows, at every depth |
| `window_cells` | Sum of non-pad window areas; shared regions count again |
| `backing_cells` | Sum of non-pad root areas, including `stdscr`, excluding children |
| `pads`, `pad_cells` | Public pad count and total budgeted pad area |
| `private_input_pads` | Live internal one-cell input pad: zero or one |
| `retired_tree_windows` | Non-null old/candidate handles retained after failed tree cleanup; inspection leaves them retained |
| `cached_color_pairs` | Color-pair records cached by the module; see `colorinfo` for allocator limits |
| `prepared_rows`, `prepared_bytes` | Live immutable rows and accounted storage, as in `rowinfo` |
| `prepared_created` | Successful preparations since session start, including subsequently released rows |
| `prepared_draws` | Successful `draw` calls since session start, including empty rows and zero-column draws |
| `counter_limit` | Saturation ceiling for cumulative counters and window totals (`ZLONG_MAX`) |

Call `zdraw rowinfo name association` to inspect a particular row. Its added `draws` field counts successful uses of that row. Failed preparations
and draws do not increment counters; a failed curses write may still have changed
cells. Releasing a row reduces live storage but retains the session's cumulative
counts. `end` clears prepared counters and storage; suspension preserves them.
Unsupported prepared-row builds report zero counts and an `unknown` byte limit.

These are logical counts, not allocator byte estimates or process memory. Root
areas omit curses' internal screen buffers and allocation overhead. A retained
tree can include both independent backing and shared handles; its handle count
cannot be converted to cells or bytes. Prepared bytes include row records, names,
locale names, stored cells and width arrays, but omit hash-table/allocator overhead.
Failed tree retirement may remain visible even after `end` if cleanup keeps failing.

The following fields publish existing limits; optional-operation support must
still be checked in `zdraw_features`. Limits do not promise that curses can satisfy
an allocation, nor impose new bounds on inherited `addwin` behavior.

| Field | Default budget |
| --- | --- |
| `prepared_byte_limit` | 16 MiB across prepared rows, or `unknown` when unsupported |
| `pad_cell_limit` / `pad_total_cell_limit` | 262,144 cells per public pad / 1,048,576 total |
| `pad_dimension_limit` | 32,767 per dimension |
| `resize_cell_limit` / `resize_dimension_limit` | 262,144 cells per old/new window / 32,767 per requested dimension |
| `tree_window_limit` | 64 handles in a reconstructed tree, and at most one bounded retired tree |
| `copy_cell_limit` | 65,536 cells per copy/overlay temporary rectangle |
| `snapshot_cell_limit` / `snapshot_byte_limit` | 65,536 cells / 16 MiB of snapshot key/value strings |

Companion data has separate caller-owned budgets: charts accept 4,096 samples;
canvas accepts 256 operations, 4,096 raster cells, dimensions up to 256 and
262,144 pixel writes per compilation; forms accept 16 fields; documents accept
128 blocks, 65,536 total source bytes and 4,096 compiled lines. Read their existing
state associations (`count`, raster `pixels`/`cells`/`writes`, document
`line_count`) for application-owned logical sizes. These are not native resources.

## Observable timing boundaries

```zsh
# Inside an active session, using a caller-selected window and drawing helper.
typeset -F 9 SECONDS started drawing_elapsed staging_elapsed present_elapsed
started=$SECONDS
render_application || return
drawing_elapsed=$((SECONDS-started))
started=$SECONDS
zdraw stage sample || return
staging_elapsed=$((SECONDS-started))
started=$SECONDS
zdraw present || return
present_elapsed=$((SECONDS-started))
```

Zsh's special floating-point `SECONDS` measures elapsed work at the shell boundary.
The first interval includes shell execution and called native operations; it is
not a C-only profile. `stage` contributes to curses' virtual screen, while
`present` computes and writes terminal updates. Presentation can include transport
backpressure. PTY byte counts measure generated output, not visible paint, perceived
latency or emulator frame rate. Synchronized output changes protocol framing, not
what these clocks can observe. Keep diagnostics outside the intervals being timed.

The [component benchmark and recorded results](../benchmarks/README.md#component-boundaries)
exercise repeated and changing data at two sizes. Final retained-cell hashes and
whole-session output byte counts support before/after comparisons. Performance
numbers are workload-specific observations, not CI timing assertions.
