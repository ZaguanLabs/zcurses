# Image previews

The optional image adapter converts a PNG or JPEG into a small retained mosaic.
Zsh draws it using ordinary curses cells: colored half blocks where available,
ASCII density characters otherwise. Conversion is separate from drawing and is
never an implicit core-module dependency. Native terminal image placement remains
research, with the measured limits below.

## Try the preview

Build using the [public-source instructions](../README.md#build-and-test). The
converter requires Python 3 and ImageMagick 7's `magick` command; drawing a saved
raster needs neither of those programs. The verified converter is ImageMagick
7.1.2-27 Q16-HDRI on Linux. Other versions and operating systems need verification.

```zsh
# Optional reproducible sample; all generated files stay in .build/.
magick -size 160x96 'gradient:#183650-#efb76d' .build/preview.png
.build/zsh/Src/zsh -df examples/image-preview.zsh .build/preview.png
```

The example converts once before initializing curses. `g` switches between
automatic glyphs and ASCII; `m` switches image colors to the theme; `s` exercises
suspend/resume; `q` or Escape exits. Resize crops the retained image and clears the
remaining viewport; it does not invoke the converter again. An unavailable
converter or rejected input produces an `[Image unavailable]` placeholder. The
example uses a fixed caption, so a filename cannot become terminal control text.

## Compose it with an application

Source the passive loader, load the native module using your matching shell's
module path, and declare caller-owned state:

```zsh
source lib/zdraw-image.zsh
typeset -A zdraw_ui_image zdraw_ui_theme
typeset -a reply
typeset packet

# Run this before taking terminal ownership, or in a caller-owned worker.
packet=$(python3 scripts/image-preview.py --rows 16 --columns 64 -- image.png) || return
zdraw-image-load "$packet" 'Sunset over the coast' || return
zdraw-image-rows || return
# reply contains printable ASCII rows, also usable after module unload.

# Inside an initialized session, after choosing a theme:
zdraw-ui-theme dark 16
zdraw-image-draw stdscr 2 2 16 64 normal palette=auto colors=image
```

Public calls:

| Call | Behavior |
| --- | --- |
| `zdraw-image-load packet alt-text` | Validates complete data and atomically replaces `zdraw_ui_image`; failure preserves its prior value. Requires native text validation. |
| `zdraw-image-rows` | Validates the retained raster and replaces caller-owned `reply` with ASCII density rows. Does not require an initialized or loaded module. |
| `zdraw-image-draw win y x rows columns state [tokens...]` | Validates data, geometry and tokens before drawing; clears the viewport, then crops the raster from its upper-left corner. Preserves the window's cursor and current style. Does not present. |

Use `palette=auto`, `ascii` or `block`, and `colors=image` or `theme`. Automatic
mode selects half blocks only when a one-column block character and at least
16 colors are available. A monochrome theme, `NO_COLOR`, insufficient colors or
an ASCII-only build selects ASCII. Explicit `palette=block` returns status 2 when
unsupported. Invalid input returns 1. Native allocation/write errors retain the
native partial-write behavior; a multirow drawing operation is not transactional.

Normal style tokens such as `fg=accent`, `bg=surface`, `bold` and state variants
apply. `colors=theme` uses the resolved foreground/background and ASCII density.
Image-colored ASCII uses the upper pixel's palette color and the resolved
background. Half blocks use the upper/lower pixel colors as foreground/background.
Borders, padding and alignment belong in an enclosing panel/layout; the renderer
rejects those tokens rather than silently ignoring them.

The retained association has `format=zdraw-image-1`, `rows`, `columns`, `alt`, and
one `N,pixels` hexadecimal string for each pixel row, numbered from 1. There are
two pixel rows per terminal row. The reader revalidates dimensions and every
pixel before arithmetic or drawing. Applications can keep multiple associations
and bind the desired one through normal Zsh dynamic scope. `_zi_*` and `_zui_*`
names are reserved implementation locals. Loaded data owns no native resources,
descriptors, worker, input reader, timer or protocol state.

## Conversion contract

The converter writes only a complete ASCII packet to stdout:

```text
zdraw-image-1 1 4
0123
cdef
```

The header gives terminal rows and columns. Exactly twice that many pixel rows
follow, each containing exactly `columns` lowercase hexadecimal palette indices.
One final newline is accepted. Extra records, controls, missing pixels and invalid
indices are rejected. The packet is data; never `source` or `eval` it.

| Resource | Bound or policy |
| --- | --- |
| Input | Regular file, at most 8 MiB. Snapshot read before conversion; pipes/devices rejected. Filenames never enter ImageMagick's command grammar. |
| Formats | PNG and baseline/progressive JPEG with valid dimension headers; first image only. No animation, SVG, PDF, URLs or automatic delegate formats. |
| Source geometry | At most 4096 pixels per side and 4,194,304 pixels total, checked before decoding. |
| Output geometry | 1–64 terminal rows, 1–128 columns, at most 4096 cells / 8192 sampled pixels. |
| Converter output | Exactly six RGB bytes per terminal cell; at most 24,576 bytes. Supervisor reads no more than this budget plus one byte before rejecting excess output. |
| Packet | At most 8500 characters accepted by the loader. Converter output is smaller than this bound. |
| Alt text | Required, nonempty printable text, at most 256 encoded bytes. The caller chooses where to display it. |
| Palette | Fixed 16 RGB targets, nearest squared RGB distance, no dithering. Terminal indices 0–15 may differ from those targets under user-customized terminal palettes. |
| Color pairs | At most 256 ordered foreground/background combinations for half blocks, or 16 image foregrounds per chosen ASCII background. Warm redraws reuse cached pairs. |
| Time | One five-second converter deadline; timeout kills and reaps the owned process group. |
| Decoder policy | 128 MiB pixel-cache budget, no mapped/disk cache, one thread, five-second internal time limit, four-image internal list limit. Decoder operations can need temporary images; only frame zero is requested. |
| Cleanup | Private temporary directory, removed on success, failure, SIGINT or SIGTERM. No output packet on conversion failure/cancellation. Exit 130/143 for those signals. |

The supervisor passes a fixed local snapshot with an explicit PNG/JPEG coder to
ImageMagick, disables delegates and filters, and permits only PNG/JPEG reads and
RGB writes in its private policy. These controls build on ImageMagick's
[security-policy facilities](https://imagemagick.org/security-policy/). Existing
stricter system limits can still reject a conversion. The pixel-cache limit is
not a whole-process resident-memory guarantee or an OS sandbox.

Images are auto-oriented, flattened onto black, converted to sRGB, scaled to fit
the sampled pixel rectangle and centered with black padding. The geometry assumes
roughly two square image pixels per terminal cell vertically. Unusual font/cell
aspect ratios need caller-selected dimensions. Color management, transparency,
photographic detail and terminal palette customization can affect fidelity.

Keep conversion out of a drawing callback. The example is deliberately synchronous
before curses starts. An application that needs asynchronous previews owns its
worker, cancellation and request identity, then calls `zdraw-image-load` only for
the current completed request. Discard stale results. Closing a consumer pipe
alone is not a worker-cancellation API. Forced termination cannot run cleanup.

## Native placement research

The [private-terminal fixture](../scripts/portability/image-source.zsh) explores
kitty Unicode placeholders using one 64×32 RGB image and an 8×4-cell virtual
placement. The protocol encodes image identity through foreground color and
combining marks on U+10EEEE. It defines quiet transfers, explicit row/column
diacritics, and deletion by image ID. See the
[official graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
and its [coordinate table](https://sw.kovidgoyal.net/kitty/_downloads/f0a0de9ec8d9ff4456206db8e0814937/rowcolumn-diacritics.txt).

This is an explicitly invoked fixture for **fresh private terminals only**. It
reserves image ID 33554474; it is not safe to reserve that ID in an arbitrary
shared terminal. It emits only its own upload/delete packets and makes no claims
about discovering support from `TERM`. Curses owns the screen; a separate FIFO
carries test acknowledgements through `sysread`. Quiet graphics packets request
no terminal responses, and no second terminal input reader is installed.

The fixture includes upload, forced redraw, a horizontally cropped copy to a new
row, opaque covering cells, replacement, actual terminal-window resize,
delete-before-suspend, upload-after-resume, an interrupted multi-chunk transfer,
quiet completion/deletion of that transfer, reupload, delete-before-end and
module unload. Its `always` path deletes the owned image and restores curses on
ordinary errors/signals. The interrupted case stops after a complete `m=1` APC
chunk; it does not simulate termination halfway through an escape sequence.

Reproduce the optional visual matrix with Xvfb, Kitty, xterm, ImageMagick's
`import`, Python/Pillow and any multiplexers being tested:

```zsh
python3 scripts/portability/image-matrix.py --run-private-terminals \
  --output .build/image-matrix.json --captures .build/image-captures
```

Only newly created X displays and private multiplexer sessions are controlled.
The tmux profile uses DCS wrapping and quietly requests `allow-passthrough` where
supported; older builds predate that option. This follows the
[tmux passthrough guidance](https://github.com/tmux/tmux/wiki/FAQ).
The Screen profile uses a 256-color terminfo name and direct APC transmission;
no Screen-specific transport adapter is implemented.

The [recorded matrix](portability/image-matrix-2026-09-10.json) and its captures
are the evidence for the decision below. Pixel counts identify exact colors in
the generated test image; they are not a general image-quality comparison.
Native readback and visual pixels are recorded separately. The tested ncurses
complex cell preserves the base plus all three coordinate/identity marks, and
each eight-cell row measures eight columns. This says nothing about other curses
implementations, underline-color placement IDs, or unrestricted placeholder grids.

| Recorded profile | Visible result |
| --- | --- |
| Kitty 0.44.0 | Image visible initially and after redraw/copy; opaque cells cover it; replacement, resize and resume visible. Reupload after interrupted transfer remains invisible. |
| Kitty 0.44.0 through tmux `next-3.3` | Initial display, redraw/copy, cover, replacement and resize visible. Image absent after suspend/resume and after interrupted-transfer reupload. |
| Kitty through Screen 5.0.1, direct APC | No test-image pixels observed. This does not evaluate a future Screen-specific passthrough adapter. |
| XTerm(407), `xterm-256color` | No test-image pixels observed. |

All four profiles retain the complete coordinates in native readback. All have
zero test-image pixels at suspended, ended and unloaded capture points. The final
direct-Kitty run counts 1296 exact red pixels initially, 2268 after the cropped
copy, and 1782 with covering cells. Earlier runs intermittently had no initial
image until the copy forced another update; the final capture includes a two-second
initial settling interval. These observations cannot establish deterministic
readiness from quiet transmission alone. See the
[copy capture](portability/image-captures/kitty-scrolled.png),
[cover capture](portability/image-captures/kitty-overlay.png), and
[tmux copy capture](portability/image-captures/kitty-tmux-scrolled.png).

**Decision:** ship the text preview and retain native placement as research.
Curses does not own an image-resource registry or cleanup hooks, and quiet uploads
provide no acknowledged readiness/error channel. The fixture cannot yet guarantee
reliable first display or recovery after an incomplete transfer. Multiplexer
behavior also needs a defined, verified transport and cell-preservation contract.
Native `suspend`, `end` and unload cannot delete resources they do not know exist;
the fixture performs that coordination explicitly. Zero visible image pixels
after cleanup does not prove that a terminal has released every cached byte.

A future native proposal must resolve image identity, acknowledged upload/error
ownership, placement metadata, dirty-cell repainting, interruption recovery and
session cleanup together. Emitting graphics escapes alone is not that API. The
portable mosaic remains the application's usable preview when support is missing
or uncertain.
