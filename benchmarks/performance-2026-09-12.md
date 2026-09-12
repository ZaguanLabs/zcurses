# Performance sweep — 2026-09-12

This sweep optimizes existing native operations and companion libraries.
The baseline is commit `9c599d85a8ecf2bf5c4bdf745ffad2e18902130a`.
Both versions use the same staged Zsh 5.9.2 shell, GCC 15.2.0 `-O2`, wide
ncurses 6.5.20250802, Linux x86-64, and an AMD Ryzen 9 5950X. No compiler
flags, terminal protocols, public commands or width policies were added.

Measurements use fresh shells in drained 24×80 PTYs, `TERM=xterm-256color`
and `LC_ALL=C.UTF-8`. Native trials warm up 25 calls; component trials warm
up two frames. Setup, snapshot export and cleanup are outside the timings.
Each comparison alternates version order and reverses workload order between
trials. Native output comparisons check complete query/cell records and exact
terminal bytes; component comparisons check cell snapshots, exact terminal
bytes and resource counters. These are shell/module and PTY timings, not
terminal-emulator paint latency.

Seven-trial native medians (500 calls per trial, Linux CPU affinity 2):

| Native workload | Before ms/call | After ms/call | Speedup |
| --- | ---: | ---: | ---: |
| 8 KiB ASCII width/clip query | 0.0922 | 0.0418 | 2.21× |
| 8 KiB ASCII position query | 0.1083 | 0.0563 | 1.92× |
| 8 KiB grapheme boundary query | 0.1952 | 0.0971 | 2.01× |
| 8 KiB safe grapheme query | 0.3564 | 0.1149 | 3.10× |
| 8 KiB styled text clipped to 8 columns | 0.1960 | 0.0711 | 2.76× |
| 64-column repeating styled row | 0.0095 | 0.0086 | 1.10× |
| Prepare/release a 64-column row | 0.0103 | 0.0090 | 1.15× |
| 20×64 rectangle fill | 0.0169 | 0.0165 | 1.02× |
| Repeated target lookup among 256 windows | 0.0078 | 0.0056 | 1.41× |

Five-trial component medians (20 frames per trial, unrestricted CPU affinity):

| Component workload | Before ms/frame | After ms/frame | Speedup |
| --- | ---: | ---: | ---: |
| Chart redraw, 16×64 | 4.747 | 3.848 | 1.23× |
| Chart update + redraw, 16×64 | 6.438 | 5.169 | 1.25× |
| Cached canvas, 16×64 | 17.468 | 8.085 | 2.16× |
| Rebuild + draw canvas, 16×64 | 44.251 | 29.624 | 1.49× |
| Form redraw, large | 14.930 | 11.947 | 1.25× |
| Form edit + redraw, large | 15.718 | 12.880 | 1.22× |
| Document reflow + draw, large | 8.080 | 7.631 | 1.06× |

The [recorded samples](results/performance-2026-09-12.json) contain all 18
native and 28 component cases, both timing distributions, stage/present times,
whole-shell peak RSS, result hashes, resource counters and build/source hashes.
Every compared result and terminal byte stream matched; component resource
counters also matched. Native microbenchmarks were pinned to one CPU after
short unpinned trials showed scheduler/frequency noise. To match that Linux
setup, prefix the native benchmark command below with `taskset -c 2`.

The main gains are in decoding, span construction and companion-library work.
Short Unicode calls, distinct-character rows, prepared draws and snapshots
show little or no reliable gain. A longer pinned check of the
short calls separated noise from a redundant recoloring check, which was
removed. Document reflow still rebuilds caller-editable data; skipping that
work based only on width would change its behavior. Curses staging/presentation
and terminal output volume are essentially unchanged. Whole-shell RSS varies
between fresh processes; the native cell cache adds a bounded stack buffer,
and these changes add no persistent text/style/raster cache.

The changes follow measured costs:

- Printable ASCII takes the same one-column result as the existing Zsh decoder
  without repeated multibyte, printability and width calls. ASCII grapheme
  properties skip the generated-table binary search; controls and Unicode still
  use that table and the existing boundary state machine.
- Span compilation retains a bounded 64-entry cache of checked single-scalar
  cells for one invocation. Its key includes scalar, attributes and pair ID.
  Combining groups always undergo their full representability check. Pair-zero
  cells already checked in preflight need no second construction.
- Safe headless queries remember successful round trips for printable ASCII
  bases within that query. A following combining suffix requires its own check.
- Prepared rows that fit use their recorded cell count. Clipped draws still
  walk widths and exclude partial cells.
