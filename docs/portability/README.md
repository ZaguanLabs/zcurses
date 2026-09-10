# Capability and input portability investigation

Recorded 2026-09-10. These results describe the named configurations and tests;
they do not establish universal terminal compatibility. All module tests used the
matching public Zsh 5.9.2 build, ncurses 6.5 (header patch 20250802), Linux x86-64,
and `C.UTF-8`. Kernel/libc details are in the recorded JSON.

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
