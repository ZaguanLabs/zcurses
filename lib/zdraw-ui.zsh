# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../LICENCE
# Passive loader. Parse implementation files with aliases disabled, without
# changing the caller's options or retaining a path to this checkout.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h}/ui/core.zsh"
} "${(%):-%x}"