- Rectangle fills save, neutralize and restore the window's background, style
  and cursor once for the rectangle. Failed moves/writes restore state and keep
  the same already-written prefix of rows.
- Window lookup retains its two most recent entries, accommodating dispatch's
  `stdscr` check followed by the actual target. Reverse-color lookup retains one
  entry. Deletion and session teardown invalidate the pointers. Public window
  order, ownership and color allocation remain unchanged.
- Style resolution validates every utility once, retaining normalized values
  separately for ordinary and conditional precedence. Inactive conditions are
  still validated, and theme mutations are read on every call.
- Canvas mask validation avoids a function/options scope per cell. Occupancy
  counts use bounded eight-bit population counting. Distinct masks map to
  glyphs once; array substitution and row joins replace the per-cell shell
  encoding loop. Backreference parameters and options are localized. Raster
  data remains caller-owned and is fully revalidated on every public call.
- Signed chart-number validation avoids a nested unsigned-parser call while
  retaining its decimal grammar, length and value bounds.

Callgrind collected **50,719,249 → 31,475,572 instructions (37.9% fewer)**
inside `zdraw_compile_spans` and its callees for the existing eight-span ASCII
fixture: 25 warmup frames plus 50 measured frames, 20 rows per frame.
The original profile attributed 20.1% of inclusive instructions to text decoding
and 34.6% to checked cell construction. Instrumented timing is not used for
speedup claims. Zsh function profiles identified per-cell canvas validation,
mask counting/encoding, and twice-parsed style utilities as companion-library
hot paths.

Validation includes the complete `make test` suite, its real optional-backend
builds and injected failures, all 766 pinned Unicode grapheme conformance
cases, and 5,400 deterministic differential text queries across cell, grapheme
and safe policies. The latter compare statuses and complete output associations,
including unchanged destinations on failure. Additional regressions exercise
cell-cache collisions, combining suffixes after cached ASCII, discarded invalid
text, all 256 masks and 95 printable ASCII ink characters, zero-padded/invalid
mask values, style precedence and theme
changes, caller backreference state, window recreation, session reset and module
reload. The cache/lifecycle fixture also passes Valgrind Memcheck with zero
errors; this check disables leak reporting and is not a whole-shell leak audit.

To reproduce against the recorded baseline, first follow the public-source
setup in the repository README. Build both revisions with the same source
release and configuration; loading a different-ABI module is unsupported.
All copies and builds stay under `.build/`:

```sh
zdraw_sources=$(cd .build/sources/zsh-5.9.2 && pwd)
ZSH_BUILD_ROOT="$zdraw_sources" make build
git worktree add --detach .build/perf-baseline 9c599d85a8ecf2bf5c4bdf745ffad2e18902130a
(cd .build/perf-baseline && ZSH_BUILD_ROOT="$zdraw_sources" make build)
python3 benchmarks/native.py --trials 7 --iterations 500 \
  --baseline-modules .build/perf-baseline/.build/modules
python3 benchmarks/components.py --trials 5 --frames 20 \
  --baseline-root .build/perf-baseline
python3 benchmarks/text-differential.py \
  --baseline-modules .build/perf-baseline/.build/modules
ZSH_BUILD_ROOT="$zdraw_sources" make test
```

For native profiling, rebuild the disposable module with symbols, then stage
it separately from the timing build. `--callgrind` requires Valgrind and records
native builtin calls, including setup and final inspection; inspect individual
function costs when separating those from the workload:

```sh
make -C .build/zsh/Src/Modules -W zdraw.c \
  'CFLAGS=-Wall -Wmissing-prototypes -O2 -g' LIBLDFLAGS= zdraw.so
mkdir -p .build/profile-modules
cp .build/zsh/Src/Modules/zdraw.so .build/profile-modules/
python3 benchmarks/native.py --modules .build/profile-modules \
  --trials 1 --iterations 50 --workloads spans clip-long safe-query-long \
  --callgrind .build/callgrind
callgrind_annotate --inclusive=yes .build/callgrind/spans.0
```

For companion-library profiles, stage the matching shell's optional `zprof`
module and run the same component fixture. Profile runs are separate from
unmodified timing runs:

```sh
cp .build/zsh/Src/Modules/zprof.so .build/modules/zsh/
python3 benchmarks/components.py --trials 1 --frames 3 \
  --workloads canvas form document chart --zprof-dir .build/zprof
```

These commands show the `.so` suffix used on the measured platform; use the
selected build's `DL_EXT` on platforms with another module suffix. The optional
`ZDRAW_TEST_LOCALE` override must name an available UTF-8 locale.
