# Application integration

This completes the final development batch on 2026-09-10. The examples use the
matching shell and modules built in `.build/`, including staged `zsh/zselect`
and `zsh/system`. No installed module or other project is required.

## Streaming paste

```zsh
zdraw paste on
typeset -A event
typeset -i pasted=0
if zdraw event stdscr event norefresh poll; then
  if [[ $event[type] == paste ]]; then
    # Append to a bounded application buffer, stream to a file, or count bytes.
    pasted=$(( pasted + event[bytes] ))
  fi
fi
# After the end record:
zdraw paste off
```

`paste on` explicitly requests xterm bracketed-paste mode 2004. It requires
terminal stdin/stdout and compiled ncurses `define_key`, `key_defined` and
`keybound`; check `streaming_paste`. It reserves an unused key code and refuses
an already-bound start delimiter instead of replacing someone else's binding.
Repeated `on` and `off` are idempotent. Status is 0 on success, 1 for invalid
state/arguments or library/output failure, and 2 without compiled support.

Curses remains the sole terminal reader. It recognizes the start delimiter using
its normal escape decoder. Once recognized, `event` reads payload bytes from the
same curses queue with keypad interpretation disabled until the end delimiter.
The inherited `input` command is rejected while paste is enabled. Do not use
shell `read`, `sysread`, ZLE or a second process to read that terminal concurrently.
Ordinary mouse/keyboard decoding resumes after the end record.

While paste is enabled, the module owns **raw terminal input mode** so signal
characters, flow-control bytes and carriage returns can reach the decoder intact.
This applies between pastes too: Ctrl-C is an input character rather than a
terminal-generated signal, and applications must handle it explicitly. Disabling
paste restores the pre-enable input modes; suspension restores the original shell
modes, and resume restores the enabled input policy. Paste is off by default.

Paste records have their own schema:

| Field | Meaning |
| --- | --- |
| `type` | `paste` |
| `phase` | `begin`, `data`, or `end` |
| `text` | Original raw bytes; empty on `begin`, possibly empty on `end` |
| `bytes` | Original byte count of `text`, at most 4096 |
| `encoding` | `byte`, including on wide-input builds |
| `source` | `bracketed-paste` |

Consume text from **both data and end records**. UTF-8 can split between records;
so can NULs, newlines and arbitrary controls. Never treat paste text as shell code
or write it unfiltered to the terminal. Applications choose decoding, sanitizing,
storage and total size limits. The module buffers one bounded record and at most
five possible end-delimiter bytes; it does not accumulate an entire paste.

The first payload read uses the requested timeout; subsequent reads in that
record poll. A record also has a bounded read-work limit. With no available data,
status 1 leaves the destination unchanged while retaining an incomplete delimiter.
False end prefixes are returned as data. End-delimiter fragments can span any
number of calls/timeouts. The start delimiter follows curses' escape delay:
fragments must arrive within that decoder's timing window. `inputdelay` trades
latency against tolerance of slow fragmented keys/start delimiters. This is not
an independent keyboard protocol decoder. A literal end delimiter in the payload
terminates the paste, as specified by the terminal protocol.

Invalid event targets and flags are rejected before input consumption. `paste
off` and `suspend` reject an active paste; applications must first finish it.
`end` and unload disable mode 2004, remove the owned key binding, clear parser
state and flush currently queued input when abandoning an active paste. They
cannot retract bytes that arrive after the session ends. No automatic timeout
closes a paste. Disabling/enabling modes emits control sequences immediately;
`norefresh` still prevents drawing-frame presentation during input.

