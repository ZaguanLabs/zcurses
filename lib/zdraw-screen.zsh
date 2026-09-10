# Passive loader: capture and restoration occur only on explicit calls.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h}/ui/screen.zsh"
} "${(%):-%x}"
