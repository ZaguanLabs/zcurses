function zdraw-meter {
  emulate -L zsh
  (( $# >= 7 )) || return 1
  _zdraw_ui_uint "$5" && _zdraw_ui_uint "$6" || return 1
  local -i _zui_value=$((10#$5)) _zui_total=$((10#$6))
  (( _zui_total > 0 && _zui_value <= _zui_total )) || return 1
  local _zui_win=$1 _zui_states=$7 _zui_fill='#' _zui_tile='-' _zui_label=on _zui_part _zui_text
  local -i _zui_y _zui_x _zui_h _zui_w _zui_bar _zui_filled _zui_label_width=0
  local -A zdraw_ui_style _zui_info _zui_styles _zui_align
  local -a _zui_tokens=(fg=border bg=surface filled:fg=accent label:fg=text label:align=right)
  _zdraw_ui_rect "$1" "$2" "$3" 1 "$4" || return
  shift 7
  for _zui_text in "$@"; do
    case $_zui_text in
      fill-char=*) _zui_fill=${_zui_text#*=} ;;
      empty-char=*) _zui_tile=${_zui_text#*=} ;;
      label=*) _zui_label=${_zui_text#*=}; [[ $_zui_label == (on|off) ]] || return 1 ;;
      *) _zui_tokens+=("$_zui_text") ;;
    esac
  done
  for _zui_text in "$_zui_fill" "$_zui_tile"; do
    [[ ${#_zui_text} == 1 ]] || return 1
    zdraw textinfo _zui_info "$_zui_text" || return
    [[ $_zui_info[width] == 1 ]] || return 1
  done
  for _zui_part in track filled label; do
    zdraw-ui-style "$_zui_states,$_zui_part" "${_zui_tokens[@]}" || return
    [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[px] == 0 && $zdraw_ui_style[py] == 0 ]] || return 1
    _zui_styles[$_zui_part]=$zdraw_ui_style[style]
    _zui_align[$_zui_part]=$zdraw_ui_style[align]
  done
  if [[ $_zui_label == on ]] && (( _zui_w >= 4 )); then
    _zui_label_width=$(( _zui_w < 5 ? _zui_w : 5 ))
  fi
  _zui_bar=$(( _zui_w-_zui_label_width ))
  _zui_filled=$(( _zui_bar*_zui_value/_zui_total ))
  if (( _zui_bar )); then
    zdraw fill "$_zui_win" "$_zui_y" "$_zui_x" 1 "$_zui_bar" "$_zui_styles[track]" "$_zui_tile" || return
    if (( _zui_filled )); then
      zdraw fill "$_zui_win" "$_zui_y" "$_zui_x" 1 "$_zui_filled" "$_zui_styles[filled]" "$_zui_fill" || return
    fi
  fi
  if (( _zui_label_width )); then
    _zui_text="$((100*_zui_value/_zui_total))%"
    zdraw fill "$_zui_win" "$_zui_y" "$((_zui_x+_zui_bar))" 1 "$_zui_label_width" "$_zui_styles[label]" ' ' || return
    _zdraw_ui_row "$_zui_win" "$_zui_y" "$((_zui_x+_zui_bar))" "$_zui_label_width" "$_zui_align[label]" "$_zui_text" "$_zui_styles[label]" || return
  fi
  return 0
}
