# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../../LICENCE
function zdraw-tabs {
  emulate -L zsh
  (( $# >= 7 )) || return 1
  [[ ${(t)zdraw_ui_theme} == association* ]] || return 1
  _zdraw_ui_uint "$5" || return 1
  local _zui_win=$1 _zui_states=$6 _zui_part _zui_text _zui_field
  local -i _zui_y _zui_x _zui_h _zui_w _zui_selected=$((10#$5)) _zui_i _zui_total=0
  local -i _zui_first _zui_last _zui_used _zui_offset=0 _zui_width _zui_pad
  local -A zdraw_ui_style _zui_info _zui_styles
  local -a _zui_items _zui_widths _zui_tokens=(fg=muted bg=canvas px=1
    selected:fg=on-selection selected:bg=selection selected:bold
    selected+inactive:fg=on-inactive selected+inactive:bg=inactive
    disabled:fg=muted disabled:bg=canvas disabled:no-bold disabled:no-reverse)
  [[ $_zui_states == (focus|inactive|disabled) ]] || return 1
  _zdraw_ui_rect "$1" "$2" "$3" 1 "$4" || return
  shift 6
  while (( $# )) && [[ $1 != -- ]]; do _zui_tokens+=("$1"); shift; done
  (( $# )) || return 1
  shift
  _zui_items=("$@")
  (( $# <= 32 && (($# == 0 && _zui_selected == 0) || (_zui_selected >= 1 && _zui_selected <= $#)) )) || return 1
  [[ ${zdraw_ui_theme[profile]-} == mono ]] && _zui_tokens=(selected:reverse "${_zui_tokens[@]}")
  for _zui_part in normal selected; do
    zdraw-ui-style "$_zui_states,$_zui_part" "${_zui_tokens[@]}" || return
    [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[py] == 0 ]] || return 1
    for _zui_field in style px align; do _zui_styles[$_zui_part,$_zui_field]=$zdraw_ui_style[$_zui_field]; done
  done
  for (( _zui_i=1; _zui_i<=${#_zui_items}; _zui_i++ )); do
    _zui_text=$_zui_items[$_zui_i]
    (( _zui_total += ${#_zui_text} ))
    (( _zui_total <= 262144 )) || return 1
    zdraw textinfo _zui_info "$_zui_text" || return
    _zui_part=normal
    (( _zui_i == _zui_selected )) && _zui_part=selected
    _zui_width=$(( _zui_info[width]+2+2*_zui_styles[$_zui_part,px] ))
    _zui_widths+=("$((_zui_width < _zui_w ? _zui_width : _zui_w))")
  done
  zdraw fill "$_zui_win" "$_zui_y" "$_zui_x" 1 "$_zui_w" "$_zui_styles[normal,style]" ' ' || return
  (( _zui_selected )) || return 0
  _zui_first=$_zui_selected _zui_last=$_zui_selected _zui_used=$_zui_widths[$_zui_selected]
  while (( _zui_first > 1 && _zui_used+1+_zui_widths[_zui_first-1] <= _zui_w )); do
    (( _zui_first--, _zui_used += 1+_zui_widths[_zui_first] ))
  done
  while (( _zui_last < ${#_zui_items} && _zui_used+1+_zui_widths[_zui_last+1] <= _zui_w )); do
    (( _zui_last++, _zui_used += 1+_zui_widths[_zui_last] ))
  done
  for (( _zui_i=_zui_first; _zui_i<=_zui_last; _zui_i++ )); do
    _zui_part=normal _zui_text="  $_zui_items[$_zui_i]"
    if (( _zui_i == _zui_selected )); then _zui_part=selected _zui_text="> $_zui_items[$_zui_i]"; fi
    _zui_width=$_zui_widths[$_zui_i]
    _zui_pad=$(( _zui_styles[$_zui_part,px] < (_zui_width-1)/2 ? _zui_styles[$_zui_part,px] : (_zui_width-1)/2 ))
    zdraw fill "$_zui_win" "$_zui_y" "$((_zui_x+_zui_offset))" 1 "$_zui_width" "$_zui_styles[$_zui_part,style]" ' ' || return
    _zdraw_ui_row "$_zui_win" "$_zui_y" "$((_zui_x+_zui_offset+_zui_pad))" \
      "$((_zui_width-2*_zui_pad))" "$_zui_styles[$_zui_part,align]" "$_zui_text" "$_zui_styles[$_zui_part,style]" || return
    (( _zui_offset += _zui_width+1 ))
  done
  return 0
}
