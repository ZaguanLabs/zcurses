# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../LICENCE
# Forms compose fields; terminal ownership and keymaps belong to the application.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h}/zdraw-input.zsh" || return
  builtin source "${1:A:h}/ui/form.zsh"
} "${(%):-%x}"
