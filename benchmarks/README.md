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
