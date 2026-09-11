# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../../LICENCE
function zdraw-badge {
  emulate -L zsh
  (( $# >= 6 )) || { _zdraw_ui_error 1 "${(%):-%N}" "expected window row column width text states [utilities ...]"; return $?; }
  [[ ${(t)zdraw_ui_theme} == association* ]] || { _zdraw_ui_error 1 "${(%):-%N}" "requires a zdraw_ui_theme association"; return $?; }
  local -a _zui_tokens=(fg=on-selection bg=selection bold align=center px=1)
  [[ ${zdraw_ui_theme[profile]-} == mono ]] && _zui_tokens+=(reverse)
  zdraw-label "${@:1:6}" "${_zui_tokens[@]}" "${@:7}"
}
