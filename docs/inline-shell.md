# Inline shell picker experiment

This milestone investigates a small picker below an editable shell prompt. The
ownership decision comes first: **ZLE owns this entire interaction**. The prototype
uses a temporary recursive-edit keymap and `POSTDISPLAY`; `zdraw` provides only
headless text validation and clipping. No curses session is initialized.

| Resource | Owner and restoration policy |
| --- | --- |
| Keyboard and terminal modes | ZLE throughout, including nested selection. No native `event`, `read` on the terminal, or competing reader. |
| Cursor and editable buffer | Original ZLE buffer, cursor, mark and selection remain intact. Selection returns data; an application may explicitly insert a quoted value afterward. |
| Region below the prompt | Temporarily owned `POSTDISPLAY`; its previous value and highlights are restored on every normal/cancellation/error return. |
| Prompt and redisplay | ZLE, via `zle -R`; no cursor-position reports, raw escape sequences or alternate-screen switching. |
| Scrollback | No deliberate retained picker output. ZLE redraw/scroll behavior can leave historical fragments when terminal geometry changes; erasing terminal scrollback is outside the prototype. |
| Async pipe | Producer and original descriptor belong to the caller. Picker owns a duplicate and one generation-specific `zle -F -w` widget, removed before closing its descriptor. |
| Keymap and widgets | One explicit installed entry widget; temporary private map and callback/navigation widgets exist only during the picker. Existing keymaps and bindings are not replaced. |
| Jobs and shell suspension | Cancel the picker before changing shell job state. Ctrl-Z cancels it; it does not suspend a shell while transient display/watchers remain active. |

A general curses-backed inline drawing API has **not** shipped. `zdraw init`
currently initializes a full-screen curses session; placing one of its windows
below the prompt does not change that ownership. Teaching it to share scrollback,
origin and redisplay with ZLE would require a separate native-session design.
The prototype stays in `examples/`: it demonstrates a useful ZLE composition,
but does not establish a public inline drawing API or guarantee coexistence with
arbitrary prompt plugins.

## Try it

