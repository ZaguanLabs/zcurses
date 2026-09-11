# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../../LICENCE
# Pure rectangle validation. Unlike drawing, layout accepts empty rectangles.
# The caller supplies the _zui_y/x/h/w integer locals populated here.
function _zdraw_ui_layout_rect {
  emulate -L zsh
  (( $# == 4 )) || { _zdraw_ui_error 1 "${(%):-%N}" "expected row column height width"; return $?; }
  local _zui_number
  for _zui_number in "$@"; do _zdraw_ui_uint "$_zui_number" || { _zdraw_ui_error 1 "${(%):-%N}" "geometry must use integers from 0 to 32767, got ${(qqq)_zui_number}"; return $?; }; done
  _zui_y=$((10#$1)) _zui_x=$((10#$2)) _zui_h=$((10#$3)) _zui_w=$((10#$4))
  (( _zui_y + _zui_h <= 32767 && _zui_x + _zui_w <= 32767 )) || { _zdraw_ui_error 1 "${(%):-%N}" 'rectangle extent exceeds 32767'; return $?; }
}

function zdraw-layout-inset {
  emulate -L zsh
  [[ $# == 8 && ${(t)reply} == (array|array-local) ]] || { _zdraw_ui_error 1 "${(%):-%N}" "requires eight geometry arguments and a writable reply array"; return $?; }
  local -i _zui_y _zui_x _zui_h _zui_w _zui_top _zui_right _zui_bottom _zui_left
  local _zui_number
  _zdraw_ui_layout_rect "${@:1:4}" || return 1
  for _zui_number in "${@:5}"; do _zdraw_ui_uint "$_zui_number" || { _zdraw_ui_error 1 "${(%):-%N}" "insets must be integers from 0 to 32767, got ${(qqq)_zui_number}"; return $?; }; done
  _zui_top=$((10#$5)) _zui_right=$((10#$6)) _zui_bottom=$((10#$7)) _zui_left=$((10#$8))
  (( _zui_y += _zui_top < _zui_h ? _zui_top : _zui_h ))
  (( _zui_x += _zui_left < _zui_w ? _zui_left : _zui_w ))
  _zui_h=$(( _zui_h > _zui_top + _zui_bottom ? _zui_h - _zui_top - _zui_bottom : 0 ))
  _zui_w=$(( _zui_w > _zui_left + _zui_right ? _zui_w - _zui_left - _zui_right : 0 ))
  reply=("$_zui_y" "$_zui_x" "$_zui_h" "$_zui_w")
}

function zdraw-layout-center {
  emulate -L zsh
  [[ $# == 6 && ${(t)reply} == (array|array-local) ]] || { _zdraw_ui_error 1 "${(%):-%N}" "requires six geometry arguments and a writable reply array"; return $?; }
  local -i _zui_y _zui_x _zui_h _zui_w _zui_height _zui_width
  _zdraw_ui_layout_rect "${@:1:4}" || return 1
  _zdraw_ui_uint "$5" && _zdraw_ui_uint "$6" || { _zdraw_ui_error 1 "${(%):-%N}" "requested dimensions must be integers from 0 to 32767"; return $?; }
  _zui_height=$((10#$5)) _zui_width=$((10#$6))
  (( _zui_height > _zui_h )) && _zui_height=$_zui_h
  (( _zui_width > _zui_w )) && _zui_width=$_zui_w
  reply=("$((_zui_y+(_zui_h-_zui_height)/2))" "$((_zui_x+(_zui_w-_zui_width)/2))"
    "$_zui_height" "$_zui_width")
}

function zdraw-layout-split {
  emulate -L zsh
  [[ $# -ge 7 && $# -le 38 && ${(t)zdraw_ui_layout} == (association|association-local) ]] || { _zdraw_ui_error 1 "${(%):-%N}" "requires rectangle axis gap and 1 to 32 tracks, with a writable zdraw_ui_layout association"; return $?; }
  local -i _zui_y _zui_x _zui_h _zui_w _zui_gap _zui_extent _zui_count
  local -i _zui_fixed=0 _zui_weights=0 _zui_free _zui_leftover _zui_i _zui_value _zui_offset=0
  local _zui_axis=$5 _zui_spec _zui_kind _zui_raw
  local -a _zui_kinds _zui_values _zui_sizes
  local -A _zui_layout
  _zdraw_ui_layout_rect "${@:1:4}" || return 1
  [[ $_zui_axis == (rows|columns) ]] || { _zdraw_ui_error 1 "${(%):-%N}" "expected rows or columns, got ${(qqq)_zui_axis}"; return $?; }
  _zdraw_ui_uint "$6" || { _zdraw_ui_error 1 "${(%):-%N}" "gap must be an integer from 0 to 32767"; return $?; }
  _zui_gap=$((10#$6))
  _zui_extent=$_zui_w
  [[ $_zui_axis == rows ]] && _zui_extent=$_zui_h
  shift 6
  _zui_count=$#
  for _zui_spec in "$@"; do
    [[ $_zui_spec == *=* ]] || { _zdraw_ui_error 1 "${(%):-%N}" "expected fixed=integer or flex=weight, got ${(qqq)_zui_spec}"; return $?; }
    _zui_kind=${_zui_spec%%=*} _zui_raw=${_zui_spec#*=}
    [[ $_zui_kind == (fixed|flex) ]] || { _zdraw_ui_error 1 "${(%):-%N}" "unknown track kind ${(qqq)_zui_kind}"; return $?; }
    _zdraw_ui_uint "$_zui_raw" || { _zdraw_ui_error 1 "${(%):-%N}" "track size or weight must be an integer from 0 to 32767"; return $?; }
    _zui_value=$((10#$_zui_raw))
    if [[ $_zui_kind == fixed ]]; then
      (( _zui_fixed += _zui_value ))
    else
      (( _zui_value > 0 )) || { _zdraw_ui_error 1 "${(%):-%N}" "flex weight must be positive"; return $?; }
      (( _zui_weights += _zui_value ))
    fi
    _zui_kinds+=("$_zui_kind") _zui_values+=("$_zui_value")
  done
  _zui_free=$(( _zui_extent - _zui_fixed - (_zui_count-1)*_zui_gap ))
  # Valid constraints that do not fit are distinct from malformed arguments.
  (( _zui_free >= 0 )) || { _zdraw_ui_error 2 "${(%):-%N}" "tracks and gaps exceed the available rectangle"; return $?; }
  _zui_leftover=$_zui_free
  for (( _zui_i=1; _zui_i<=_zui_count; _zui_i++ )); do
    _zui_value=$_zui_values[$_zui_i]
    if [[ $_zui_kinds[$_zui_i] == flex ]]; then
      _zui_value=$(( _zui_free * _zui_value / _zui_weights ))
      (( _zui_leftover -= _zui_value ))
    fi
    _zui_sizes+=("$_zui_value")
  done
  # Integer remainders go to earlier flexible tracks, one cell each. Fixed
  # tracks never stretch; an all-fixed layout may leave trailing space unused.
  _zui_layout=(count "$_zui_count")
  for (( _zui_i=1; _zui_i<=_zui_count; _zui_i++ )); do
    _zui_value=$_zui_sizes[$_zui_i]
    if [[ $_zui_kinds[$_zui_i] == flex ]] && (( _zui_leftover )); then
      (( _zui_value++, _zui_leftover-- ))
    fi
    _zui_layout[$_zui_i,row]=$_zui_y _zui_layout[$_zui_i,column]=$_zui_x
    _zui_layout[$_zui_i,height]=$_zui_h _zui_layout[$_zui_i,width]=$_zui_w
    if [[ $_zui_axis == rows ]]; then
      _zui_layout[$_zui_i,row]=$(( _zui_y + _zui_offset ))
      _zui_layout[$_zui_i,height]=$_zui_value
    else
      _zui_layout[$_zui_i,column]=$(( _zui_x + _zui_offset ))
      _zui_layout[$_zui_i,width]=$_zui_value
    fi
    (( _zui_offset += _zui_value + _zui_gap ))
  done
  zdraw_ui_layout=("${(@kv)_zui_layout}")
}

function zdraw-layout-rect {
  emulate -L zsh
  [[ $# == 1 && ${(t)reply} == (array|array-local) && ${(t)zdraw_ui_layout} == association* ]] || { _zdraw_ui_error 1 "${(%):-%N}" "requires a track index, a writable reply array and a zdraw_ui_layout association"; return $?; }
  _zdraw_ui_uint "$1" && _zdraw_ui_uint "${zdraw_ui_layout[count]-}" || { _zdraw_ui_error 1 "${(%):-%N}" "track index and layout count must be integers from 0 to 32767"; return $?; }
  local -i _zui_index=$((10#$1)) _zui_count=$((10#$zdraw_ui_layout[count]))
  local -i _zui_y _zui_x _zui_h _zui_w
  (( _zui_count >= 1 && _zui_count <= 32 && _zui_index >= 1 && _zui_index <= _zui_count )) || { _zdraw_ui_error 1 "${(%):-%N}" "track index or layout count is out of range"; return $?; }
  _zdraw_ui_layout_rect "${zdraw_ui_layout[$_zui_index,row]-}" "${zdraw_ui_layout[$_zui_index,column]-}" \
    "${zdraw_ui_layout[$_zui_index,height]-}" "${zdraw_ui_layout[$_zui_index,width]-}" || return 1
  reply=("$_zui_y" "$_zui_x" "$_zui_h" "$_zui_w")
}
