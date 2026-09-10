# Styled-span benchmark

Build with the public Zsh source setup in the [repository README](../README.md),
then run from the repository root:

```sh
python3 benchmarks/spans.py --trials 7 --frames 500
```

The driver uses `.build/zsh/Src/zsh` and `.build/modules` in a 24x80 PTY, with
`TERM=xterm-256color` and the C locale. It requires no installed curses module,
external application or additional Python package. It emits JSON measurements.

Each frame draws 20 rows, each containing eight styled segments of eight ASCII
characters. The legacy path uses `move`, then `attr`/`string` for each segment,
and restores the cursor/style after each row. The batch path uses one `spans`
call per row. Both paths use the same colors, text and retained window contents.
Cell-for-cell equivalence is also tested by the ordinary PTY suite.

Every trial uses a fresh shell/curses session, allocates colors and draws 25 warmup
frames before timing. Timings use Zsh's floating-point `SECONDS` parameter. The
backend order alternates between trials. One column per row changes on successive
frames, so the refresh workload is not an unchanged-screen benchmark.

- `draw` times shell calls and retained-window drawing without refresh.
- `refresh` also includes one `zdraw refresh` per frame and draining terminal
  output into the PTY driver. It does not measure a graphical terminal emulator's
  paint latency.
- Byte totals cover the whole session, including initialization, warmup refresh
  and cleanup; these are excluded from timing. The driver captures actual bytes,
  not an estimate from the text length.

A local run on Linux x86-64, AMD Ryzen 9 5950X, Zsh 5.9.2, GCC `-O2`, and wide
ncurses produced the following medians across seven trials of 500 frames:

| Workload | Legacy ms/frame | Spans ms/frame | Speedup | Bytes per session, either path |
| --- | ---: | ---: | ---: | ---: |
| Drawing only | 0.687 | 0.116 | 5.95x | 4,383 |
| Drawing and refresh | 0.747 | 0.169 | 4.43x | 85,221 |

Drawing-only trial ranges were 0.666–0.694 ms for the legacy path and
0.114–0.120 ms for spans. With refresh they were 0.707–0.760 ms and
0.164–0.197 ms respectively. Results depend on the machine and workload; these
numbers describe this fixed ASCII frame, not arbitrary applications or Unicode
text. Batching reduces shell/module calls. It retains curses' existing screen
diff and emitted the same number of terminal bytes in this experiment.

## Prepared-row reuse

Include the prepared backend with:

```sh
python3 benchmarks/spans.py --prepared --trials 7 --frames 500
```

This runs all three backends and preserves the original two-backend default.
The prepared backend constructs two immutable rows before timing, differing in
one character. Each timed frame reuses the appropriate row twenty times. It
produces the same alternating content as the legacy and ordinary-span paths,
including the same warmup result. Preparation cost and memory are outside the
timed interval: this measures repeated reuse, not continually creating new rows.

A local Linux run on 2026-09-09 using Zsh 5.9.2, GCC `-O2`, wide curses and the
same 24x80 ASCII fixture produced these seven-trial medians (500 frames each):

| Workload | Ordinary spans ms/frame | Prepared ms/frame | Speedup over spans | Bytes/session, all three paths |
| --- | ---: | ---: | ---: | ---: |
| Drawing only | 0.126 | 0.054 | 2.32x | 4,383 |
| Drawing and refresh | 0.170 | 0.107 | 1.59x | 85,221 |

The [recorded measurements](prepared-2026-09-09.json) include trial ranges and
the legacy path. These are workload-specific results, not terminal paint times
or promises for arbitrary Unicode and frequently changing content. The prepared
backend skips repeated style parsing/text decoding and allocates no new colors
while drawing; curses still performs the physical-screen diff. Future work
should measure preparation amortization and representative changing workloads
before adding broader drawing batches.


## Rectangle fills

Run the uniform-rectangle comparison with:

```sh
python3 benchmarks/fill.py --trials 7 --frames 500
```

