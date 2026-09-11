# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../LICENCE
# Passive component loader.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h}/ui/core.zsh" || return
  builtin source "${1:A:h}/ui/help.zsh"
} "${(%):-%x}"
