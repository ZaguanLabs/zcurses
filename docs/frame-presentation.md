# Synchronized frame presentation

`stage` and `viewport` compose curses' virtual screen; `present` submits its diff
to the terminal. Optional `sync on` brackets only that final `present` call with
DEC mode-2026 markers. Drawing and application computation happen before the
terminal is asked to hold its visible frame.

```zsh
zdraw init
zdraw query on
zdraw query request synchronized_output 1000
# Process the capability reply or timeout in the normal event loop.
# After an accepted reset report:
zdraw sync on

# Build the frame with normal drawing operations, then:
zdraw stage stdscr sidebar
zdraw viewport content 0 0 2 20 18 60
zdraw present

zdraw sync off
```

The capability query has the existing single input owner, finite deadline and
one-attempt-per-session rules. It must run through `event`, alongside normal
application input. Neither `sync on` nor `present` consumes input or sends queries.
Loading the module, inspecting capabilities and ordinary presentation do not
activate the protocol. `event ... norefresh` remains the way to keep input from
presenting unfinished drawing.

## Activation and fallback

`sync on` requires a successfully accepted `synchronized_output` report of
`reset` (mode 2026, report 2). `set` could belong to another writer; permanent or
unrecognized states and unknown evidence cannot establish safe ownership. There
is no force form. Record-only capability overrides do not authorize activation.
Applications can retain ordinary `present` when activation fails.

`sync on` configures subsequent calls without immediately writing a begin marker.
Repeated on/off calls are idempotent. Check `synchronized_output` in
`zdraw_features` for the compiled API; its current gate uses the optional ncurses
query implementation. Capability `compiled` and observed terminal `support` are
independent. `synchronized_output,enabled=yes` means configured presentation in
an active session, not a permanently enabled terminal mode or paint confirmation.
It is `no` while suspended and after off/end/unload.

Status is 0 for success, 1 for invalid arguments/state or output/library failure,
and 2 when the compiled implementation or sufficient activation evidence is
unavailable. Initialization is required. Unknown support stays unknown on timeout.

## Exact presentation boundary

With synchronization configured, `present`:

1. Retries any outstanding reset from an earlier failed frame.
2. Defers Zsh signal traps, flushes earlier stdout, writes and flushes `CSI ? 2026 h`.
3. Calls curses' existing `doupdate` once and flushes its output.
4. Attempts `CSI ? 2026 l` and flushes it, including after a begin/update failure.
5. Releases the local frame guard, then lets deferred traps run.

A nested presentation attempt fails. No user callback, shell computation, input
wait or cross-command begin/end interval is introduced inside the region. An
empty `present` still emits a balanced marker pair: curses decides whether it has
any changes. The markers add 16 bytes per synchronized call. Windows, pads,
prepared drawing and the screen diff keep their existing semantics.

Ordinary `refresh`, implicit input refreshes and `resume` repaint retain their
existing paths and emit no synchronization markers. They may present staged
content. Applications requiring synchronized updates use `stage`/`viewport`,
`present` and no-refresh input consistently; enabling sync does not silently
change inherited operations. Output from another writer is outside this contract.

## Duration, interruption and failures

The owned region is bounded to one synchronous curses update and its marker
writes, with no open region between successful builtin calls. This is an
**operation bound, not a hard wall-clock deadline**. Curses and stdio can block on
a full terminal output queue; a stopped process, a dead transport or SIGKILL can
prevent any application from sending its closing marker. The protocol does not
specify a universal emulator timeout. There is no watchdog thread, alarm handler,
forced nonblocking descriptor mode or replacement of application signal traps.

The implementation attempts reset after a failed begin or update. A failed reset
retains a local cleanup obligation; another `present`, `sync off`, `suspend`,
`end` or unload attempts it again. A reset is idempotent. Cleanup cannot confirm
what a peer applied after a terminal write or flush failed. End/unload make a
best-effort final attempt and clear session state; failed presentation is not a
transactional rollback of curses' virtual or physical screen model. Handle the
failure explicitly and repaint or end the session as appropriate.

Successful suspension has no open synchronized region and retains the setting.
Resume repaints normally; the next explicit `present` is synchronized again. End
and unload clear configuration and evidence; a new session negotiates again.
Nothing automatically suspends the session in response to job-control signals.

## Example and measured evidence

```sh
.build/zsh/Src/zsh -df examples/task-monitor.zsh --sync
```

The monitor queries explicitly, displays the activation/fallback result, and
composes its table and chart views before each `present`. Use Tab to switch views,
`n` to advance work, `g` for ASCII charts and `m` for monochrome. Without `--sync`,
it sends no query and uses the same ordinary staged presentation path.

The [recorded rendering probe](portability/README.md#frame-presentation-follow-up)
relays native frame output through a private PTY, pauses halfway through delivery,
and compares actual Xvfb screen pixels. In kitty 0.44.0, a roughly 181 ms pause
exposed changed pixels without synchronization and zero changed pixels with it;
the complete frame became visible after the closing marker. The tested xterm,
tmux and screen paths declined activation. These observations establish one
specific improvement, not universal atomic painting, physical-display latency or
behavior on arbitrary slow/remote links.

Standard PTY tests verify byte ordering, empty frames, ordinary refresh, invalid
and unavailable activation, nested calls, failed updates, deferred SIGINT traps,
failed-reset recovery through off/suspend/unload, retained settings and session
cleanup. The monitor test exercises table/chart rendering, resize and more than
100 balanced synchronized presentations.

Protocol references: [synchronized-output semantics](https://github.com/contour-terminal/vt-extensions/blob/master/synchronized-output.md)
and [xterm mode queries](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html).
