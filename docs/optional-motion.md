# Optional activity and transitions

`lib/zdraw-motion.zsh` supplies small, caller-driven motion helpers. It loads
passively, owns no event loop, timer, signal handler or terminal protocol, and
allocates no persistent native object. State management works without loading
`zdraw` or opening a terminal. Rendering uses existing `fill` and `restyle` calls.

Start with the nonanimated version and make movement an explicit choice:

```sh
.build/zsh/Src/zsh -df examples/task-monitor.zsh --no-motion
.build/zsh/Src/zsh -df examples/task-monitor.zsh --motion
.build/zsh/Src/zsh -df examples/task-monitor.zsh --reduced-motion
```

The task monitor defaults to `--no-motion`. `a` cycles on → reduced → off → on;
`--sync` can be combined with any mode. Progress, status words, selected rows and
keyboard controls work in every mode. No desktop preference is guessed: the
application explicitly supplies the user's chosen policy.

## Caller-owned state

```zsh
source ./lib/zdraw-motion.zsh
typeset -A zdraw_ui_motion
zdraw-motion-init activity on

# At a tick owned by the application:
zdraw-motion-action advance
if (( zdraw_ui_motion[changed] )); then
  # Initialized session and caller-owned zdraw_ui_theme required for rendering.
  zdraw-activity stdscr 0 2 normal fg=accent bg=canvas
  # Stage/present within the application's ordinary frame boundary.
fi
```

`zdraw-motion-init activity|settle on|reduced|off` atomically replaces an ordinary
writable `zdraw_ui_motion` association. Use a local association to isolate an
instance; save and restore its key/value entries when managing several instances,
as `monitor-motion` does in the [task-monitor example](../examples/task-monitor.zsh).
No parameter names or callback strings are evaluated.

| Field | Meaning |
| --- | --- |
| `format` | `zdraw-motion-1` |
| `kind` | `activity` or `settle` |
| `mode` | `on`, `reduced`, `off` |
| `phase` | `running`, `paused`, `complete`, `cancelled` |
| `frame` | Activity 0–3; transition 0–2 |
| `visible` | 0 or 1, explicitly controlled by the caller |
| `changed` | 1 if initialization or the last action changed phase, mode, frame or visibility; otherwise 0 |

Each state has exactly seven fields. Updates validate the complete state before
using numeric fields, reject unknown keys/actions and preserve data on failure.
`changed` is an action result, not an automatically acknowledged rendering flag.
Rendering leaves state unchanged. Scheduling neither depends on a clock nor
accumulates elapsed time: one successful `advance` moves at most one frame.

`zdraw-motion-action ACTION` supports:

| Action | Behavior |
| --- | --- |
| `advance` | Advances only visible, running instances in `on` mode. Activity wraps after four frames; transition completes at frame 2. |
| `pause`, `resume` | Freeze a running instance or resume a paused one. Completed/cancelled instances stay stopped. |
| `finish` | Mark complete; activity uses its completed marker, transition selects its base style. |
| `cancel` | Mark cancelled; activity uses its cancellation marker, transition selects its base style. |
| `restart` | Explicitly restart using the current mode and visibility. |
| `hide`, `show` | Freeze hidden instances; showing resumes from the retained frame without catching up. |
| `on`, `reduced`, `off` | Change policy. Reduced/off reset activity to its static marker and immediately complete unfinished transitions, including hidden/paused ones. Re-enabling does not restart a completed/cancelled transition. |

Reduced and off have the same nonanimated output in this version; their distinct
values preserve the caller's policy. A pending activity remains pending rather
than pretending the underlying work has completed. Only finite decoration
completes immediately. Call `finish` when work actually finishes.

## Activity indicator

```text
zdraw-activity window row column states [glyphs=ascii|dots] [utility ...]
```

The indicator owns exactly one column. Defaults are `fg=accent bg=surface` and
ASCII frames `|`, `/`, `-`, `\`. `glyphs=dots` selects four fixed Braille glyphs
(`⠋`, `⠙`, `⠹`, `⠸`); it requires suitable native wide drawing and locale support,
and may return unsupported status instead of silently changing the glyph choice.
The selected glyph must occupy one system column.

Static markers are `*` for pending work in reduced/off mode, `=` for paused work,
`+` for completion and `x` for cancellation. Keep a word such as “Running” or
“Paused” beside the indicator, as the monitor does; motion and color need not
carry the meaning alone. Existing style utilities and variants work normally:

```zsh
zdraw-activity stdscr 0 2 focus glyphs=dots \
  fg=muted focus:fg=accent bg=canvas bold
