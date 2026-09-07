# Project guidance

- Improve zcoder first through general-purpose Zsh/curses primitives. Keep
  application layouts, command palettes and agent concepts out of the C module.
- Use the local Zsh documentation at
  `~/dev/ai/zaguan/PowerHouse/inspiration/zsh/zsh_html/`.
- Preserve the recorded original sources in `upstream/` and their licence headers.
- Build in `.build/`; never overwrite the installed module or supplied source tree
  as part of a normal build or test.
- Use the Zsh expertise skill for Zsh code. Run `make test` with `ZSH_BUILD_ROOT`
  pointing to the matching configured source tree after code changes.
- Preserve existing `zcurses` command behavior. New terminal protocols must be
  opt-in and must have explicit input ownership and cleanup behavior.
