# zcurses

An experimental fork of Zsh's `zsh/curses` module, driven by the needs of
[zcoder.zsh](../../ai/zaguan/labs/zcoder.zsh/). The aim is a responsive, capable
terminal interface built from small, reusable primitives. Changes should also
be suitable for discussion with Zsh maintainers as independent patches.

The first extension is implemented and tested: **`zcurses geometry array`**
queries the controlling terminal's current rows and columns without a subprocess
or screen update. The remaining work is a [roadmap](docs/design.md).

## Build and test

This initial development harness uses a **configured, built Zsh source tree
matching the target shell**. It copies that tree into `.build/zsh`, overlays the
fork, and uses Zsh's own module build rules. It does not install anything.

```zsh
export ZSH_BUILD_ROOT=~/dev/mgarepo/zsh/BUILD/zsh-5.9.2-build/zsh-5.9.2
make test
```

The development tools are Zsh, Make, a C toolchain and dependencies matching that
build; Python 3 is used only by the PTY test driver. The source check pins this
first harness to the recorded baseline. Remove the disposable `.build` directory
before changing source trees or their build configuration.

The resulting module is `.build/modules/zsh/curses.so`. In a **fresh Zsh process**
with a controlling terminal, load it with:

```zsh
module_path=("$PWD/.build/modules" $module_path)
zmodload zsh/curses
typeset -a size
zcurses geometry size && print -r -- "$size[1] rows, $size[2] columns"
```

Prepending `module_path` does not replace a module already loaded in a shell.
This binary is for the matching local Zsh ABI; portability to other versions and
systems has not yet been tested.

## API

```text
zcurses geometry array
```

Returns a two-element array: **rows, columns**. It queries the controlling
terminal directly, works before `init` and after `end`, and leaves curses window
dimensions and terminal modes alone. There is no default output parameter.

| Status | Meaning |
| --- | --- |
| 0 | Dimensions assigned successfully |
| 1 | Query failed, a dimension was zero, assignment failed, or arguments were invalid |
| 2 | This build lacks `TIOCGWINSZ` |

A failed terminal query leaves the output parameter unchanged. Check the return
status before using it. `position stdscr array` continues to describe the curses
window; `geometry` describes the terminal, which may have changed independently.

The [upstream-format documentation](Doc/Zsh/mod_curses.yo) includes the extension.
The PTY tests exercise live resizing before curses processes input, zero-sized
terminals, local and readonly parameters, argument errors, operation before and
after curses, terminal-mode restoration, no controlling terminal, and existing
window/text/color/refresh operations.

## Source and patch workflow

- `Src/Modules/`: forked module sources, retaining Zsh's file layout.
- `Doc/Zsh/`: forked module documentation.
- `upstream/`: original C and documentation baselines, checksums and provenance.
- `.build/`: ignored configured source copy and locally loadable module.

Run `make -s patch > geometry.patch` to export the C and documentation changes as
a focused patch. See [provenance](upstream/README.md) for the exact starting point.
An upstream submission would also need tests adapted to Zsh's test harness and
review against the maintainers' current tree.

The local zcoder source now uses this query when available and keeps a cached
stock-module fallback. The installed system module remains unchanged. To run
zcoder with the experimental module from this project directory:

```zsh
zsh -dfc 'module_path=("$1" $module_path); shift; source "$@"' zcurses \
  "$PWD/.build/modules" ~/dev/ai/zaguan/labs/zcoder.zsh/zcoder.zsh \
  --workspace /path/to/project
```

Run the zcoder regression suite with both resize backends:

```zsh
ZCODER_TEST_CURSES_PATH="$PWD/.build/modules" \
  make -C ~/dev/ai/zaguan/labs/zcoder.zsh test
```

See the [integration notes](docs/design.md#first-zcoder-integration) for backend
selection and failure behavior. These changes are local development work.
