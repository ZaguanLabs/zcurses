# zcurses

A portable, general-purpose extension of Zsh's `zsh/curses` module. The project
preserves existing `zcurses` behavior and develops small, independently
reviewable changes for possible inclusion in the official Zsh distribution.
It has no dependency on another application or a contributor's local setup.

An example consumer is [zcoder.zsh](https://github.com/ZaguanLabs/zcoder.zsh).

The first extension, **`zcurses geometry array`**, queries the controlling
terminal's current rows and columns without a subprocess or screen update.
See the [design notes](docs/design.md) for scope and future work.

## Build and test

Prerequisites:

- Zsh to run the build script, GNU Make, a C compiler, and standard Unix build
  tools (including a POSIX shell, Awk, and Sed).
- Curses development headers and libraries, such as ncurses, and a terminfo
  database containing `xterm-256color` for the tests.
- Python 3.9 or newer for the PTY tests.
- Curl, Tar, and Xz for the download example below.

From this repository's root, download and extract a public
[Zsh release](https://www.zsh.org/pub/), then build:

```sh
mkdir -p .build/downloads .build/sources
curl -fL https://www.zsh.org/pub/zsh-5.9.2.tar.xz \
  -o .build/downloads/zsh-5.9.2.tar.xz
tar -xJf .build/downloads/zsh-5.9.2.tar.xz -C .build/sources
export ZSH_BUILD_ROOT="$PWD/.build/sources/zsh-5.9.2"
make test
```

The release archive's SHA-256 is
`36fa734374b44783582cec09bcd67822e2f992c779ec1624ab5596df078d2f81`,
as listed in the publisher's [checksums](https://www.zsh.org/pub/SHA256SUM).
Use `gmake` instead of `make` on systems where GNU Make has that name.

The build copies the supplied source tree to `.build/zsh`, overlays this module,
and uses Zsh's own configuration and build rules. It builds both the shell and
its modules; tests use that matching shell. All build products stay in `.build/`.
No installation, administrator access, or changes to the supplied tree are needed.
The tests create their own pseudo-terminal, so they also run without an
interactive terminal. `make build` builds without running tests.

An extracted release needs no prior configuration. Standard compiler environment
variables such as `CC`, `CPPFLAGS`, `CFLAGS`, and `LDFLAGS` can be set before the
first build, including paths to curses installed in a nonstandard location.
Alternatively, set `ZSH_BUILD_ROOT` to your own configured in-tree Zsh build
using relative source paths. Separate source/build trees are not supported by
the copy-based harness. Run `make clean` before changing sources or configuration;
it removes the working copy and staged module, preserving downloads and extracted
sources.

## Try the module

From the repository root, in a terminal, start the newly built shell:

```sh
.build/zsh/Src/zsh -df
```

Then run these Zsh commands:

```zsh
module_path=("$PWD/.build/modules")
zmodload zsh/curses
typeset -a size
zcurses geometry size && print -r -- "$size[1] rows, $size[2] columns"
```

The staged module is `.build/modules/zsh/curses.so` on systems using the `.so`
module suffix; the build uses the suffix selected by Zsh on other systems.
Type `exit` to leave the test shell.

To use the module in an existing Zsh installation, build against sources and
configuration matching that shell's ABI. In a fresh process, prepend the staged
module directory to `module_path` before `zmodload zsh/curses`. Changing
`module_path` does not replace an already loaded module. To test a particular
matching shell, run `ZSH_TEST_SHELL=/path/to/zsh make test` with `ZSH_BUILD_ROOT`
still set. A binary built for one Zsh configuration or operating system is not
a universal binary.

The public Zsh 5.9.2 release is the tested source baseline. The implementation
uses Zsh's platform configuration and curses abstractions; Linux is currently
verified, while BSD/macOS and alternative curses libraries still need testing.

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

## Source and upstream contribution

- `Src/Modules/`: forked module sources, retaining Zsh's file layout.
- `Doc/Zsh/`: module documentation in Zsh's native format.
- `upstream/`: preserved original sources, checksums and provenance.
- `tests/`: standalone module tests, with no application dependencies.
- `.build/`: ignored build inputs and outputs.

Run `make -s patch > geometry.patch` to export the C and documentation changes as
a focused patch against the recorded baseline. See [provenance](upstream/README.md)
for its origin. An upstream submission also needs tests adapted to Zsh's test
harness and review against the maintainers' current tree. This project is not
part of the official Zsh distribution.

The original copyright notices and [Zsh licence](LICENCE) are retained.
