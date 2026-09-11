# Grapheme-safe text using native curses widths

Status: opt-in implementation of the reduced contract agreed for the zcoder /
zmdown integration. No replacement renderer, linked library, runtime download or
dependency on either application. Existing calls retain their default behavior.

## Select and discover the policy

```zsh
typeset -A contract info hit
typeset policy=unicode-17.0.0-egc-wcwidth-sum-attach-zero
zdraw textpolicy contract "$policy" || return $?

zdraw textinfo info '👩‍💻X' 4 "$policy"
# With libc widths woman=2, ZWJ=0, laptop=2:
# text=👩‍💻 width=4 total_width=5 remainder=X truncated=1
zdraw textpos hit '👩‍💻X' column 2 "$policy"
# text=👩‍💻 column_start=0 column_end=4 byte_start=0 byte_end=11

# Inside an initialized session, with an existing window:
zdraw spansclip panel 0 0 4 "policy=$policy" bold '👩' underline '‍💻X'
# Retains the entire emoji sequence in four native cells, all bold.
zdraw move panel 1 0
zdraw string panel '👩‍💻X' "policy=$policy"
# Advances five native cells when the row has enough room.
```

Syntax:

```text
zdraw textpolicy association [policy]
zdraw textinfo association text [columns [policy]]
zdraw textpos association text byte|column offset [policy]
zdraw spans window row column [policy=policy] style text [style text ...]
zdraw spansclip window row column columns [policy=policy] style text [style text ...]
zdraw string window text [policy=policy]
```

There is no global policy switch. The complete policy name opts each operation
in. `cell` and `libc-wcwidth` select legacy behavior. The older `grapheme` name
remains a **query-only boundary policy**: it does not check native storage and
cannot select safe drawing. `textpolicy` rejects that query-only name. Successful
safe `textinfo` and `textpos` results include the complete `policy` name and
`unicode_version=17.0.0`; their other result fields are unchanged.

`textpolicy` works before initialization, during suspension, and after cleanup.
It reads no terminal input, emits no terminal output and changes no locale or
module state. With no requested policy it reports the default and safe-policy
availability. Passing the safe name requires support now; failure leaves the
association unchanged. As with other queries, the destination must be an ordinary
writable association, or a valid name for one to create.

| Discovery field | Meaning |
| --- | --- |
| `policy`, `default_policy` | Selected policy; default is `libc-wcwidth` |
| `grapheme_policy` | Full safe policy name, including on unsupported builds |
| `grapheme_compiled`, `grapheme_available` | Complete path compiled; also usable in current locale/options |
| `width_model`, `locale` | `sum-libc-wcwidth`; current `LC_CTYPE` locale name |
| `boundaries`, `unicode_version` | Safe: `unicode-egc-attach-zero`, `17.0.0`; legacy: `spacing-attach-zero`, `none` |
| `style_policy` | Safe: `first-scalar`; legacy spans: `per-span` |
| `native_storage_checked` | 1 for the safe policy, 0 for legacy queries |
| `emoji_two_cells`, `intra_grapheme_styles` | Both 0: neither guarantee is provided |
| `persistent_grapheme_metadata` | 0: retained storage contains native cells, not grapheme records |
| `operations` | `textinfo textpos spans spansclip string` |
| `max_bytes`, `max_spans` | Safe: 1048576 original text bytes and 4096 span pairs per call; legacy: -1 (no added policy limit) |
| `native_cell_scalar_limit` | Native cell capacity excluding its terminator, or -1 without this backend; not a limit on an entire grapheme |

`zdraw_features` includes `text_policy` for discovery. `grapheme_safe_text` means
the complete safe path is compiled, not that the current locale or a particular
string is supported. `grapheme_boundaries` alone does **not** establish drawing
support. The safe path currently requires wide ncurses, the wide array-write and
readback APIs, Zsh multibyte support, `nl_langinfo(CODESET)`, a UTF-8 codeset, and
`MULTIBYTE` enabled. Other backends explicitly reject this policy.

## Exact text contract

