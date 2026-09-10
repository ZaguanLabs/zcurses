# Capability evidence and explicit queries

`zdraw capabilities association [name=yes|no|unknown …]` is passive inspection.
It works before initialization, during a session and while suspended. It never
opens a terminal, sends queries, reads input, enables modes or presents drawing.
The optional overrides affect only the returned record.

```zsh
zmodload zdraw
typeset -A capabilities
zdraw capabilities capabilities
print -r -- "$capabilities[streaming_paste,support]"  # unknown without evidence

# An application decision, explicitly labelled as such:
zdraw capabilities capabilities synchronized_output=no
```

The destination follows the other native association APIs: ordinary writable
association or absent parameter; invalid, readonly, special and subscripted
targets fail before changing it. Unknown names, duplicate overrides and values
other than the three literal choices fail without replacing the destination.

Run the interactive inspector with the matching built shell:

```sh
.build/zsh/Src/zsh -df examples/capabilities.zsh
```

It begins passively. Press `p` to request the next terminal mode, `o` to cycle a
record-only synchronized-output override, and `q` or Escape to exit. It does not
enable paste, focus reporting or synchronized output.

## Record contract

The format is `zdraw-capabilities-1`. `names` lists the eight capability names;
`session` is `inactive`, `active` or `suspended`. `term`, `locale` and
`curses_version` describe local configuration, not verified terminal identity.
`query_owner` says whether the module has reserved mode-report decoding.

Each capability has these comma-separated keys:

| Field | Meaning |
| --- | --- |
| `name,compiled` | Whether this build implements the corresponding operation; `yes` or `no`. |
| `name,support` | `yes`, `no` or `unknown`, in the scope described below. |
| `name,source` | `none`, `compiled`, `curses`, `terminfo`, `reply` or `override`. |
| `name,evidence_support`, `name,evidence_source` | The unmodified evidence, even when an override is supplied. |
| `name,enabled` | Module-owned persistent activation, `yes` or `no`; never inferred from a reply or override. |
| `name,reported` | Last accepted mode report: `unknown`, `unrecognized`, `set`, `reset`, `permanent-set` or `permanent-reset`. |
| `name,query` | `never`, `pending`, `replied`, `timeout`, `cancelled`, `send-error`, or `unavailable` for non-queryable entries. |

| Name | Scope of support evidence |
| --- | --- |
| `colors` | Curses' current session result; unknown before initialization. |
| `truecolor` | Existing terminfo-based direct-color detection; unknown before initialization or without that compiled detector. |
| `wide_text` | Compiled multibyte text measurement, not font coverage, emoji shaping or wide curses input. |
| `norefresh_events` | Compiled implementation of the explicit per-call no-refresh input path. |
| `suspend_resume` | Compiled retained-session handoff implementation. |
| `streaming_paste` | Recognition of DEC private mode 2004, separately from the compiled paste API. |
| `focus_events` | Recognition of mode 1004; its event API is not implemented in this milestone. |
| `synchronized_output` | Recognition of mode 2026; its presentation API is not implemented in this milestone. |

`enabled=no` is also used for operations without persistent activation, such as
text measurement and per-call no-refresh input. Paste enabled state means module
configuration while not suspended; it is not confirmation that the peer obeyed
an enable sequence. A `permanent-reset` report recognizes a mode but does not
establish that it can be enabled. Applications need the reported state as well
as recognition before attempting later protocol operations.

These records complement `zdraw_features`, which remains compile-time discovery.
`capability_evidence` advertises passive inspection; `capability_queries` advertises
the optional query implementation. An override never bypasses native availability
checks or creates missing operations. It is not retained between inspections.

## Explicit query lifecycle

After `init`, an application can reserve reply decoding and send one request:

```zsh
typeset -A event
zdraw query on
zdraw query request streaming_paste 1000
# Keep normal event handling for keys, mouse, resize and paste in this loop.
while zdraw event stdscr event norefresh; do
  [[ $event[type] == capability && $event[name] == streaming_paste &&
     $event[phase] == (reply|timeout) ]] && break
done
zdraw capabilities capabilities
zdraw query off
```

This example assumes a blocking/adequate window timeout. Applications using
`poll` or finite timeouts keep calling their event loop after empty reads.
There is no background reader or timer callback. External wait loops must use a
finite tick, as described in [application integration](application-integration.md).

- `query on` reserves 15 exact reply sequences in the existing curses decoder.
  It sends nothing and enables no terminal mode. Repeated `on` is idempotent.
- `query request name milliseconds` supports only the three mode names above,
  with a literal decimal timeout of 20–5000 ms. It sends one DECRQM request and
  flushes stdout. Only one request may be outstanding; an active paste rejects it.
- `query cancel` cancels a pending request. It sends nothing and produces no
  synthetic cancellation event; inspection reports `cancelled`.
- `query off` cancels any request and releases the registered sequences. It does
  not flush input or reset existing evidence and attempts.
- Each mode may be requested **once per initialized session**, including after
  failure, cancellation, or toggling ownership off/on. Replies carry no request
  ID, so retries cannot reliably distinguish an old response from a new one.

The event owner receives `type=capability`, `source=decrpm`, `name`, numeric
`mode`, `phase`, numeric `report`, and empty `text`. `phase=reply` records evidence
only for the outstanding mode before its monotonic deadline. Report 0 means
unrecognized; 1–4 mean set, reset, permanently set or permanently reset. A timeout
has `phase=timeout` and `report=-1`, leaving support unknown. Other recognized
replies have `phase=unsolicited` or `late` and do not change evidence.

Deadlines are processed at event calls; passive inspection can show an expired
request as `timeout` without consuming its pending timeout event. Non-poll input
caps its initial wait by the outstanding deadline. Curses escape decoding and
inherited signal retries can extend a call beyond that interval: this is a
response acceptance deadline, not a hard execution-time guarantee.

Only exact seven-bit reports are recognized. Ordinary keys, unsupported/malformed
reports and incomplete sequences retain the existing curses decoding behavior.
Fragments within the configured curses escape delay are combined, including
across delayed transport. Longer gaps can leave the reply as ordinary characters;
shorten `inputdelay` only with that tradeoff in mind. No unbounded raw parser or
response buffer is introduced. Report-shaped text inside streaming paste remains
paste payload. A matching sequence typed or injected during a request cannot be
authenticated as a genuine terminal response.

While query ownership is on, use `event`; inherited `input` is rejected to avoid
exposing private key codes. Do not run shell `read`, ZLE or another terminal reader
concurrently. Turning ownership off restores ordinary decoding, so subsequent
late reports can become ordinary input. There is no promise to filter replies
forever after ownership has been relinquished.

Successful `suspend` cancels the request before handing input back. Resume does
not retry it; registered decoding remains available for late replies after the
handoff. Bytes arriving while another foreground program owns the terminal belong
to that program. `end` and unload remove registrations and clear attempts and
evidence; repeated `init` in an active session preserves them.

On systems with terminal process-group support, background `resume` returns 1
before changing terminal modes; the application can resume after `fg`. The module
does not install application signal traps or automatically suspend for a signal.
Applications explicitly pair handoff and continuation with their own trap policy.

Query status is 0 on success, 1 for invalid state/arguments, collisions, resource
or I/O failures, and 2 without compiled support. The implementation requires
ncurses key registration and a monotonic clock. Protocol source:
[xterm DECRQM/DECRPM](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html).

See the [recorded compatibility investigation](portability/README.md) for actual
terminal and multiplexer results, scripted transport/interruption coverage and
the separate NetBSD curses probe. A timeout is evidence of no answer within the
chosen interval, not evidence that the terminal cannot implement the feature.