References: [xterm bracketed paste](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html),
[curses key definitions](https://invisible-island.net/ncurses/man/define_key.3x.html).
Raw and newline handling follow the [curses input options](https://invisible-island.net/ncurses/man/curs_inopts.3x.html).

## Suspend and resume

```zsh
source ./lib/zdraw-run.zsh
zdraw-run less ./README.md
```

`suspend` saves current program modes, disables configured paste and active mouse
reporting, calls `endwin`, and restores the terminal modes saved before `init`.
Windows, pads, prepared rows, styles and color pairs remain owned by the session.
An active paste blocks suspension. While suspended, drawing, input and `init`
are rejected; `resume`, `suspend`, `end`, `inputinfo`, geometry/color queries and
headless text queries remain available. Ending a suspended session frees resources
without re-entering the alternate screen. Repeated suspend/resume is idempotent.

`resume` restores program modes, rechecks terminal dimensions and applies them
when `resize_term` is available, then repaints the retained virtual frame. It
restores configured paste and mouse reporting. Resume is an **explicit presentation
boundary**, including any frame queued before suspension. Applications still own
window relayout and viewport recomposition: the next event reports changed terminal
geometry where supported. Queued input is not normally flushed during handoff.

Check `suspend_resume` (`def_prog_mode` and `reset_prog_mode`). Commands require
an initialized session; status is 0 on success, 1 for state/library failure, and
2 without compiled support. Recoverable preparation failures keep the session
active; failed resume mode/resize/repaint steps leave it suspended for retry or
`end`. Terminal-output failures can leave partially applied terminal state.

`zdraw-run command [args ...]` requires an active session. It suspends, executes
the argument array directly, and resumes in an `always` block. It returns the
foreground command's status unless restoration fails (status 1). No command
string is evaluated. The wrapper does not install signal or job-control traps;
applications should explicitly suspend before stopping themselves or transferring
terminal ownership. `SIGKILL` cannot run cleanup. Tests cover ordinary handoff,
failed commands, an interrupted foreground child, resize while suspended, repeated
calls, end/unload, retained resources and injected library failures.

Reference: [curses program/shell modes](https://invisible-island.net/ncurses/man/curs_kernel.3x.html).

## Asynchronous input

`zdraw event window association poll [norefresh] [mouse]` temporarily sets the
initial curses timeout to zero and restores it on every return path. It delivers
queued events without changing application timeout policy. Empty input returns
1 without assigning the destination. It retains native escape-sequence waiting
and EINTR behavior, so it is **not a hard real-time nonblocking guarantee**.

`zdraw inputdelay milliseconds` explicitly changes ncurses' escape-decoding delay
from 0 through 1000 ms; `end`/unload restores the value saved before the first
change. Check `input_delay` (`get_escdelay` and `set_escdelay`). Lower delays improve
responsiveness but can split slow function-key or paste-start sequences. Default
input retains the existing library delay unless this command is used.

`zdraw inputinfo association` requires a session and returns:

| Field | Meaning |
| --- | --- |
| `fd` | 0 for terminal stdin used by `initscr`, otherwise -1 |
| `queued` | `unknown`; descriptor readiness cannot reveal curses' internal queue |
| `wait_ms` | Recommended maximum external wait tick, 20 ms |
| `escape_delay_ms` | Current ncurses delay when queryable, otherwise `unknown` |
| `suspended` | Whether the session has explicitly released the terminal |
| `paste_enabled`, `paste_active` | Configured paste ownership and active payload state |
| `paste_pending` | Number of held possible end-delimiter bytes |

Mode fields describe module configuration, not proof that a terminal received or
supports a control sequence. The query consumes no input and presents no frame.
Check `input_info`; status is 0 on assignment, 1 for invalid target/state.

Drain a bounded batch of `event ... poll norefresh`, process worker descriptors,
draw if state changed, then call `zselect` with a timeout of at most the suggested
tick. `zselect` timeouts are in **hundredths of a second** (`-t 2` = 20 ms).
Include terminal fd 0 to wake on new bytes, but never read it outside curses.
Remove worker descriptors at EOF. Poll again even after a timeout because curses
may already hold input and terminal resize is not descriptor data. Bound event
batches so a busy input stream cannot starve worker output. The combined example
uses 32-event batches and `sysread` only on the worker pipe.

No extra event-loop framework, reader thread or raw-terminal decoder is added.
See the selected source release's `Doc/Zsh/mod_zselect.yo` and `mod_system.yo`.

## Colored command output

```zsh
source ./lib/zdraw-sgr.zsh
typeset -A zdraw_sgr_state
typeset -a reply
zdraw-sgr-feed $'\e[1;32;40mSuccess\e[0m\n'
# reply is triples: kind, style, text
zdraw-sgr-feed '' final
```

The caller owns `zdraw_sgr_state` and `reply`. Both must be ordinary writable
association/array parameters. Use enclosing function locals for independent
streams; the names are deliberately shared through native Zsh dynamic scope.
State is opaque, local application data, not a format for importing untrusted
serialized state. The module must be loaded for headless `textinfo` validation;
the decoder itself does not require `init` or allocate colors.

`zdraw-sgr-feed chunk [final]` returns triples whose kind is `text`, `newline`,
`tab`, or `carriage_return`. Text records carry a complete `spans` style and
printable text. Other records have empty style/text. Text is buffered until a
control/style boundary or `final`, so partial UTF-8 bytes across input chunks stay
together. Applications own line layout, tab stops, carriage-return semantics,
clipping and retention. The example provides a bounded pad-backed output view.

Supported SGR: reset; bold/dim/underline/blink/reverse and their resets; basic and
bright indexed colors; default colors; `38/48;5;N`; and `38/48;2;R;G;B` with
semicolon syntax and components 0–255. Unsupported numeric attributes are ignored;
malformed color forms discard that SGR command without partial style changes.
Styles remain symbolic strings. Drawing still checks actual terminal color limits,
default-color support and explicit `truecolor on` for RGB. The decoder never enables
RGB itself. Unsupported CSI/escape commands, OSC/DCS/APC/PM/SOS strings and other
controls are filtered, including when split across chunks. No escape bytes are
forwarded to drawing text and no input is evaluated as shell code.

Limits per call/stream: 65,536 input bytes per chunk, 65,536 pending text bytes,
64 pending CSI bytes, and 2,048 output records per call. Longer CSI commands are
discarded through their final byte; control-string payloads are discarded without
buffering. Other limit errors return 1. Invalid/nonprintable text at an emission
boundary returns 1; this includes invalid encoding or a combining-only text span.
Failure leaves both caller state and reply unchanged. Success replaces reply;
an empty reply is normal for a partial span. `final` flushes text, discards an
unfinished control sequence/string, and resets stream state. Drop the caller-owned
state to abandon a stream; no terminal cleanup is needed for this decoder.

This intentionally does not emulate an interactive subprocess terminal. It is
suited to colored compiler, search and diagnostic output read from a pipe.


## Capability queries and foreground continuation

Use [passive capability records](capabilities.md) for evidence without terminal
I/O. Explicit queries use the same `event` owner as paste and keyboard input;
handle `type=capability` without treating it as text. Keep external waits finite
so the next event call can deliver a query timeout. Cancel/off and successful
suspend do not retry requests; mode replies have no request identifier.

A background continuation must leave the session suspended until foreground
ownership is restored. On systems with terminal process-group support, `resume`
returns 1 in the background before changing terminal modes. Applications retain
signal/trap policy, including explicit suspend before stopping. The
[portability record](portability/README.md) documents the interactive-shell
`bg`/`fg` test and the limits of the current terminal matrix.
