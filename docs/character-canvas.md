# Character canvas

The optional canvas retains points, lines and rectangles in source coordinates,
then rasterizes them into a bounded grid. ASCII, half-block and Braille output
share that grid: changing the marker profile never changes the underlying data.
It is a companion Zsh library using existing native spans, with no new terminal
protocol, background loop or application framework.

```zsh
source ./lib/zdraw-canvas.zsh
typeset -A zdraw_ui_canvas zdraw_ui_canvas_raster zdraw_ui_theme
typeset -a reply
zdraw-ui-theme dark 256
zdraw-canvas-init 0 -100 32 100
zdraw-canvas-add line 0 0 8 100
zdraw-canvas-add line 8 100 24 -100
zdraw-canvas-add line 24 -100 32 0
zdraw-canvas-raster 8 40
zdraw-canvas-rows ascii
# reply contains eight printable rows. No native module is needed for this path.

# With zdraw loaded and a window initialized:
zdraw-canvas-draw stdscr 2 4 normal palette=auto fg=accent
```

Run the [waveform example](../examples/canvas.zsh) with the matching built shell:

```sh
.build/zsh/Src/zsh -df examples/canvas.zsh
```

`g` cycles automatic/Braille, ASCII and block markers; `p` changes lines to
points; `e` toggles empty data; `t` changes theme; `m` toggles monochrome; `q` or
Escape exits. The example keeps a fixed integer waveform and source scale,
labels its axes outside the plot, and caches the raster until size or data changes.
Automatic mode uses ASCII if Braille is unavailable. Explicit block fallback is
an application decision displayed in the example's footer.

## Retained geometry

The caller owns an ordinary writable `zdraw_ui_canvas` association. Function-local
outputs work through Zsh dynamic scope. Loading is passive, and geometry editing
and rasterization need neither the native module nor a terminal.

| Call | Behavior |
| --- | --- |
| `zdraw-canvas-init xmin ymin xmax ymax` | Replace the scene with an empty one and define its inclusive world bounds. |
| `zdraw-canvas-add point x y [set\|erase]` | Add one point operation. |
| `zdraw-canvas-add line x0 y0 x1 y1 [set\|erase]` | Add a segment including its endpoints. |
| `zdraw-canvas-add rect x0 y0 x1 y1 [set\|erase]` | Add a rectangle outline; opposite corners may be reversed. |
| `zdraw-canvas-add fill x0 y0 x1 y1 [set\|erase]` | Add a filled rectangle. |
| `zdraw-canvas-clear` | Remove all operations, retaining world bounds. |

Shape coordinates are **x, y**. This differs from native drawing rectangles,
which use row, column. X increases rightward and Y increases upward. Bounds must
satisfy `xmin < xmax` and `ymin < ymax`. All source coordinates, including
out-of-bounds endpoints, follow the chart data grammar: signed decimal integers
from −32767 through 32767, with one to five digits and an optional minus sign.
Leading zeros are decimal. Fractions, plus signs, expressions and control text
are rejected before arithmetic. Missing samples are not canvas coordinates;
an application should omit them or break a polyline at a gap.

There are at most 256 operations. They are applied in insertion order. `set`
(default) turns covered pixels on; repeated coverage does not duplicate pixels.
`erase` turns covered pixels off, leaving other dots in the same cell intact.
A later `set` can restore erased pixels. All operations share the draw's color
and attributes; this first canvas has no per-shape colors or transparent layer
composition. To change an existing shape, rebuild the bounded scene from
application data, then replace its raster.

The scene format is `zdraw-canvas-1`, with `count`, the four world bounds, and
one-based `N,kind`, `N,x0`, `N,y0`, `N,x1`, `N,y1`, `N,paint` fields. Point
operations store matching endpoints. Treat these as retained data and use the
public functions to change them. Readers validate numeric fields before using
arithmetic, including operations that would be clipped away.

## Rasterization and clipping

Declare a writable association `zdraw_ui_canvas_raster` and call
`zdraw-canvas-raster rows columns`. Each terminal cell contains **two columns by
four rows of logical pixels**, regardless of the output marker profile.

World bounds map to the outermost pixel centers. The maximum Y maps to the top
row; minimum Y maps to the bottom. Continuous coordinates are rounded to the
nearest pixel, with exact half positions toward the increasing pixel index.
The transform independently fits both axes; it does not promise physically
square pixels or an aspect ratio independent of terminal fonts.

Segments are clipped in continuous world space before mapping to pixels, then
rasterized with an integer line algorithm. Endpoints are canonicalized so reversed
segments use the same rounding and tie-breaking. Clipping calculations use
bounded double-precision arithmetic; retained inputs and output indexes stay
integers. The algorithm is not antialiased, and clipping before rounding is not
a promise of equivalence to cropping an arbitrarily larger raster.

