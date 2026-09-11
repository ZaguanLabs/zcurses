# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../../LICENCE
function zdraw-help {
  emulate -L zsh
  (( $# >= 6 )) || return 1
  local _zui_win=$1 _zui_states=$5 _zui_part _zui_text
  local -i _zui_y _zui_x _zui_h _zui_w _zui_i _zui_width _zui_offset=0 _zui_total=0
  local -A zdraw_ui_style _zui_info _zui_styles
  local -a _zui_tokens=(fg=muted bg=canvas key:fg=accent key:bold) _zui_items _zui_widths
  _zdraw_ui_rect "$1" "$2" "$3" 1 "$4" || return
  shift 5
  while (( $# )) && [[ $1 != -- ]]; do _zui_tokens+=("$1"); shift; done
  (( $# )) || return 1
  shift
  (( $# % 2 == 0 && $# <= 64 )) || return 1
  _zui_items=("$@")
  for _zui_text in "${_zui_items[@]}"; do
    (( _zui_total += ${#_zui_text} ))
    (( _zui_total <= 262144 )) || return 1
    zdraw textinfo _zui_info "$_zui_text" || return
    _zui_widths+=("$_zui_info[width]")
  done
  for _zui_part in label key; do
    zdraw-ui-style "$_zui_states,$_zui_part" "${_zui_tokens[@]}" || return
    [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[px] == 0 && $zdraw_ui_style[py] == 0 && $zdraw_ui_style[align] == left ]] || return 1
    _zui_styles[$_zui_part]=$zdraw_ui_style[style]
  done
  zdraw fill "$_zui_win" "$_zui_y" "$_zui_x" 1 "$_zui_w" "$_zui_styles[label]" ' ' || return
  for (( _zui_i=1; _zui_i<=${#_zui_items}; _zui_i+=2 )); do
    _zui_width=$(( _zui_widths[_zui_i]+1+_zui_widths[_zui_i+1] ))
    (( _zui_offset+_zui_width <= _zui_w )) || break
    zdraw spans "$_zui_win" "$_zui_y" "$((_zui_x+_zui_offset))" \
      "$_zui_styles[key]" "$_zui_items[$_zui_i]" "$_zui_styles[label]" " $_zui_items[$((_zui_i+1))]" || return
    (( _zui_offset += _zui_width+2 ))
  done
  return 0
}
