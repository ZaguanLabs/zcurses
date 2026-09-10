# Passive, independently usable single-line editing and rendering.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h}/ui/core.zsh" || return
  builtin source "${1:A:h}/ui/input.zsh"
} "${(%):-%x}"
