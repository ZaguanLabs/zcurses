# Semantic documents

A document is structured content with stable block IDs, independent of its
current width and theme. The optional Zsh library compiles blocks into wrapped
rows, follows a source position through reflow, and paints a scrolling viewport.
Applications still own their layout, keymap, event loop and refreshes.

```zsh
source ./lib/zdraw-document.zsh
typeset -A zdraw_ui_theme zdraw_ui_document
zdraw-ui-theme dark 256
zdraw-document-init 60 \
  intro heading 'A place for good ideas' \
  body paragraph 'Structured content can adapt to the space available.' \
  first bullet 'Keep colors semantic and focus visible.' \
  sample code $'typeset -A zdraw_ui_theme\nzdraw-ui-theme dark 256'

# After initializing a window:
zdraw-document stdscr 2 4 12 60 normal heading:fg=accent code:bg=canvas
zdraw-document-scroll 12 page-down
# Width changes preserve a source position near the top of the viewport.
zdraw-document-reflow 40
zdraw-document-scroll 12 keep
zdraw-document stdscr 2 4 12 40 normal
```

The [reader example](../examples/document.zsh) combines documents with a chapter
sidebar, a responsive panel, dark/light themes and keyboard navigation. Run it
using `.build/zsh/Src/zsh -df examples/document.zsh` after the normal build.

## Blocks and wrapping

`zdraw-document-init columns [id kind text …]` replaces the caller-owned ordinary
writable `zdraw_ui_document` association. Function-local associations work too.
The loader is passive; compilation, reflow and scrolling work without `init`, a
terminal or an input stream. They require the module's text measurement APIs.

| Kind | Presentation and wrapping |
| --- | --- |
| `heading` | Accent color and bold; word wrapping. |
| `subheading` | Accent color and bold; a separate customizable role. |
| `paragraph` | Normal body text with word wrapping. |
| `bullet` | `- ` before the first row, two-space continuation indent; consecutive bullets have no spacer between them. |
| `quote` | `\| ` on each row and muted text. |
| `code` | Two-space indent, canvas background, cell wrapping with exact whitespace. |
| `separator` | A full-width ASCII rule; source text must be empty. |

Other block boundaries include one blank spacer row. Prefixes disappear below
three columns. Where a prefix is present, it consumes two columns of the width
budget. Role defaults can be overridden using utilities such as
`heading:no-bold`, `subheading:underline`, `quote:fg=accent`, `code:bg=surface`
and `separator:fg=muted`. `spacer:` styles the blank rows. The role joins the
caller's explicit states, so `focus+heading:underline` is also available.

Each line feed in source text starts a new logical line; empty and trailing
logical lines are preserved. Tabs, carriage returns, other controls and invalid
encoding are rejected. Word wrapping prefers the last ASCII space that fits,
retains that space, and falls back to a complete cell unit for long words. It
never collapses whitespace or adds hyphens. Code uses complete cell units only.
A unit wider than the available content budget returns status 2 rather than
splitting or dropping it. The previous document remains intact.

These are the native `textinfo`/`textpos` units: a positive-width character with
its following zero-width characters. They are not full Unicode grapheme clusters
or a shaping engine. Wide text requires the corresponding module support and a
suitable locale. Prefixes and separators are deliberately ASCII-compatible.

The format accepts 0–128 blocks, 1–32767 columns, at most 32767 source bytes per
block and 65536 source bytes in total, and at most 4096 compiled rows including
spacers. IDs must be unique, start with an ASCII letter or underscore, contain
only ASCII letters/digits/underscore/hyphen, and have at most 48 characters.
Empty documents are valid. Pass text as quoted arguments; no markup, URLs,
commands, escape sequences or shell expressions are interpreted.

## Reading and navigation

`zdraw-document-scroll visible-rows action [id]` updates the first visible row.
Actions: `keep`, `up`, `down`, `page-up`, `page-down`, `home`, `end`,
`next-heading`, `previous-heading`, and `anchor id`. Page moves overlap by one
row. Heading moves consider both heading kinds; missing next/previous headings
leave the reading position unchanged. An unknown named anchor fails atomically.
The viewport clamps to the final full page, so an anchor near the end may appear
below the top row. Zero visible rows is accepted for temporarily hidden views.

`zdraw-document-reflow columns` recompiles retained source and maps the old top
row's block and source byte to a new row. It replaces the document only after
successful compilation. Call `scroll visible-rows keep` afterward to clamp for a
changed viewport height. A changed width can move the reading position to the
start of a row containing the same source byte; it does not promise that the
same byte will stay at column zero. Blank spacers are anchored at their preceding
block's source end. Source block IDs and order remain stable through reflow.

The public association contains:

| Keys | Meaning |
| --- | --- |
| `format` | `zdraw-document-1`. |
| `columns`, `count`, `line_count`, `first` | Compiled width, source block count, row count, one-based first visible row. Empty documents use `first=1`. |
| `b,N,id`, `b,N,kind`, `b,N,text`, `b,N,line` | One-based source block identity, kind, original text, and first compiled row. |
| `N,text`, `N,role`, `N,block` | One-based compiled row text (including prefix), semantic role, and source block index. |
| `N,byte_start`, `N,byte_end` | Half-open byte range in the original source block. Prefixes are not source bytes; line-feed bytes are gaps between logical lines. Spacers have empty ranges. |

Treat compiled fields as read-only data and use the public actions to update
state. For changed source, initialize a new document and optionally navigate to
a saved block ID. Applications can use retained block IDs and source ranges to
build their own table of contents or other navigation affordances.

## Drawing contract

`zdraw-document window y x rows columns states [utilities …]` requires the draw
width to match the compiled width. It clears the viewport and paints visible
rows, retaining the native cursor and current attributes. It neither scrolls
state, refreshes, reads input nor takes ownership of terminal protocols.

Colors and attributes can vary by role. Geometry utilities must remain
`border=none`, `px=0`, `py=0`, `align=left`; compose with a panel or layout helper
for borders, outer padding and positioning. All role styles and row text are
validated before painting, including off-screen content. Like other toolkit
components, drawing is several native operations: a later native resource
failure can leave a partial paint.

Success is 0, invalid arguments/data/limits are 1, and insufficient width for a
complete unit is 2. Native unsupported-operation errors can also return 2.
Compilation/reflow failures preserve state; invalid drawing arguments preserve
the screen. Keep the compiled document between events, reflow when width changes,
and redraw when content, appearance or viewport changes.

This API supplies semantic block rendering and navigation. It does not parse
Markdown, provide inline rich-text spans, syntax highlighting, clickable links,
images or automatic terminal protocol negotiation. Those can be considered as
separate extensions based on applications that need them.