- Segment with the existing pinned Unicode 17.0.0 extended grapheme engine
  (UAX #29 revision 47). Suppress boundaries before any scalar whose system
  `wcwidth` is zero, preserving native spacing-character/zero-width units.
  Thus `a` + U+200B + `b` has units `a` + U+200B, then `b`. This is a declared
  profile, not an unmodified UAX #29 boundary API.
- Sum every scalar's libc `wcwidth` within each unit. No maximum-width rule,
  emoji recognition override, normalization, replacement or shaping. For the
  tested libc, `👩‍💻` and `👍🏽` each occupy four cells, a flag two, and `1️⃣` one.
- Text is empty or begins with a positive-width printable scalar. Reject controls,
  NUL, invalid encoding, leading zero-width scalars and negative scalar widths.
  Unicode segmentation data does not override libc printability.
- Before measurement succeeds or drawing begins, check every native group (one
  positive-width scalar plus subsequent zero-width scalars) by exact
  `setcchar`/`getcchar` round-trip. Reject unrepresentable groups, including an
  excessive combining suffix, even beyond a clip budget. The entire grapheme may
  contain many native groups. This avoids curses' silent truncation of a group.
- `textinfo` and `spansclip` retain the longest prefix ending at a complete unit.
  The first non-fitting unit and everything after it are omitted. They insert no
  padding. The window's right edge is an additional budget for `spansclip`.
  `spans` requires all units to fit. Byte/column hits return the whole unit;
  the end offset returns the existing empty end range.
- For spans, concatenate the text conceptually before segmentation. Each span
  must contain complete encoded scalars; a UTF-8 scalar split between spans fails.
  Every native cell of a unit uses the complete style of its **first scalar**.
  Later styles apply when a new unit starts. All styles are validated, even those
  ignored within a unit or clipped away. No source text is discarded or duplicated.
- Safe `string` accepts printable single-row text and uses current window
  attributes/color. It preflights fit and then advances by the measured native
  width. An exact row-end advances to column zero of the next row; an exact
  bottom-right ending fails before writing. It never implicitly scrolls or wraps
  excess text. Spaces are literal, as in spans; inherited background-character
  substitution applies only to legacy `string`. Background and current style are
  preserved. `spans`/`spansclip` continue preserving the cursor.

Status **0** means success, **1** invalid input, limits, geometry, assignment or
curses operation failure, and **2** unsupported policy/backend/locale or a native
group that cannot be represented exactly. Unknown policy names return 2.
Validation failures leave query destinations, window cells and cursor unchanged.
Normal curses write failures retain the existing operation's failure semantics;
this is not a transactional renderer. Validated color pairs can remain cached
if a later allocation fails, as for legacy spans.

## Layout integration and retained-screen limits

A layout engine must implement **this** boundary profile, scalar validation and
width sum, and use matching libc widths and locale. The policy name pins Unicode
boundaries but cannot pin another machine's libc character tables; the locale
name alone cannot prove equality either. Compare representative `textinfo` /
`textpos` results, and handle per-text native-storage rejection. An engine using
`unicode-17.0.0-egc-max-wcwidth-emoji2` must explicitly switch width models before
using this backend. zdraw rejects that policy name; it never silently substitutes
the sum policy.

Padding begins at `textinfo[width]`. Snapshots and `cellinfo` expose ordinary
native cells: woman+ZWJ at one native base and laptop at another, followed by X
at column four for `👩‍💻X` starting at zero. Wide continuation cells still appear
in snapshots; use the existing occupancy metadata when reconstructing text.
There is no new snapshot format or synthetic two-cell occupancy. Native copy,
staging, presentation and non-cutting resize retain these same cells and styles.

The policy protects text supplied to **one opted-in call**. It does not discover
boundaries in previously retained text or across separate calls. Callers must
align edit/overwrite origins and region edges using their source text and
`textpos`. A later cell-based overwrite, partial region copy, viewport cut,
restyle or shrinking resize can cut an earlier multi-cell grapheme. Native wide
character repair also remains in effect. `prepare`/`draw`, `textwrap`, companion
UI reflow and the narrow-only `zdraw-screen-save` serializer retain their existing
contracts; this work does not advertise those as safe-policy operations.

Actual terminal glyph shaping can still disagree with curses' logical advance,
including for emoji and scripts with shaping. Tests establish agreement between
queries and retained native cells, not pixel placement in every terminal.
Exact two-cell emoji, independent styles within a grapheme and persistent
cluster-aware region operations require a separate rendering architecture
proposal. That proposal is outside this task. The native API's constraints are
described in the official [complex-character documentation](https://invisible-island.net/ncurses/man/curs_getcchar.3x.html).

## Verification

`tests/test_text_policy.py` and `tests/text-policy.zsh` cover native window writes,
all clip budgets for representative combining/modifier/flag/keycap/ZWJ sequences,
cross-style segmentation, cursor advances, padding, snapshots, full-region copy,
staged presentation, resize, suspend/resume, atomic validation failure and
unsupported build/locale discovery. The existing Unicode test retains all 766
pinned official segmentation cases. Run through the documented matching-source
build with `ZSH_BUILD_ROOT=/path/to/zsh-source make test`.
