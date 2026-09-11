# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../../LICENCE
function zdraw-help {
  emulate -L zsh
  (( $# >= 6 )) || { _zdraw_ui_error 1 "${(%):-%N}" "expected window row column width states [utilities ...] -- [key description ...]"; return $?; }
  local _zui_win=$1 _zui_states=$5 _zui_part _zui_text
  local -i _zui_y _zui_x _zui_h _zui_w _zui_i _zui_width _zui_offset=0 _zui_total=0
  local -A zdraw_ui_style _zui_info _zui_styles
  local -a _zui_tokens=(fg=muted bg=canvas key:fg=accent key:bold) _zui_items _zui_widths
  _zdraw_ui_rect "$1" "$2" "$3" 1 "$4" || return
  shift 5
  while (( $# )) && [[ $1 != -- ]]; do _zui_tokens+=("$1"); shift; done
  (( $# )) || { _zdraw_ui_error 1 "${(%):-%N}" "missing -- before help key/description pairs"; return $?; }
  shift
  (( $# % 2 == 0 && $# <= 64 )) || { _zdraw_ui_error 1 "${(%):-%N}" "expected at most 32 help key/description pairs"; return $?; }
  _zui_items=("$@")
  for _zui_text in "${_zui_items[@]}"; do
    (( _zui_total += ${#_zui_text} ))
    (( _zui_total <= 262144 )) || { _zdraw_ui_error 1 "${(%):-%N}" "help labels exceed 262144 characters"; return $?; }
    zdraw textinfo _zui_info "$_zui_text" || { _zdraw_ui_error $? "${(%):-%N}" "native textinfo failed"; return $?; }
    _zui_widths+=("$_zui_info[width]")
  done
  for _zui_part in label key; do
    zdraw-ui-style "$_zui_states,$_zui_part" "${_zui_tokens[@]}" || return
    [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[px] == 0 && $zdraw_ui_style[py] == 0 && $zdraw_ui_style[align] == left ]] || { _zdraw_ui_error 1 "${(%):-%N}" "help requires border=none, px=0, py=0 and align=left"; return $?; }
    _zui_styles[$_zui_part]=$zdraw_ui_style[style]
  done
  zdraw fill "$_zui_win" "$_zui_y" "$_zui_x" 1 "$_zui_w" "$_zui_styles[label]" ' ' || { _zdraw_ui_error $? "${(%):-%N}" "native fill failed"; return $?; }
  for (( _zui_i=1; _zui_i<=${#_zui_items}; _zui_i+=2 )); do
    _zui_width=$(( _zui_widths[_zui_i]+1+_zui_widths[_zui_i+1] ))
    (( _zui_offset+_zui_width <= _zui_w )) || break
    zdraw spans "$_zui_win" "$_zui_y" "$((_zui_x+_zui_offset))" \
      "$_zui_styles[key]" "$_zui_items[$_zui_i]" "$_zui_styles[label]" " $_zui_items[$((_zui_i+1))]" || { _zdraw_ui_error $? "${(%):-%N}" "native spans failed"; return $?; }
    (( _zui_offset += _zui_width+2 ))
  done
  return 0
}
