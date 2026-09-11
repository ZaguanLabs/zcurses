# Design-study measurement record

Recorded 2026-09-11 on Linux x86-64, AMD Ryzen 9 5950X, the matching public
Zsh 5.9.2 build and ncurses 6.5. This is one developer machine, not an older-host
or cross-platform result. The [raw record](timings.json) includes every sample,
source/module SHA-256 hashes and the platform string.

| Design | Terminal size | Median redraw | P95 redraw |
| --- | --- | ---: | ---: |
| Quiet | 120x32 | 21.167 ms | 24.578 ms |
| Workbench | 120x32 | 25.506 ms | 28.379 ms |
| Expressive | 120x32 | 21.213 ms | 23.441 ms |
| Quiet | 44x20 | 12.748 ms | 13.760 ms |
| Workbench | 44x20 | 13.034 ms | 14.385 ms |
| Expressive | 44x20 | 12.846 ms | 14.433 ms |

## Workload

Three fresh processes per design and size, four warmup frames and twenty timed
frames per process. At 120x32, selection alternates between the first two
changes. At 44x20, the detail view scrolls down and up. All input goes through a
real PTY to the runnable example. The driver drains terminal output.

The interval starts at `study-render` and ends after native `refresh`, before
the test fixture serializes screen cells. It includes Zsh composition, theme
resolution, document compilation, drawing, curses refresh and the measurement
wrapper's overhead. It excludes input waiting, snapshot serialization, physical
display latency and graphical emulator paint time. P95 is the nearest-rank
95th percentile of the sixty samples, not a bound on worst-case latency.
Designs are measured sequentially; small differences between them should not be
read as an optimization result.

## Interpretation

The example uses a simple complete redraw after a relevant input event. It
recompiles the current small document and redraws its visible rows, without a
prepared-row cache, dirty-region optimization or application model cache. This
is a useful cost for a straightforward implementation, not the maximum speed
available from zdraw. It does not continuously redraw while idle.

The screenshot review establishes that these particular frames were rendered
by xterm. The timing run establishes the producer's cost under a drained PTY.
Neither establishes a sustained interactive frame rate, actual SSH performance,
large-transcript behavior or a comparison with another toolkit.

The first design improvements were prose wrapping, shorter navigation labels,
clearer text hierarchy and adaptive shortcut rows. None required a native change.
If a real application misses its interaction budget, measure that workload and
first investigate repeated document/style work and repaint scope. This study
does not establish a need for a larger C API.

## Reproduce

```sh
python3 benchmarks/design-study.py --trials 3 --frames 20 \
  --output .build/design-study/timings.json
```

Use the matching built shell/module and a UTF-8 locale. The benchmark uses the
repository's PTY test driver and Python's standard library; no graphical desktop,
Ollama instance or zcoder checkout is needed. Run separately from the full test
suite to avoid competing with its compiler workloads.
