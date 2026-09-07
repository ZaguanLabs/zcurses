# Baseline provenance

Recorded on 2026-09-07 from the source tree supplied by the project owner:

```text
/home/stig/dev/mgarepo/zsh/BUILD/zsh-5.9.2-build/zsh-5.9.2
```

Installed shell: `zsh 5.9.2 (x86_64-mageia-linux-gnu)`.
Installed RPM: `zsh-5.9.2-1.zen3.mga10`.
Installed module: `/usr/lib64/zsh/5.9.2/zsh/curses.so`.
Matching source RPM also exists at:

```text
/home/stig/rpmbuild/repo/SRPMS/zsh-5.9.2-1.zen3.mga10.src.rpm
```

This is the supplied distribution build tree, not a verified pristine upstream
Git revision. Any distribution patches already present are part of this baseline.
No claim of a byte-for-byte reproducible system binary is made.

| Recorded file | Original path |
| --- | --- |
| `upstream/curses.c` | `Src/Modules/curses.c` |
| `upstream/mod_curses.yo` | `Doc/Zsh/mod_curses.yo` |
| `Src/Modules/curses.mdd` | `Src/Modules/curses.mdd` |
| `Src/Modules/curses_keys.awk` | `Src/Modules/curses_keys.awk` |
| `LICENCE` | `LICENCE` |

Run `sha256sum -c upstream/SHA256SUMS` from the project root to verify these
recorded files. The full configured tree is a local build dependency, not vendored
source. The original copyright headers and licence are retained.

For Zsh documentation, the project's reference is:

```text
~/dev/ai/zaguan/PowerHouse/inspiration/zsh/zsh_html/
```

The module text is in `Zsh-Modules.html#The-zsh_002fcurses-Module`; the separate
`The-zsh_002fcurses-Module.html` file in this copy is a redirect page.