```

Borders and padding are rejected because this renderer owns one cell. Place the
indicator inside a caller-drawn panel when a surrounding border is desired.

## Finite emphasis transition

```text
zdraw-settle window row column rows columns states [utility ...]
```

Create a `settle` instance, draw meaningful final content first, and call this
renderer with its **uniform base style**. It adds bold at frame 0, underline at
frame 1, then the unmodified caller style at frame 2. Styles already containing
those attributes may make a step visually identical. Caller style variants still
apply. No content is blanked, translated, slid, or delayed until completion.

```zsh
zdraw-motion-init settle on
zdraw-label stdscr 8 2 30 'Saved successfully' normal fg=text bg=surface
zdraw-settle stdscr 8 2 1 30 normal fg=text bg=surface
# Later application ticks: advance, render the current style, then present.
```

Use this for a small status or notification region. Do not pass a heterogeneous
panel and expect each original cell style to be remembered: native `restyle`
replaces the rectangle's style. Pass the intended focus/selection utilities when
the region represents focused content. The helper leaves text and focus coordinates
in place and inherits native cursor/current-style preservation.

A transition covers at most **4,096 cells**, wholly inside its destination. It
requires `region_restyle`; the monitor checks that feature and retains ordinary
content when unavailable. Align edges to complete wide characters and avoid legacy
ACS border cells, following the [native restyle contract](native-api.md#restyling-retained-text).
Borders and padding are rejected here too; the rectangle contains existing text.

## Scheduling, hiding and cleanup

Call `advance` only when the application's own tick arrives. Neither helper reads
keys, polls an FD, sleeps, refreshes, registers hooks or installs signal handlers.
If an action reports no change, it needs no motion-driven redraw. Work/data changes
can still require an application redraw. No calls means no component execution.

Hidden rendering returns success without querying geometry or drawing; after
basic arity/state/kind checks it ignores the remaining render arguments. Hiding
**does not erase the previous location**. The caller repaints exposed background
when moving, hiding, resizing or replacing a region. Recompute geometry after
resize, repaint the base content, then render at the current frame. There is no
retained window handle or stale coordinate inside motion state.

Cancellation and policy changes update data only. To remove an already drawn
transition emphasis while keeping the screen, render its final base style or
repaint that region before presenting. At application exit, cancel instances and
end the native session in the application's cleanup path. No prepared rows,
background jobs or descriptors belong to a motion instance; discarding its
association releases all component-owned state.

The monitor uses its existing 250 ms simulation timeout as its motion tick.
This is not a real-time scheduler: continuous input can delay advancement. The
status footer demonstrates the finite transition on pause/resume, reset and task
completion. Hidden effects freeze. Once work is paused/complete and no visible
transition or protocol query remains, input becomes blocking (`timeout -1`).
Changing the mode does not move Queue selection or the selected tab. Its INT/TERM
traps record interruption, then the loop exits through `always`, cancels both
instances and restores terminal modes; signal exit statuses are 130 and 143.
Applications adapting this example own their signal/handoff policy.

## Resource and verification record

Frame sets are fixed: four activity glyphs and three transition styles. There is
no RGB interpolation, per-frame preparation or growing history. Transition frames
reuse the caller's foreground/background pair and change attributes only. Each
indicator rendering uses one fill; each transition uses one native restyle over
its bounded rectangle. Choosing an unbounded stream of different caller colors
can still grow the shared native color cache; these helpers do not do that.

Tests verify hundreds of deterministic state updates without native calls,
Unicode/ASCII activity markers, static alternatives, invalid-state rejection,
combining/wide text preservation, cursor preservation and base-style restoration.
After warming all transition frames, 100 repetitions allocate **zero additional
color pairs**, in both 256-color and monochrome profiles; prepared-row count stays
zero. PTY tests preserve Queue selection across tiny/full-size layouts and observe
blocking input with **zero additional input calls or presentations for 400 ms**
after a paused transition settles, exceeding the old 250 ms polling interval.
That measures application scheduling behavior, not CPU nanoseconds or emulator
paint latency. INT/TERM tests assert terminal-mode restoration and exit status.

State operations return 0 on success and 1 on invalid inputs. Renderers propagate
native failure/unsupported statuses (1/2). They do not advance state on draw failure.
Native write failures can partially change cells; there is no screen rollback.
Ordinary snapshots and the existing visual fixtures can compare these logical
frames, without implying that terminal fonts render every glyph identically.
