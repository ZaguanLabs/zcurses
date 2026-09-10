# Passive layout loader; coordinates are calculated without terminal access.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h}/ui/core.zsh" || return
  builtin source "${1:A:h}/ui/layout.zsh"
} "${(%):-%x}"
