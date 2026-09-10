# Passive structured-document compiler, navigation and viewport renderer.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h}/ui/core.zsh" || return
  builtin source "${1:A:h}/ui/document.zsh"
} "${(%):-%x}"
