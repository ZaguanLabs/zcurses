# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../../LICENCE
function zdraw-list {
  emulate -L zsh
  [[ $# -ge 7 && ${(t)zdraw_ui_list} == association* ]] || { _zdraw_ui_error 1 "${(%):-%N}" "requires window row column height width focus -- items and a zdraw_ui_list association"; return $?; }
  [[ ${(t)zdraw_ui_theme} == association* ]] || { _zdraw_ui_error 1 "${(%):-%N}" "requires a zdraw_ui_theme association"; return $?; }
  local _zui_win=$1 _zui_focus=$6 _zui_label _zui_state _zui_empty_text='No items'
  [[ $_zui_focus == (focus|inactive|disabled) ]] || { _zdraw_ui_error 1 "${(%):-%N}" "expected focus, inactive or disabled; got ${(qqq)_zui_focus}"; return $?; }
  local -i _zui_y _zui_x _zui_h _zui_w _zui_i _zui_row _zui_s _zui_first _zui_col _zui_width _zui_count
  local -A zdraw_ui_style _zui_normal _zui_selected _zui_empty _zui_info _zui_current
  local -a _zui_items _zui_tokens=(fg=text bg=surface px=0 selected:bg=selection
    selected:fg=on-selection selected:bold selected+inactive:bg=inactive
    selected+inactive:fg=on-inactive empty:fg=muted
    disabled:bg=surface disabled:fg=muted disabled:no-bold disabled:no-reverse)
  _zdraw_ui_rect "${@:1:5}" || return
  shift 6
  while (( $# )) && [[ $1 != -- ]]; do
    case $1 in
      empty-text=*) _zui_empty_text=${1#*=} ;;
      *) _zui_tokens+=("$1") ;;
    esac
    shift
  done
  (( $# )) || { _zdraw_ui_error 1 "${(%):-%N}" "missing -- before items"; return $?; }
  shift
  _zui_items=("$@") _zui_count=$#
  (( _zui_count <= 32767 )) || { _zdraw_ui_error 1 "${(%):-%N}" "at most 32767 items are allowed"; return $?; }
  _zdraw_ui_uint "${zdraw_ui_list[selected]-}" && _zdraw_ui_uint "${zdraw_ui_list[first]-}" || { _zdraw_ui_error 1 "${(%):-%N}" "selected and first must be integers from 0 to 32767; initialize with zdraw-list-update"; return $?; }
  _zui_s=$((10#$zdraw_ui_list[selected])) _zui_first=$((10#$zdraw_ui_list[first]))
  (( _zui_first >= 1 && ((_zui_count == 0 && _zui_s == 0 && _zui_first == 1) ||
     (_zui_count > 0 && _zui_s >= 1 && _zui_s <= _zui_count && _zui_first <= _zui_count)) )) || { _zdraw_ui_error 1 "${(%):-%N}" "selection is outside the current data; reconcile with zdraw-list-update"; return $?; }
  if [[ ${zdraw_ui_theme[profile]-} == mono ]]; then
    # Insert before instance utilities so an explicit no-reverse can override.
    _zui_tokens=(selected:reverse "${_zui_tokens[@]}")
  fi
  # Validate text even offscreen, before clearing retained content. Bound total
  # character count to prevent an unbounded validation pass per draw.
  local -i _zui_total=0
  for _zui_label in "$_zui_empty_text" "${_zui_items[@]}"; do
    (( _zui_total += ${#_zui_label} ))
    (( _zui_total <= 262144 )) || { _zdraw_ui_error 1 "${(%):-%N}" "list text exceeds 262144 characters"; return $?; }
    zdraw textinfo _zui_info "$_zui_label" || { _zdraw_ui_error $? "${(%):-%N}" 'native textinfo failed'; return $?; }
  done
  for _zui_state in "$_zui_focus" "selected,$_zui_focus" "empty,$_zui_focus"; do
    zdraw-ui-style "$_zui_state" "${_zui_tokens[@]}" || return
    # Lists are content regions. Compose with a panel for a titled border.
    [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[py] == 0 ]] || { _zdraw_ui_error 1 "${(%):-%N}" "lists require border=none and py=0"; return $?; }
    case $_zui_state in
      selected,*) _zui_selected=("${(@kv)zdraw_ui_style}") ;;
      empty,*) _zui_empty=("${(@kv)zdraw_ui_style}") ;;
      *) _zui_normal=("${(@kv)zdraw_ui_style}") ;;
    esac
  done
  zdraw fill "$_zui_win" "$_zui_y" "$_zui_x" "$_zui_h" "$_zui_w" "$_zui_normal[style]" ' ' || { _zdraw_ui_error $? "${(%):-%N}" 'native fill failed'; return $?; }
  if (( ! _zui_count )); then
    _zdraw_ui_row "$_zui_win" "$_zui_y" "$((_zui_x+_zui_empty[px]))" "$((_zui_w-2*_zui_empty[px]))" "$_zui_empty[align]" "$_zui_empty_text" "$_zui_empty[style]"
    return
  fi
  for (( _zui_row=0, _zui_i=_zui_first; _zui_row<_zui_h && _zui_i<=_zui_count; _zui_row++, _zui_i++ )); do
    _zui_label="  $_zui_items[$_zui_i]"
    _zui_current=("${(@kv)_zui_normal}")
    if (( _zui_i == _zui_s )); then
      _zui_label="> $_zui_items[$_zui_i]"
      _zui_current=("${(@kv)_zui_selected}")
      zdraw fill "$_zui_win" "$((_zui_y+_zui_row))" "$_zui_x" 1 "$_zui_w" "$_zui_current[style]" ' ' || { _zdraw_ui_error $? "${(%):-%N}" 'native fill failed'; return $?; }
    fi
    _zui_col=$(( _zui_x + _zui_current[px] ))
    _zui_width=$(( _zui_w - 2 * _zui_current[px] ))
    _zdraw_ui_row "$_zui_win" "$((_zui_y+_zui_row))" "$_zui_col" "$_zui_width" "$_zui_current[align]" "$_zui_label" "$_zui_current[style]" || return
  done
  return 0
}
