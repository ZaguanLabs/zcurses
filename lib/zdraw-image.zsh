# Passive loader. Image decoding is an optional, separate process.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h}/zdraw-ui.zsh" || return
  builtin source "${1:A:h}/ui/image.zsh"
} "${(%):-%x}"
