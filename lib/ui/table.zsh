# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../../LICENCE
function zdraw-table-update {
  emulate -L zsh
  [[ ${(t)zdraw_ui_table} == (association|association-local) ]] || { _zdraw_ui_error 1 "${(%):-%N}" "requires a writable zdraw_ui_table association"; return $?; }
  local -A zdraw_ui_list=("${(@kv)zdraw_ui_table}")
  zdraw-list-update "$@" || return
  zdraw_ui_table=("${(@kv)zdraw_ui_list}")
}

function zdraw-table {
  emulate -L zsh
  [[ $# -ge 7 && ${(t)zdraw_ui_table} == association* &&
     ${(t)zdraw_ui_theme} == association* && ${(t)zdraw_ui_headers} == array* &&
     ${(t)zdraw_ui_tracks} == array* ]] || { _zdraw_ui_error 1 "${(%):-%N}" "requires rectangle focus -- cells, zdraw_ui_table/theme associations and zdraw_ui_headers/tracks arrays"; return $?; }
  local _zui_win=$1 _zui_focus=$6 _zui_empty_text='No rows' _zui_header=on
  local _zui_text _zui_group _zui_field _zui_align
  local -i _zui_y _zui_x _zui_h _zui_w _zui_gap=1 _zui_ncols=${#zdraw_ui_headers}
  local -i _zui_count _zui_s _zui_first _zui_marker _zui_row _zui_i _zui_j _zui_index _zui_total=0
  local -A zdraw_ui_layout zdraw_ui_style _zui_styles _zui_info
  local -a reply _zui_cells _zui_alignments _zui_tokens=(fg=text bg=surface
    alternate:bg=canvas selected:bg=selection selected:fg=on-selection selected:bold
    selected+inactive:bg=inactive selected+inactive:fg=on-inactive
    header:fg=accent header:bold empty:fg=muted
    disabled:bg=surface disabled:fg=muted disabled:no-bold disabled:no-reverse)
  [[ $_zui_focus == (focus|inactive|disabled) ]] || { _zdraw_ui_error 1 "${(%):-%N}" "expected focus, inactive or disabled; got ${(qqq)_zui_focus}"; return $?; }
  (( _zui_ncols >= 1 && _zui_ncols <= 32 && ${#zdraw_ui_tracks} == _zui_ncols )) || { _zdraw_ui_error 1 "${(%):-%N}" "requires 1 to 32 headers and one track per header"; return $?; }
  if (( ${+zdraw_ui_alignments} )); then
    [[ ${(t)zdraw_ui_alignments} == array* && ${#zdraw_ui_alignments} -eq _zui_ncols ]] || { _zdraw_ui_error 1 "${(%):-%N}" "zdraw_ui_alignments must be an array with one entry per header"; return $?; }
    _zui_alignments=("${zdraw_ui_alignments[@]}")
  else
    repeat $_zui_ncols; do _zui_alignments+=(inherit); done
  fi
  for _zui_align in "${_zui_alignments[@]}"; do
    [[ $_zui_align == (left|center|right|inherit) ]] || { _zdraw_ui_error 1 "${(%):-%N}" "unknown alignment ${(qqq)_zui_align}"; return $?; }
  done
  _zdraw_ui_rect "${@:1:5}" || return
  shift 6
  while (( $# )) && [[ $1 != -- ]]; do
    case $1 in
      empty-text=*) _zui_empty_text=${1#*=} ;;
      header=*) _zui_header=${1#*=}; [[ $_zui_header == (on|off) ]] || { _zdraw_ui_error 1 "${(%):-%N}" "expected header=on or header=off"; return $?; } ;;
      gap=*)
        _zui_text=${1#*=}
        _zdraw_ui_uint "$_zui_text" || { _zdraw_ui_error 1 "${(%):-%N}" "gap must be an integer from 0 to 16"; return $?; }
        (( 10#$_zui_text <= 16 )) || { _zdraw_ui_error 1 "${(%):-%N}" "gap must be from 0 to 16"; return $?; }
        _zui_gap=$((10#$_zui_text)) ;;
      *) _zui_tokens+=("$1") ;;
    esac
    shift
  done
  (( $# )) || { _zdraw_ui_error 1 "${(%):-%N}" "missing -- before cells"; return $?; }
  shift
  (( $# <= 32767 && $# % _zui_ncols == 0 )) || { _zdraw_ui_error 1 "${(%):-%N}" "at most 32767 cells are allowed, in complete rows"; return $?; }
  _zui_cells=("$@") _zui_count=$(( $# / _zui_ncols ))
  _zdraw_ui_uint "${zdraw_ui_table[selected]-}" && _zdraw_ui_uint "${zdraw_ui_table[first]-}" || { _zdraw_ui_error 1 "${(%):-%N}" "selected and first must be integers from 0 to 32767; initialize with zdraw-table-update"; return $?; }
  _zui_s=$((10#$zdraw_ui_table[selected])) _zui_first=$((10#$zdraw_ui_table[first]))
  (( _zui_first >= 1 && ((_zui_count == 0 && _zui_s == 0 && _zui_first == 1) ||
     (_zui_count > 0 && _zui_s >= 1 && _zui_s <= _zui_count && _zui_first <= _zui_count)) )) || { _zdraw_ui_error 1 "${(%):-%N}" "selection is outside the current data; reconcile with zdraw-table-update"; return $?; }
  for _zui_text in "$_zui_empty_text" "${zdraw_ui_headers[@]}" "${_zui_cells[@]}"; do
    (( _zui_total += ${#_zui_text} ))
    (( _zui_total <= 262144 )) || { _zdraw_ui_error 1 "${(%):-%N}" "table text exceeds 262144 characters"; return $?; }
    zdraw textinfo _zui_info "$_zui_text" || { _zdraw_ui_error $? "${(%):-%N}" 'native textinfo failed'; return $?; }
  done
  [[ ${zdraw_ui_theme[profile]-} == mono ]] && _zui_tokens=(selected:reverse "${_zui_tokens[@]}")
  # Resolve every row kind before touching retained cells. Alternation follows
  # source row numbers, so scrolling does not change a row's appearance.
  for _zui_group in normal alternate selected selected,alternate header empty; do
    zdraw-ui-style "$_zui_group,$_zui_focus" "${_zui_tokens[@]}" || return
    [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[py] == 0 ]] || { _zdraw_ui_error 1 "${(%):-%N}" "tables require border=none and py=0"; return $?; }
    for _zui_field in "${(@k)zdraw_ui_style}"; do
      _zui_styles[$_zui_group,$_zui_field]=$zdraw_ui_style[$_zui_field]
    done
  done
  _zui_marker=$(( _zui_w < 2 ? _zui_w : 2 ))
  zdraw-layout-split 0 0 1 "$((_zui_w-_zui_marker))" columns "$_zui_gap" "${zdraw_ui_tracks[@]}" || return
  zdraw fill "$_zui_win" "$_zui_y" "$_zui_x" "$_zui_h" "$_zui_w" "$_zui_styles[normal,style]" ' ' || { _zdraw_ui_error $? "${(%):-%N}" 'native fill failed'; return $?; }
  _zui_row=$_zui_y
  if [[ $_zui_header == on ]]; then
    _zui_group=header _zui_i=0
    _zdraw_ui_table_row || return
    (( _zui_row++ ))
  fi
  if (( ! _zui_count && _zui_row < _zui_y+_zui_h )); then
    zdraw fill "$_zui_win" "$_zui_row" "$_zui_x" 1 "$_zui_w" "$_zui_styles[empty,style]" ' ' || { _zdraw_ui_error $? "${(%):-%N}" 'native fill failed'; return $?; }
    _zdraw_ui_row "$_zui_win" "$_zui_row" "$((_zui_x+_zui_styles[empty,px]))" \
      "$((_zui_w-2*_zui_styles[empty,px]))" "$_zui_styles[empty,align]" "$_zui_empty_text" "$_zui_styles[empty,style]"
    return
  fi
  for (( _zui_i=_zui_first; _zui_i<=_zui_count && _zui_row<_zui_y+_zui_h; _zui_i++, _zui_row++ )); do
    _zui_group=normal
    (( _zui_i % 2 == 0 )) && _zui_group=alternate
    if (( _zui_i == _zui_s )); then
      if [[ $_zui_group == alternate ]]; then _zui_group=selected,alternate; else _zui_group=selected; fi
    fi
    _zdraw_ui_table_row || return
  done
  return 0
}

# Deliberate dynamic scope: compose one validated row using the table call's
# rectangles, data and style. Clip each cell before joining, so wide characters
# cannot consume a neighboring column. One native draw includes the background,
# marker and padding, including trailing space in an all-fixed layout.
function _zdraw_ui_table_row {
  emulate -L zsh
  local _zui_line=''
  local -i _zui_used=0 _zui_column _zui_width _zui_spaces
  if (( _zui_i > 0 && _zui_i == _zui_s )); then
    _zui_line='>' _zui_used=1
  fi
  for (( _zui_j=1; _zui_j<=_zui_ncols; _zui_j++ )); do
    _zui_column=$(( _zui_marker + zdraw_ui_layout[$_zui_j,column] + _zui_styles[$_zui_group,px] ))
    _zui_width=$(( zdraw_ui_layout[$_zui_j,width] - 2*_zui_styles[$_zui_group,px] ))
    (( _zui_width > 0 )) || continue
    if (( _zui_i == 0 )); then
      _zui_text=$zdraw_ui_headers[$_zui_j]
    else
      _zui_index=$(( (_zui_i-1)*_zui_ncols+_zui_j ))
      _zui_text=$_zui_cells[$_zui_index]
    fi
    zdraw textinfo _zui_info "$_zui_text" "$_zui_width" || { _zdraw_ui_error $? "${(%):-%N}" 'native textinfo failed'; return $?; }
    _zui_align=$_zui_alignments[$_zui_j]
    [[ $_zui_align == inherit ]] && _zui_align=$_zui_styles[$_zui_group,align]
    case $_zui_align in
      right) (( _zui_column += _zui_width - _zui_info[width] )) ;;
      center) (( _zui_column += (_zui_width - _zui_info[width]) / 2 )) ;;
    esac
    _zui_spaces=$(( _zui_column - _zui_used ))
    _zui_line+="${(pl:$_zui_spaces:: :):-}$_zui_info[text]"
    _zui_used=$(( _zui_column + _zui_info[width] ))
  done
  _zui_spaces=$(( _zui_w - _zui_used ))
  _zui_line+="${(pl:$_zui_spaces:: :):-}"
  zdraw spans "$_zui_win" "$_zui_row" "$_zui_x" "$_zui_styles[$_zui_group,style]" "$_zui_line" || {
    _zdraw_ui_error $? "${(%):-%N}" 'native spans failed'; return $?
  }
}