Rectangle outlines clip their four original edges independently. An outline
surrounding the whole viewport therefore does not invent a border on the viewport
edge. Filled rectangles clip their area and include the rounded boundary pixels.
Degenerate shapes reduce to lines or points. Completely outside shapes succeed
without setting pixels.

Limits are 1–256 rows, 1–256 columns, and **4096 terminal cells** in total (32768
logical pixels). A rasterization also permits at most **262144 pixel write
attempts**, including repeated coverage and erasure. A large collection of fills
may reach the work limit before either storage limit. Exceeding any limit fails
without replacing the previous raster. These bounds constrain work and storage;
they do not imply a real-time deadline.

| Raster field | Meaning |
| --- | --- |
| `format` | `zdraw-canvas-raster-1`. |
| `rows`, `columns` | Terminal-cell dimensions. |
| `N,mask` | One-based row-major cell occupancy, 0–255. Zero is empty. |
| `pixels` | Number of occupied logical pixels after all operations. |
| `cells` | Number of cells containing at least one occupied pixel. |
| `writes` | Pixel write attempts during compilation, including repeated coverage. |

The occupancy mask follows the dot numbering in the Unicode
[Braille Patterns chart](https://www.unicode.org/charts/PDF/U2800.pdf). From top to
bottom, the left pixel column uses bit values 1, 2, 4, 64; the right uses 8, 16,
32, 128. The grid models graphical occupancy, not linguistic Braille translation.

## Marker profiles and reusable rows

`zdraw-canvas-rows ascii|block|braille|auto [ink-character]` atomically replaces the
caller-owned writable array `reply` with one string per raster row.

- `ascii`: an occupied cell becomes `#`, or the supplied single printable ASCII
  character. Empty cells become spaces. This export works without `zdraw` loaded.
- `block`: occupied pixels in only the upper or lower half become `▀` or `▄`;
  occupancy in both halves becomes `█`. Horizontal subcell detail is discarded.
- `braille`: each nonempty cell maps to its exact eight-dot character. Empty cells
  use ordinary spaces, allowing predictable opaque replacement.
- `auto`: use Braille only when the module/locale text queries accept the required
  glyphs at one column; otherwise use ASCII. It never emits capability queries.

Explicit unsupported Unicode profiles return 2 without assigning rows. Custom
ASCII ink is validated even when another profile is selected. The same raster
can be exported repeatedly in different profiles or reused after a theme change.
Cell-width checks do not establish how well a particular font draws the markers.

Exported rows are ordinary printable strings accepted by `spans`, `spansclip`
and native `prepare`/`draw`. Applications using prepared rows own their names,
locale/style lifetime and `unprepare` cleanup. This offers a path for static
artwork to avoid repeated raster or marker conversion.

## Drawing and lifecycle

`zdraw-canvas-draw window y x states [utilities/options …]` paints the dimensions
of `zdraw_ui_canvas_raster`, using accent foreground and surface background by
default. Options are `palette=auto|ascii|block|braille` and `ink-char=CHAR`.
Shared color, attribute and state utilities apply normally. Geometry utilities
must remain `border=none`, `px=0`, `py=0`, `align=left`; compose with panels and
layout helpers for framing and positioning.

`zdraw-canvas window y x rows columns states [utilities/options …]` is the
convenience path: compile the caller's scene into a local raster and draw it.
It preserves an existing caller-owned raster. For repeated rendering, explicitly
cache a raster and use `zdraw-canvas-draw` instead.

Every row includes its blank cells, so a successful draw **replaces** the target
rectangle, including old artwork. Erasing a pixel in the scene is not transparent
copying of the terminal underneath it. Draws preserve the native cursor and
current attributes, and do not refresh, read input, enable protocols or allocate
named prepared resources. The application owns presentation and cleanup.

Status 0 means success, 1 means invalid input/limits or a native failure, and 2
can indicate an unsupported Unicode profile or native operation. Editing,
rasterization and row-export failures preserve their outputs. Drawing validates
data, styles, marker widths and geometry before painting, but a later native
failure may leave a partially replaced rectangle.

## Verification and measured limits

Tests cover every dot position, collisions, partial erasure, reversed/clipped
segments in multiple directions, rectangle clipping, degenerate shapes, source
preservation on resize, command/pixel budgets, invalid retained data, prepared-row
reuse, unsupported Unicode, monochrome, caller state and real recipe interaction.
Visual fixtures compare all three encodings across dark/light and color/mono.

The [canvas benchmark](../benchmarks/README.md#character-canvas) records raster
compilation, cached drawing and full rebuild costs, plus whole-shell peak memory.
The measured implementation is intended for small diagrams and modest update
rates. Native acceleration remains a later decision based on representative
workloads; this milestone introduces no C changes.
