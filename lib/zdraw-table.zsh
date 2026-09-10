# Passive table loader; shared state helpers do not load the list renderer.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h}/ui/core.zsh" || return
  builtin source "${1:A:h}/ui/layout.zsh" || return
  builtin source "${1:A:h}/ui/selection.zsh" || return
  builtin source "${1:A:h}/ui/table.zsh"
} "${(%):-%x}"
