# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../../LICENCE
# Encode ASCII JSON, including surrogate pairs, without evaluating text.
# REPLY is a scalar scratch result owned by the enclosing exporter.
function _zdraw_ui_json_string {
  emulate -L zsh
  local _zui_char _zui_piece
  local -i _zui_code
  REPLY='"'
  for _zui_char in "${(@s::)1}"; do
    [[ -n $_zui_char ]] || continue
    printf -v _zui_code '%d' "'$_zui_char" || return
    case $_zui_char in
      '"'|'\') REPLY+="\\$_zui_char" ;;
      *)
        if (( _zui_code >= 32 && _zui_code < 127 )); then
          REPLY+=$_zui_char
        elif (( _zui_code <= 65535 )); then
          printf -v _zui_piece '\\u%04x' "$_zui_code" || return
          REPLY+=$_zui_piece
        else
          (( _zui_code -= 65536 ))
          printf -v _zui_piece '\\u%04x\\u%04x' "$((55296+(_zui_code>>10)))" "$((56320+(_zui_code&1023)))" || return
          REPLY+=$_zui_piece
        fi ;;
    esac
  done
  REPLY+='"'
}

function zdraw-fixture {
  emulate -L zsh
  [[ $# == 1 && ${(t)zdraw_ui_fixture} == (scalar|scalar-local) ]] || return 1
  local -A _zui_snapshot _zui_names=(black 0 red 1 green 2 yellow 3 blue 4 magenta 5 cyan 6 white 7)
  local _zui_result REPLY _zui_text _zui_color _zui_side
  local -i _zui_r _zui_c _zui_i
  local -a _zui_sides _zui_fields
  zdraw snapshot "$1" _zui_snapshot || return
  # A bounded fixture is intentionally smaller than the native snapshot limit.
  (( _zui_snapshot[cell_count] <= 16384 )) || return 1
  _zui_result='{"format":"zdraw-ui-fixture-1","layout":"readback","rows":'
  _zui_result+="$_zui_snapshot[rows],\"columns\":$_zui_snapshot[columns],\"cursor\":[$_zui_snapshot[cursor_row],$_zui_snapshot[cursor_column]],\"cells\":["$'\n'
  for (( _zui_r=0; _zui_r<_zui_snapshot[rows]; _zui_r++ )); do
    for (( _zui_c=0; _zui_c<_zui_snapshot[columns]; _zui_c++ )); do
      _zui_color=$_zui_snapshot[$_zui_r,$_zui_c,color]
      if [[ $_zui_color != unknown ]]; then
        _zui_sides=("${(@s:/:)_zui_color}")
        for (( _zui_i=1; _zui_i<=${#_zui_sides}; _zui_i++ )); do
          _zui_side=$_zui_sides[$_zui_i]
          if [[ -n ${_zui_names[$_zui_side]-} ]]; then
            _zui_sides[$_zui_i]=$_zui_names[$_zui_side]
          elif [[ $_zui_side == <-> ]]; then
            _zui_sides[$_zui_i]=$((10#$_zui_side))
          else
            _zui_sides[$_zui_i]=${(L)_zui_side}
          fi
        done
        _zui_color=${(j:/:)_zui_sides}
      fi
      _zui_fields=()
      for _zui_text in "$_zui_snapshot[$_zui_r,$_zui_c,text]" "$_zui_color" \
        "$_zui_snapshot[$_zui_r,$_zui_c,attributes]" "$_zui_snapshot[$_zui_r,$_zui_c,encoding]"; do
        _zdraw_ui_json_string "$_zui_text" || return
        _zui_fields+=("$REPLY")
      done
      _zui_result+="[$_zui_r,$_zui_c,${(j:,:)_zui_fields}]"
      (( _zui_r+1 < _zui_snapshot[rows] || _zui_c+1 < _zui_snapshot[columns] )) && _zui_result+=','
      _zui_result+=$'\n'
    done
  done
  _zui_result+=']}'
  zdraw_ui_fixture=$_zui_result
}
