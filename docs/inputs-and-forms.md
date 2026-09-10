# Editable inputs and forms

These optional Zsh components add single-line editing and small forms without an
application framework. They use the shared theme and utility resolver. Loading
neither initializes curses nor reads input; the application owns its event loop,
keymap, refreshes and terminal protocols. No change to the C module is required.

```zsh
source ./lib/zdraw-form.zsh  # Includes zdraw-input and shared styles.
typeset -A zdraw_ui_theme zdraw_ui_form
zdraw-ui-theme dark 256
zdraw-form-init 'Display name' '' required,max-length=40 \
                Port 443 required,integer,min=1,max=65535
# After initializing a window:
zdraw-form stdscr 2 4 6 40 focus selected:bg=accent
zdraw-form-action edit insert 'Ada'
zdraw-form-action next
if zdraw-form-action validate; then
  print -r -- "$zdraw_ui_form[1,text] / $zdraw_ui_form[2,text]"
fi
```

Only print after returning ownership of the terminal to the shell, or direct
application results to a separate destination. The complete interactive recipe is
[`examples/form.zsh`](../examples/form.zsh): Tab/Shift-Tab move fields, arrows and
Home/End move the caret, Ctrl-A selects all, Enter validates, and Escape quits.
Shift-arrow selection depends on the terminal exposing the corresponding curses
key. Running with `--paste` explicitly enables native bracketed paste; cleanup
uses `zdraw end` inside an `always` block.

## Individual fields

Source `lib/zdraw-input.zsh` and declare an ordinary writable association
`zdraw_ui_input`. Function-local outputs work through Zsh dynamic scope.

| Call | Behavior |
| --- | --- |
| `zdraw-input-init text [byte-limit]` | Replace state; caret and anchor at end. Default limit 4096, allowed 0–32767. |
| `zdraw-input-edit insert text` | Replace the selection, or insert at the caret. |
| `zdraw-input-edit left\|right\|home\|end` | Move and collapse selection. Left/right first collapse a nonempty selection to that edge. |
| `zdraw-input-edit select-left\|select-right\|select-home\|select-end\|select-all` | Extend selection or select the complete value. |
| `zdraw-input-edit backspace\|delete\|clear` | Delete selection, adjacent complete unit, or all text. |
| `zdraw-input window y x columns states [utilities…]` | Paint one row, scroll horizontally to the caret, highlight selection and show a software caret in `focus` state. |

State keys are `text`, `cursor`, `anchor`, `limit`, `paste_active`, `paste_failed`
and `paste_buffer`. Cursor/anchor are zero-based **source byte offsets** at native
`textpos` boundaries. Movement/deletion keeps a positive-width base with its
following zero-width characters; this is the module's clipping-unit policy, not
full Unicode grapheme segmentation. UTF-8 text requires a matching locale and
wide-text support. Tabs, line breaks, control characters and invalid encoding
are rejected. There is no multiline, password masking, undo history or clipboard
ownership in this API.

Editing failures leave the value and selection unchanged. Malformed offsets are
rejected before arithmetic. Editing never evaluates text. Drawing preserves the
native cursor and current attributes; the software caret is ordinary cell data.
Selection uses `selected:` utilities and the caret uses `cursor:` utilities.
Forms also expose `invalid:`. Colors and attributes are customizable; input rows
require `border=none`, `px=0`, `py=0`, `align=left`. Compose with panels for borders
and padding. A one-column viewport shows a blank caret when its glyph is wider
than the viewport, without splitting the glyph. A `disabled` appearance does not
prevent an application from calling edit actions: the application owns that policy.

## Paste transactions

Forward native `event` paste phases to:

```zsh
zdraw-input-paste begin
zdraw-input-paste data "$chunk"  # May end in the middle of a UTF-8 sequence.
zdraw-input-paste end
# Or abandon a buffered edit explicitly:
zdraw-input-paste cancel
```

The buffer is bounded by the field byte limit. Only `end` attempts insertion and
validates the entire result. Oversized data marks the paste failed and releases
its buffer; continue consuming native events through `end`. Invalid or oversized
pastes preserve the original text and selection. A failed `end` still clears the
active state. Ordinary edits and form focus changes are refused while a paste is
active. `cancel` discards toolkit data; it does **not** cancel or consume an active
native protocol stream. Keep draining that stream before changing input owners.

The toolkit never enables/disables paste mode. Enable it explicitly at the
application boundary, and use the native cleanup contract described in
[application integration](application-integration.md).

## Validation

Declare a writable scalar `zdraw_ui_error`, then call
`zdraw-input-check [rules…]`. It returns 0 and clears the error for a valid value,
1 and a human-readable error for invalid data, or 2 for invalid state/rules/output
without changing the error. All rules are checked for valid syntax even after a
value fails an earlier rule; the first failing rule supplies the message.

Rules: `required`, `min-length=N`, `max-length=N`, `integer`, `min=N`, `max=N`.
Length counts Zsh characters (code points in a multibyte locale), not cells or
graphemes. Numeric validation accepts unsigned decimal values up to nine digits;
leading zeroes are decimal. Bounds are unsigned decimal literals up to nine
digits. `min`/`max` also require a numeric value. At most 16 rules are accepted.
No callbacks or shell expressions are executed. Applications can implement their
own validation and set a field's `N,error` to a printable message.

## Forms

`zdraw-form-init label value comma-separated-rules [label value rules…]` creates
1–16 fields, each with a default 4096-byte limit. An empty rules string means no
validation. Initial invalid values are allowed and start without visible errors.
The caller owns `zdraw_ui_form`, an ordinary writable association: `count`,
`focus` (one-based), and `N,label`, `N,rules`, `N,error`, plus `N,text`, `N,cursor`
and the other input state keys. Field identity is its stable one-based index.

`zdraw-form-action edit action [text]` and `paste phase [chunk]` forward to the
focused field. Successful edits clear its previous error. `next` and `previous`
validate the current field and move cyclically, allowing the user to leave an
invalid field. `validate` checks every field, stores all errors, focuses the first
invalid field, and returns 1; all valid returns 0. Invalid form actions return 2;
forwarded input actions retain their input status. Paste drain/cleanup changes
are retained even when the forwarded action fails.

`zdraw-form window y x rows columns focus|inactive|disabled [utilities…]` uses
three rows per visible field: label, value and error. The viewport follows focus;
fewer than three rows returns 2 without drawing. Keep the same form association
across resize. Draws read state and never submit, refresh, move focus or consume
input. Use `zdraw-form-action validate` before reading values for submission.

The implementation is intentionally for bounded single-line fields and small
forms. The tests cover combining/wide characters, selection replacement,
malformed offsets, paste chunk boundaries/overflow, rule validation, scrolling,
retained styles, actual PTY input, resize and terminal cleanup.
