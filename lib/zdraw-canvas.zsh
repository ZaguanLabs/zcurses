# Passive loader: retained geometry, headless rasterization and optional drawing.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h}/zdraw-chart.zsh" || return
  builtin source "${1:A:h}/ui/canvas.zsh"
} "${(%):-%x}"
