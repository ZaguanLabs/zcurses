# Compact charts

Sparklines show a bounded history in one row; bars compare signed values against
a shared zero baseline. Both use the existing theme/utility model and preserve
window cursor, current attributes and application ownership of input/refreshes.
Existing meters remain the component for single-value progress.

```zsh
source ./lib/zdraw-sparkline.zsh
source ./lib/zdraw-bars.zsh
# Each loader includes shared styles and chart data helpers, not the other renderer.
typeset -A zdraw_ui_theme zdraw_ui_chart
zdraw-ui-theme dark 256
zdraw-chart-series fixed 0 100 -- 10 18 - 32 60 90
# After initializing stdscr:
zdraw-sparkline stdscr 2 4 40 normal palette=auto positive:fg=accent

zdraw-chart-series auto -- -10 -5 0 5 10
zdraw-bars stdscr 4 4 5 40 normal negative:fg=error positive:fg=accent
```

The [task monitor](../examples/task-monitor.zsh) has a History tab (`3`) showing
bounded progress history and per-task gains. `g` switches automatic/ASCII glyphs,
`m` toggles monochrome, and `t` switches theme. Its application-owned sampling is
simulation-step based, not a wall-clock scheduler.

## Numeric data and scale

`zdraw-chart-series auto -- [sample …]` or
`zdraw-chart-series fixed low high -- [sample …]` atomically replaces an ordinary
writable caller-owned `zdraw_ui_chart` association. It accepts at most 4096 samples.
Source `lib/zdraw-chart.zsh` when only data/projection is needed. These helpers
work without loading the native module, initializing a terminal or spawning a
process. Local associations work through Zsh dynamic scope.

Values and fixed bounds are signed decimal integers in **−32767…32767**: an
optional minus sign followed by one to five ASCII digits. Leading zeros are
always decimal and negative zero becomes zero. `-` alone means a missing sample;
it is never silently converted to zero. Empty strings, plus signs, fractions,
exponents, shell expressions and values outside the range are rejected before
arithmetic. Use a documented fixed unit such as milliseconds when fractional
source measurements need conversion; the application owns that conversion.

Automatic scales use the minimum and maximum of all valid samples **including
zero**. Thus `[7,7]` has scale 0…7, `[-7,-7]` has −7…0, and all-zero, all-missing
or empty series use 0…1. This keeps constant series meaningful and bars comparable
to a real zero. Automatic scales can change when the application replaces data;
use fixed bounds for stable comparisons over time.

Fixed bounds must satisfy `low < high`. Values beyond them remain in the source
series and contribute to `below`/`above` counts. Rendering clamps them to the
nearest endpoint and adds a `clipped` state, underlined by default. Both styles
and the numeric source remain available to show that clipping occurred. The
complete supplied series determines the scale, including samples hidden by the
viewport; resizing does not silently change it.

| Association key | Meaning |
| --- | --- |
| `format`, `mode` | `zdraw-chart-1`; `auto` or `fixed`. |
| `count`, `valid`, `missing` | Total, numeric and missing sample counts. |
| `low`, `high` | Effective display domain, always distinct. |
| `data_min`, `data_max` | Actual numeric extrema, or `unknown` without valid samples. |
| `below`, `above` | Counts strictly outside the effective domain. |
| `latest` | Last sample, including `-` if missing; `unknown` for an empty series. |
| `N,value` | One-based sample: canonical integer or `-`. |

Treat the returned association as retained data and rebuild it through the public
helper when samples change. Renderers accept read-only associations and validate
all numeric inputs again, including hidden samples, before drawing.

## Headless projection

Declare a writable array `reply` and call `zdraw-chart-project endpoint` to map
every sample to an integer position from 0 through `endpoint`, inclusive. The
endpoint is a literal decimal integer from 0 through 32767. Missing samples
remain `-`; numeric samples are clamped and then rounded down. Endpoint zero
maps every numeric sample to zero. Invalid input leaves `reply` unchanged.

```zsh
typeset -a reply
zdraw-chart-series fixed -10 10 -- -20 - 0 10
zdraw-chart-project 10
# reply=(0 - 5 10)
```

