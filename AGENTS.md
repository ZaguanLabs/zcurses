# Project guidance

- Develop a portable, general-purpose Zsh/curses module with changes suitable
  for consideration in the official Zsh distribution. Keep application layouts,
  command palettes and agent concepts out of the C module.
- Do not depend on a contributor's home directory, distribution build tree,
  installed module, or another application repository. Document reproducible
  setup using publicly available Zsh sources.
- Use the Zsh documentation shipped with the selected source release or the
  public manual at https://zsh.sourceforge.io/Doc/Release/.
- Preserve the recorded original sources in `upstream/` and their licence headers.
- Build in `.build/`; never overwrite the installed module or supplied source tree
  as part of a normal build or test.
- Use the Zsh expertise skill for Zsh code. Run `make test` with `ZSH_BUILD_ROOT`
  pointing to the selected Zsh source tree after code changes. Test against the
  shell built from that tree; loading into another shell requires a matching ABI.
- Preserve existing `zcurses` command behavior. New terminal protocols must be
  opt-in and must have explicit input ownership and cleanup behavior.
