# Baseline provenance

The baseline was recorded on 2026-09-07 from the distribution source package
`zsh-5.9.2-1.zen3.mga10`. That package identifies the historical origin; it is
not a build dependency.

The recorded `curses.c` and `mod_curses.yo` have also been verified byte-for-byte
against the public [Zsh 5.9.2 release](https://www.zsh.org/pub/zsh-5.9.2.tar.xz).
The release archive's SHA-256 is
`36fa734374b44783582cec09bcd67822e2f992c779ec1624ab5596df078d2f81`.
This verifies the two patch baselines, not the entirety of the original
distribution build or its installed binaries.

| Recorded file | Path in Zsh sources |
| --- | --- |
| `upstream/curses.c` | `Src/Modules/curses.c` |
| `upstream/mod_curses.yo` | `Doc/Zsh/mod_curses.yo` |
| `Src/Modules/curses.mdd` | `Src/Modules/curses.mdd` |
| `Src/Modules/curses_keys.awk` | `Src/Modules/curses_keys.awk` |
| `LICENCE` | `LICENCE` |

Run `sha256sum -c upstream/SHA256SUMS` from the project root to verify these
recorded files (or `shasum -a 256 -c upstream/SHA256SUMS` where appropriate).
The original source files, copyright headers and licence are retained.

The full Zsh source tree is a build dependency obtained separately; see the
[build instructions](../README.md#build-and-test). Consult the documentation
shipped with that release and the module documentation in `Doc/Zsh/mod_curses.yo`.
