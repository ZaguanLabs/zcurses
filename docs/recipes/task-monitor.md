# Task-monitor recipe

The [example](../../examples/task-monitor.zsh) combines tabs, badges, meters,
help rows, panels, layouts, a table and compact charts into a small monitor with
Overview, Queue and History views.

After building, run from the repository root:

```sh
.build/zsh/Src/zsh -df examples/task-monitor.zsh
```

This example simulates three tasks; it does not launch commands or inspect
processes. An idle input timeout advances the simulation approximately every
250 ms. Input activity can delay a step, so the simulation is not a wall-clock
scheduler. Completed work stops advancing automatically.

| Control | Action |
| --- | --- |
| Space or `p` | Pause/resume automatic steps. |
| Tab or Left/Right | Cycle Overview, Queue and History. |
| `1`/`2`/`3` | Choose Overview, Queue or History directly. |
| Up/Down or `k`/`j` | Select a row in Queue. |
| `n` | Advance one simulation step, including while paused. |
| `r` | Reset progress while keeping the current pause setting. |
| `t` | Switch dark/light theme. |
| `g` | Switch automatic/ASCII chart glyphs. |
| `m` | Toggle monochrome and the initial color profile. |
| `q` or Escape | Quit and restore terminal settings. |

Overview shows completed-task counts, an overall meter and individual task
meters. The overall percentage is the integer average of task percentages; it
is an illustrative aggregate, not a duration-weighted estimate. Queue shows
task names, percentages and states, omitting the state column when space is tight.
Tabs preserve the application's selected view when resized.

History shows a sparkline of the overall percentage on a fixed 0–100% scale.
The application owns `chart_history`, retaining at most 96 samples; a narrow
sparkline shows the newest samples without rescaling. A bar comparison shows each
task's actual gain in percentage points during the last simulation step on a
fixed 0–3 scale. Finished tasks have zero gain on subsequent steps. Labels and
numeric values accompany the plots; the plots themselves remain reusable.
Reset restores history to one zero sample and clears gains. Short panes omit
secondary chart labels and comparison rows before hiding the sparkline.


The application centers its layout within 112 columns, reserves the heading,
tabs and footer, and gives the remaining height to a panel. A status badge is
shown when at least 44 columns are available. Short overview panes omit lower
task rows; Queue remains available for scrolling. Below 8 rows or 24 columns,
the application displays a quit/resize hint. Help items disappear as whole pairs,
with quit and pause placed first.

## Adapt it to real work

Replace the `progress` arrays and `monitor-step` simulation with application-owned
data updates. Keep terminal input under one owner. For worker pipes and colored
command output, use the existing
[asynchronous integration contracts](../application-integration.md) rather than
adding a second terminal reader inside a component.

The example redraws when data, view, appearance or geometry changes. Paused and
completed sessions continue accepting input without repainting on each timeout.
The application presents once after drawing its frame and owns cleanup through
an `always` block.

See the [presentation component guide](../ui-presentation.md) for styling and
limits. Each piece can be adopted independently. For example, choose different
meter glyphs, change the selected-tab color, or use a badge next to an existing
application's status text without adopting this recipe's event loop.

See [compact charts](../compact-charts.md) for the shared numeric-series, scale,
marker and styling contracts. Sampling remains illustrative: steps can be delayed
by input and should not be labelled as a real-time rate.