Each frame replaces a 20x64 rectangle with a single styled ASCII tile, alternating
between `X` and `Y`. The backends use twenty ordinary span calls, twenty prepared
row draws, or one `fill`. All use the same style, content, warmup and explicit
refresh schedule. Both prepared rows and their color pair are created before
timing in every backend. Preparation and allocation cost is excluded.

A local Linux run using the matching Zsh 5.9.2 shell, GCC `-O2`, wide curses,
`TERM=xterm-256color` and `LC_ALL=C` gave these seven-trial medians (500 frames):

| Workload | Row spans ms/frame | Prepared rows ms/frame | Fill ms/frame | Fill speedup over spans / prepared | Bytes/session, all backends |
| --- | ---: | ---: | ---: | ---: | ---: |
| Drawing only | 0.101 | 0.052 | 0.021 | 4.87x / 2.54x | 362 |
| Drawing and refresh | 0.153 | 0.102 | 0.073 | 2.08x / 1.39x | 131,100 |

The [recorded results](fill-baseline.json) include ranges. This is a uniform-fill
workload suited to `fill`, not a replacement for multi-style text rows. It measures
shell and curses execution, not terminal paint time. Every backend emitted the
same number of terminal bytes in each scenario. Fill removes shell row loops and
repeated tile/style compilation while retaining curses' normal screen diff.

## Character canvas

Build with the documented public Zsh source release, then run:

```sh
python3 benchmarks/canvas.py --trials 3 --frames 10
```

The benchmark uses the matching staged shell/module in a controlled PTY, a
32-segment integer waveform, and 8×32/16×64 cell grids. ASCII and Braille use the
same occupancy masks. Each trial creates a fresh shell, builds the scene, warms
up three frames and times ten frames using Zsh's floating-point `SECONDS`.
Backend order alternates between trials. Set `ZDRAW_TEST_LOCALE` if `C.UTF-8` is
unavailable. The script requires Unix PTYs and `wait4`.

- `baseline`: scene, loaded functions and an initialized window, without raster
  storage; this supplies a whole-shell memory reference, not a useful draw time.
- `raster`: rebuild the occupancy grid only.
- `cached`: retain the grid and perform row encoding plus native drawing.
- `rebuild`: rasterize, encode and draw each frame.

Drawn frames alternate between two foreground colors. They do not call refresh,
so timings do not measure terminal output transport or emulator paint latency.
Scene construction is outside timing. Peak RSS covers the whole shell, including
setup, scene construction, caches and warmup. On Linux the driver reads `VmHWM`
from `/proc` while the completed child waits for acknowledgement. Other systems
fall back to `wait4`, which may include launch overhead. Neither counter measures
canvas allocations in isolation, and differences between fresh processes include
allocator/library variation. Logical pixels, occupied cells and write attempts
are reported separately.

A local Linux x86-64 run with the matching Zsh 5.9.2 build and wide curses gave
these medians (three trials, ten measured frames each):

| Cells | Profile | Raster ms/frame | Cached draw ms/frame | Rebuild + draw ms/frame | Rebuild peak RSS KiB |
| --- | --- | ---: | ---: | ---: | ---: |
| 8×32 | ASCII | 9.184 | 6.634 | 15.785 | 4932 |
| 8×32 | Braille | 9.348 | 7.464 | 16.634 | 4960 |
| 16×64 | ASCII | 16.800 | 26.319 | 42.875 | 5360 |
| 16×64 | Braille | 15.997 | 28.319 | 45.041 | 5428 |

Baseline whole-shell peak RSS was 4708–4848 KiB across these cases. The smaller
raster contained 79 occupied logical pixels in 39 cells; the larger had 155 pixels
in 83 cells. Both retained 32 source segments. Full trial ranges, platform details
and logical resource counters are in the
[recorded JSON](results/canvas-2026-09-10.json).

These measurements support small plots and caching unchanged geometry. They do
not establish animation performance for arbitrary shapes or large filled scenes.
Cached drawing still validates/encodes cells in Zsh; native prepared rows are an
available separate reuse path, but were not timed in this benchmark. Keep these
results as evidence for the later diagnostics/optimization milestone rather than
moving the rasterizer into C without an application workload that needs it.
