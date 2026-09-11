# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../LICENCE
# Passive numeric-series and projection helpers; no terminal is required.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h}/ui/core.zsh" || return
  builtin source "${1:A:h}/ui/chart.zsh"
} "${(%):-%x}"
