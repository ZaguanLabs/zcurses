# Capability and input portability investigation

Recorded 2026-09-10. These results describe the named configurations and tests;
they do not establish universal terminal compatibility. All module tests used the
matching public Zsh 5.9.2 build, ncurses 6.5 (header patch 20250802), Linux x86-64,
and `C.UTF-8`. Kernel/libc details are in the recorded JSON.

## Image placement experiment

The [image-preview guide](../image-previews.md#native-placement-research) describes
the bounded adapter and the separate opt-in placement experiment. The
[image matrix](image-matrix-2026-09-10.json) records 12 visual lifecycle captures
per profile, plus native placeholder readback. Images were displayed by Kitty
0.44.0 directly and through tmux `next-3.3` with DCS passthrough, including copied
and covered cells. Resume through that tmux profile and reupload after an
interrupted transfer failed to restore visible images. The Screen/direct-APC and
xterm profiles produced no test-image pixels. These are rendering observations,
not support flags inferred from environment variables.

The ordinary mosaic preview uses curses cells and remains the usable default.
Native placement is deferred pending acknowledged upload/error ownership,
reliable repaint/recovery, and session resource cleanup. See the guide for exact
commands, captured configurations and limits; this experiment does not add an
image protocol to the native module.

## Real emulator and multiplexer matrix

The driver starts a private Xvfb display, launches real xterm processes, and uses
isolated tmux/screen sessions with empty configuration files. It queries modes
without enabling them and records native capability fields after a reply or a
1500 ms timeout. It does not test how an emulator paints pixels.

| Terminal / intermediary | Application TERM | Paste 2004 | Focus 1004 | Sync 2026 |
| --- | --- | --- | --- | --- |
| XTerm(407), direct local PTY | `xterm` | Reply: reset | Reply: reset | Reply: unrecognized |
| XTerm(407), tmux `next-3.3`, default session | `screen` | Unknown: timeout | Unknown: timeout | Unknown: timeout |
| XTerm(407), GNU Screen 5.0.1, empty config | `screen` | Unknown: timeout | Unknown: timeout | Unknown: timeout |
| Kitty, WezTerm, Windows Terminal, other xterm/tmux versions | — | Untested | Untested | Untested |
| Actual SSH remote connection | — | Untested | Untested | Untested |

No response from a multiplexer is not a negative support claim. The outer xterm's
answers are not automatically evidence about the session inside a multiplexer.
No passthrough wrappers or environment-name heuristics are used.

Reproduce after the normal build, with `Xvfb`, `xterm`, and optionally `tmux` and
`screen` available:

```sh
python3 scripts/portability/terminal-matrix.py \
  --output .build/portability/terminal-matrix.json
```

[Recorded real-terminal results](terminal-matrix-2026-09-10.json) retain the exact
returned fields, shell/curses/locale and intermediary versions. Missing optional
executables are recorded as untested rather than silently replaced.

## Controlled transport and interruption coverage

These are scripted PTYs, not observations from an SSH host or a second emulator.
They run in `make test` and are useful reproducible fault scenarios:

| Scenario | Evidence |
| --- | --- |
| Slow/fragmented response transport | Pieces arrive after 30, 90 and 150 ms with surrounding letter/arrow input; reply recognized and keys preserved. |
| Fragment gap exceeds escape delay | With 20 ms escape delay and an 80 ms gap, the entire sequence survives as ordinary input; no false evidence. |
| Unresponsive peer / late response | A 20 ms request expires; a subsequent complete report cannot change unknown support. |
| Invalid and unsolicited replies | Unknown report values remain ordinary input; recognized unsolicited reports produce events without becoming evidence. |
| Paste collision | A mode report inside bracketed paste remains literal payload; requests during an active paste fail. |
| Explicit handoff and cancellation | Suspend cancels a pending query, removes enabled paste mode and restores shell termios; a reply after resume is late. |
| Real interactive Zsh job control | Application TSTP/CONT/USR1 traps remain owned by the application; `bg` cannot restore curses, `fg` can, and final terminal state is restored. |
| End and unload | Input registrations, pending queries, observations and per-session attempt limits are cleared. |

The tests separate query acceptance deadlines from curses escape-decoder latency.
They do not establish an upper bound on arbitrary signal handlers, scheduler
stalls, output backpressure or emulator processing time.

## Another curses implementation

The [portable NetBSD curses source](https://github.com/sabotage-linux/netbsd-curses)
was built at commit `51d179dad861640caeb76674b5908ccd79f04fae`, entirely under
`.build/portability/`. A small C program probes the same private input-pad
primitive used by zdraw's ncurses path. It stages a frame, polls an empty pad,
reads a real PTY key, and checks that the marker is emitted only by explicit
`doupdate`. Both `wgetch` and `wget_wch` pass, with terminal mode restoration.
The same probe passes against ncurses.

| Build | Empty poll | Key read | Explicit presentation | zdraw module support |
| --- | --- | --- | --- | --- |
| ncurses 6.5 | No queued frame emitted | No queued frame emitted | Frame emitted | Full module suite tested |
| Portable NetBSD curses, pinned commit | No queued frame emitted | No queued frame emitted | Frame emitted | Not enabled; full module integration unverified |

[NetBSD probe results](netbsd-input-pad-2026-09-10.json) and
[ncurses probe results](ncurses-input-pad-2026-09-10.json) record the checks.
This is positive primitive-level evidence, not a full alternate-library module
validation. The native `norefresh_events` gate remains ncurses-only and other
builds retain status 2. A full matching-shell NetBSD curses build, feature gates,
resize handling and the module's existing retained-window/pad suite are a separate
follow-up before widening that gate. No extra curses dependency was added.

Reproduce on Linux with Git, GNU make, a C compiler, and the normal ncurses
headers available. The prefix is local; these commands do not install system files:

```sh
mkdir -p .build/portability
git clone https://github.com/sabotage-linux/netbsd-curses.git \
  .build/portability/netbsd-curses
git -C .build/portability/netbsd-curses checkout 51d179dad861640caeb76674b5908ccd79f04fae
env -u TERMINFO -u TERMINFO_DIRS make -C .build/portability/netbsd-curses \
  -j4 CFLAGS='-O2 -fPIC' PREFIX="$PWD/.build/portability/netbsd-prefix" all install
cc -O2 -I .build/portability/netbsd-prefix/include \
  scripts/portability/input-pad.c \
  .build/portability/netbsd-prefix/lib/libcurses.a \
  .build/portability/netbsd-prefix/lib/libterminfo.a \
  -o .build/portability/netbsd-input-pad
python3 scripts/portability/input-pad.py .build/portability/netbsd-input-pad
cc -O2 -D_XOPEN_SOURCE_EXTENDED scripts/portability/input-pad.c \
  -lncursesw -o .build/portability/ncurses-input-pad
python3 scripts/portability/input-pad.py .build/portability/ncurses-input-pad
```

Clear `TERMINFO` during the external build: its generator otherwise inherits that
path and can silently generate an empty embedded database. This happened in the
initial local build; a clean rebuild without the variable produced the recorded
successful results. Tests use the selected locale and do not load installed Zsh
modules. These optional investigations are separate from the standard test suite.

## Enhanced input follow-up

Milestone 4 extends the same matrix with focus activation and the kitty keyboard
query. It uses the matching Zsh 5.9.2 build, ncurses 6.5 and `C.UTF-8`:

| Terminal / intermediary | Focus activation | Keyboard activation | Enhanced key evidence |
| --- | --- | --- | --- |
| XTerm(407), direct | Enabled after reset report | Unknown; left off | Legacy fallback |
| XTerm(407), tmux `next-3.3` | Unknown; left off | Unknown; left off | Legacy fallback |
| XTerm(407), Screen 5.0.1 | Unknown; left off | Unknown; left off | Legacy fallback |
| Kitty 0.44.0, private Xvfb | Enabled after reset report | Enabled after flags reply | Ctrl+Shift+S press/release and associated `a` text verified |

[Recorded enhanced results](enhanced-matrix-2026-09-10.json) contain the actual
returned fields and executable version seen by the driver. The kitty test uses
its remote key-command injection for the shortcut and XTest on the private Xvfb
display for associated text. Remote key-command injection alone did not supply
associated text in this tested version. The test is real emulator encoding of
synthetic key input, not physical keyboard or IME coverage. Focus in/out decoding,
repeat events, paste collisions and restoration are separately covered by PTYs.

```sh
python3 scripts/portability/terminal-matrix.py --enhanced \
  --output .build/portability/enhanced-matrix.json
```

The optional kitty case requires kitty, X11/XTest shared libraries, and software
OpenGL support under Xvfb. It starts with an empty kitty configuration and a
private control socket, and closes its own process and display. It does not use
the user's running kitty instance or desktop. Unsupported/missing combinations
remain untested; actual SSH and other terminal versions are still outside the
recorded matrix. The initial milestone-3 JSON is retained as historical evidence.

## Frame presentation follow-up

The [frame probe](../../scripts/portability/frame-matrix.py) tests actual rendered
pixels using private Xvfb terminals. A PTY relay forwards native capability queries
and real replies, captures one `present` update, then pauses delivery at its byte
midpoint. ImageMagick reads the private display before, during and after that
pause. No terminal contents from the user's desktop are accessed.

[Recorded results](frame-matrix-2026-09-10.json), Zsh 5.9.2, ncurses 6.5,
`C.UTF-8`:

| Terminal / intermediary | Mode-2026 evidence | Activation | Mid-frame observation |
| --- | --- | --- | --- |
| XTerm(407) | Unrecognized | Declined | Ordinary output exposes a partial frame |
| XTerm(407), tmux `next-3.3` | Unknown, timeout | Declined | Ordinary output exposes a partial frame |
| XTerm(407), Screen 5.0.1 | Unknown, timeout | Declined | Ordinary output exposes a partial frame |
| Kitty 0.44.0 | Reset | Enabled | Old frame retained until closing marker |

Kitty's plain-output comparison changed 808,595 RGB bytes at the midpoint;
synchronization changed **zero**, while both final frames changed 1,595,580 bytes.
The relay held the remainder for about 181 ms. The plain update was 4,278 bytes;
the synchronized update was 4,294 bytes, including the 16 marker bytes. Reported
`producer_interval_ms` measures relay release of the native producer to receipt
of its completion report (about 0.25–0.28 ms here), not CPU time, physical-display
latency or a portable performance bound. Pixel hashes and exact relay pauses are
recorded. The fixture changes a large colored cell region; the normal PTY suite
separately exercises the task monitor's table/chart views and resize behavior.

```sh
python3 scripts/portability/frame-matrix.py \
  --output .build/portability/frame-matrix.json
```

Required programs are Xvfb, xterm and ImageMagick `import`; kitty, tmux and screen
are optional cases. Kitty also needs software OpenGL on Xvfb. Multiplexers use
private sessions and empty configurations. This is a controlled delayed local
transport, not an actual SSH test. There is one midpoint sample per frame; the
probe does not claim continuous observation, all emulator versions, physical
refresh timing or behavior when a delay exceeds an emulator's own timeout. A
blocked writer cannot enforce a portable hard synchronization deadline; the
[API contract](../frame-presentation.md) states that limitation explicitly.


## Unicode boundaries and rendering

Milestone 8 adds an [18-case Unicode corpus](../../tests/unicode/corpus.json),
[pinned boundary policy](../unicode-boundaries.md), and a
[raw/native rendering comparison](unicode-matrix-2026-09-10.json) on the same
private xterm/tmux/screen/kitty matrix. The record separates libc column sums,
curses cell contents, raw cursor replies and actual screenshots. Width agreement
alone does not establish correct rendering: Screen shows visible combining/joiner
problems, while kitty shapes several sequences with advances different from libc.
Eight [raw and native captures](unicode-captures/) preserve the observations.

```sh
python3 scripts/portability/unicode-matrix.py \
  --output .build/portability/unicode-matrix.json \
  --captures .build/portability/unicode-captures
```

These optional probes use an explicit input owner for cursor replies and a private
Xvfb display. The production text-query and editing policy remains passive.
