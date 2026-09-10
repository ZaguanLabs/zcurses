# Passive loader: no clocks, timers, input ownership or native resources.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h}/ui/core.zsh" || return
  builtin source "${1:A:h}/ui/motion.zsh"
} "${(%):-%x}"
