# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../../LICENCE
function zdraw-badge {
  emulate -L zsh
  (( $# >= 6 )) || return 1
  [[ ${(t)zdraw_ui_theme} == association* ]] || return 1
  local -a _zui_tokens=(fg=on-selection bg=selection bold align=center px=1)
  [[ ${zdraw_ui_theme[profile]-} == mono ]] && _zui_tokens+=(reverse)
  zdraw-label "${@:1:6}" "${_zui_tokens[@]}" "${@:7}"
}
