# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../LICENCE
# Independently usable list; loading does not initialize a terminal or read input.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h}/ui/core.zsh" || return
  builtin source "${1:A:h}/ui/selection.zsh" || return
  builtin source "${1:A:h}/ui/list.zsh"
} "${(%):-%x}"