After the [normal build from public Zsh sources](building.md#build-and-test), run this
from the repository root in an interactive terminal:

```zsh
.build/zsh/Src/zsh -df scripts/inline-shell.zsh
```

The launcher creates a temporary `.zshrc` under `.build/`, starts the matching
built Zsh, and deletes the configuration when that shell exits, including a
nonzero exit. It preserves the child shell's exit status. It does not change
your startup files. The build stages matching ZLE/helper modules and the selected
source release's `add-zle-hook-widget` function alongside the module.

Type `print -r -- `, then **Ctrl-X Tab**. Move with arrows or Ctrl-P/Ctrl-N;
Enter selects. Escape, Ctrl-C, Ctrl-G and Ctrl-Z cancel. Paste is consumed by
ZLE's bracketed-paste widget and ignored. Exit the disposable shell when finished.

The launcher opts into inserting one shell-quoted word after selection. Its guard
requires the cursor at the end of the buffer after whitespace, or an empty buffer.
Use this demonstration with an ordinary command, outside quotes and substitutions:
the guard does not parse shell syntax or identify an unfinished quoted context.
Selecting a value does not execute the command; the next Enter does.

## Use the picker in a widget

In the **matching built interactive shell**, from the repository root:

```zsh
module_path=("$PWD/.build/modules" "${module_path[@]}")
fpath=("$PWD/.build/functions" "${fpath[@]}")
source examples/inline-picker.zsh
zdraw-inline-setup

typeset -a zdraw_inline_items=('local cache' 'remote index' 'release notes')
typeset zdraw_inline_result=''
bindkey -M emacs '^X^I' zdraw-inline-pick
bindkey -M viins '^X^I' zdraw-inline-pick
```

Sourcing defines functions; setup explicitly loads dependencies and installs the
entry widget. Setup refuses an unrelated widget with the same name. Choose your
own binding and save/restore any binding you replace. `zdraw-inline-teardown`
removes the owned entry widget when idle; it does not restore caller-owned
bindings or unload shared modules/functions.

A wrapper calls `zle zdraw-inline-pick` and uses `zdraw_inline_result` only when
the call succeeds. The result must be a writable ordinary scalar. The base widget
does not alter the command buffer or insert/execute the result. Cancellation
returns nonzero and leaves the prior result intact. A native session that is
active or suspended is refused before drawing. Nested picker calls are refused.

Initial data must be an array of at most 32 labels. Each label must be nonempty,
printable under native `textpos` validation, no more than 256 source bytes, and
occupy at least one terminal column. The picker shows up to five choices plus
one status line, reduced for short terminals. Label width is capped at 120
columns and clipped with native `textinfo`; the selection marker and a spare
rightmost column are budgeted separately. This is a short selection interaction,
without filtering or text entry.

## Asynchronous choices

Set the optional `zdraw_inline_source_fd` to a readable pipe descriptor before
opening the picker. The descriptor must be decimal, in 3–32767, and at most five
digits. Leave the parameter unset or empty for static choices. Do not give it the
terminal, a second consumer's stream, or a descriptor whose lifetime another
callback can change during selection.

For a finite demonstration, issue these commands at the prompt, then open the
picker using its binding:

```zsh
exec {zdraw_inline_source_fd}< <(print -r -- $'item\tadditional choice\nitem\t界面\ndone')
```

After the picker returns, close the caller's descriptor and clear the parameter:

```zsh
exec {zdraw_inline_source_fd}<&-
unset zdraw_inline_source_fd
```

The producer writes literal records, not shell code:

```text
item<TAB>label<LF>
item<TAB>another label<LF>
done<LF>
```

`<TAB>` and `<LF>` denote actual bytes. Labels may contain valid UTF-8 on a
UTF-8 locale. Fragmented records and split multibyte characters are accumulated
until a complete line is available. Empty labels, control characters, invalid
text, extra fields and unrecognized records are rejected. The final `done` record
ends consumption; do not send more bytes after it. Trailing bytes already in
that read cause an error; later bytes remain in the caller's stream.

Each `zle -F -w` callback makes one zero-timeout `sysread` of at most 1,024 bytes.
The entire stream is limited to 16 KiB, including framing; initial and streamed
choices together cannot exceed 32. Rendering only occurs when complete choices
or status change. A callback cannot wait for the rest of a record. The parser
retains at most the stream budget plus one read before rejecting excess input.

Completion, invalid/oversized input, read failure, and EOF without `done` remove
the watcher and close the picker's duplicate. Already accepted choices remain
selectable. Errors show a fixed message, never producer-supplied terminal text.
Acceptance and cancellation also remove the watcher before closing the duplicate.
The caller still owns its original descriptor and any producer process. Closing
the duplicate neither rewinds the stream nor cancels the producer: bytes already
read, including a partial record, are consumed. Each new invocation needs a fresh
framing boundary. A long-running producer needs caller-defined cancellation and
reaping; it must not write directly to the terminal.

## Verified behavior and limits

PTY tests use the shell and modules built from public Zsh 5.9.2. They cover
selection of literal shell metacharacters, command-buffer/cursor/selection
restoration, existing `POSTDISPLAY` and foreign highlights, emacs and vi insert
keymaps, ignored paste, fragmented UTF-8 updates, byte/item limits, invalid text,
truncated EOF, repeated invocation, removed watchers/closed duplicates, retained
caller descriptors, unchanged terminal modes and absence of alternate-screen
entry. The launcher is exercised through selection, quoted insertion, its cursor
guard, a nonzero shell exit and temporary-configuration cleanup.

ZLE performs immediate reflow on resize. The picker remeasures on its next widget
dispatch or complete async update; the line-pre-redraw hook does not guarantee
immediate invocation on SIGWINCH. Tests shrink the terminal and then navigate.
Long/multiline prompts and buffers can leave less visible room than the nominal
picker height; ZLE owns viewport clipping and scrolling. No emulator-specific
scrollback or grapheme-rendering guarantee is made beyond native text helpers.

Ctrl-Z cancels the picker. Tests then stop an ordinary foreground job, resume it
with `bg`, stop it again, and return it with `fg`, before opening another picker.
A failed shell command also leaves the next picker usable. Suspending the shell
externally during the picker is outside this experiment's tested contract.

The prototype temporarily owns `POSTDISPLAY` and its highlight entries. Concurrent
autosuggestions, highlighters or other callbacks that mutate this state need an
explicit integration agreement; restoring a snapshot can discard their intervening
changes. Existing prompt hooks must likewise tolerate recursive editing. Paste
capture inherits ZLE's buffering policy; the async stream limits do not bound a
pasted packet. Forced process termination cannot run shell cleanup.

The architectural blocker for a general native inline API is concrete: the
current curses lifecycle assumes full-screen ownership and has no shared prompt
origin, scrollback contract or coordinated ZLE redisplay. Adding a window position
alone cannot solve those responsibilities. Keep this bounded ZLE experiment as
research; a future native proposal must first define and verify that lifecycle.