For a width of W cells, use endpoint W−1; the sparkline uses endpoint 7 for its
eight marker levels. The bounded domain and endpoint keep the intermediate
product within signed 32-bit integer range. No floating-point interpretation,
locale-dependent numeric parsing or arbitrary arithmetic evaluation is used.

## Sparklines

`zdraw-sparkline window y x columns states [options/utilities …]` paints one cell
per sample. If there are more samples than columns, it shows the newest samples.
Otherwise samples start at the left edge and the remaining cells are cleared.
There is no interpolation, resampling or implicit history ownership. A one-column
view shows the latest sample; an empty series clears the row.

Options:

- `palette=auto|ascii|unicode` (default `auto`). The default ASCII ramp is
  `.:-=+*#@`; Unicode uses `▁▂▃▄▅▆▇█`.
- `ramp=TEXT`: exactly eight single-column characters, ordered low to high.
- `missing-char=CHAR`: one single-column character; default `?`.

Levels represent increasing numeric values within the domain, not absolute
magnitudes. Negative values use the `negative` style. A zero value is a real
sample with a ramp marker; missing samples remain visibly distinct.

## Bar comparisons

`zdraw-bars window y x rows columns states [options/utilities …]` draws one sample
per row, showing the first samples that fit. Remaining rows are cleared. The
scale must include zero (`low <= 0 <= high`), including for fixed scales; a
truncated positive-only domain is rejected rather than implying a zero baseline.

The zero axis maps into the available columns. Positive bars extend right of it,
negative bars left; the axis cell itself remains visible. Zero and values too
small to occupy a separate cell show just the axis. Missing samples replace the
axis marker with `?`. A one-column view therefore shows only axis/missing markers.
When a clipped value has no bar cells, the clipped style is applied to the axis
instead. An empty series clears the rectangle without drawing axes.

Options:

- `palette=auto|ascii|unicode`: default bar fill `#` or `█`.
- `fill-char=CHAR` and `negative-char=CHAR`: positive/negative fill. The negative
  fill defaults to the positive fill; sign is also conveyed by direction.
- `axis-char=CHAR`: default `|`.
- `missing-char=CHAR`: default `?`.
- `track-char=CHAR`: default space.

Labels, values, units and scale annotations belong alongside the plot using
labels or other components. The monitor shows how to keep them visible at useful
sizes. Applications choose aggregation or scrolling when more categories exist
than rows; bars never silently reorder data.

## Styles, fallbacks and failure behavior

Parts expose `track`, `positive`, `negative`, `missing`, and (bars only) `axis`.
Out-of-range numeric samples combine `positive`/`negative` with `clipped`, so
`negative+clipped:bold` and `clipped:no-underline` work with the shared resolver.
The caller's states also participate. Defaults use accent for values, error for
negative values, muted for missing samples, and border for the bar axis; override
these roles for domains where a negative value is not an error.

Geometry utilities must stay `border=none`, `px=0`, `py=0`, `align=left`. Compose
charts with panels/layout helpers for borders, titles and padding. Colors and
attributes are customizable independently of marker profiles. Monochrome keeps
sign direction, missing markers and clipped underlining without requiring color.

`auto` selects Unicode only when native text queries accept the default ramp and
report single-column glyphs; otherwise it uses ASCII. This checks the current
module/locale geometry, not actual terminal font appearance. An explicit Unicode
profile returns status 2 if those glyphs are unavailable. Explicit custom markers
must themselves be valid single-column characters; they are never silently
replaced. No capability query or terminal protocol is activated.

Successful calls return 0; invalid arguments/data return 1; native unsupported
operations can return 2. Series/projection failures preserve caller outputs.
Geometry, all sample values, all styles (including invisible variants) and markers
are validated before any painting. Later native drawing failures, such as color
resource exhaustion, can leave a partial paint, as with other toolkit components.
The usual native rectangle/resource limits apply.

Tests cover numeric bounds and injection attempts, fixed/automatic scales,
constant/empty/missing series, projection endpoints, signs, clipping, custom
glyphs, native span chunk boundaries, narrow views, an ASCII-only module build,
monochrome, caller-state preservation, visual baselines and monitor interaction.
