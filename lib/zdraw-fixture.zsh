# Passive export loader; only an explicit capture reads the native window.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h}/ui/core.zsh" || return
  builtin source "${1:A:h}/ui/fixture.zsh"
} "${(%):-%x}"
