# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../LICENCE
# Independently usable panel; the common styling helpers are its only dependency.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h}/ui/core.zsh" || return
  builtin source "${1:A:h}/ui/panel.zsh"
} "${(%):-%x}"
