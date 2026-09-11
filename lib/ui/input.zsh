# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../../LICENCE
# Byte anchors use the field's explicit boundary policy (cell by default).
function _zdraw_ui_bytes {
  emulate -L zsh
  local LC_ALL=C
  REPLY=${#1}
}

function zdraw-input-init {
  emulate -L zsh
  [[ $# -ge 1 && $# -le 3 && ${(t)zdraw_ui_input} == (association|association-local) ]] || return 1
  local _zui_limit=${2:-4096} _zui_boundary=${3:-cell}
  local -A _zui_pos
  _zdraw_ui_uint "$_zui_limit" || return 1
  [[ $_zui_boundary == (cell|grapheme) ]] || return 1
  zdraw textpos _zui_pos "$1" byte 0 "$_zui_boundary" || return
  (( _zui_pos[total_bytes] <= 10#$_zui_limit )) || return 1
  zdraw_ui_input=(text "$1" cursor "$_zui_pos[total_bytes]" anchor "$_zui_pos[total_bytes]"
    limit "$((10#$_zui_limit))" paste_active 0 paste_failed 0 paste_buffer '')
  [[ $_zui_boundary == cell ]] || zdraw_ui_input[boundary]=$_zui_boundary
  return 0
}

# Resolve per-field policy at every query; no process-global mode or cache.
function _zdraw_ui_input_pos {
  emulate -L zsh
  local _zui_boundary=${zdraw_ui_input[boundary]:-cell}
  [[ $_zui_boundary == (cell|grapheme) ]] || return 1
  zdraw textpos "$@" "$_zui_boundary"
}

# Populate the caller's scratch positions only after lexical validation.
function _zdraw_ui_input_state {
  emulate -L zsh
  [[ ${(t)zdraw_ui_input} == association* ]] || return 1
  local _zui_key
  for _zui_key in cursor anchor limit; do
    _zdraw_ui_uint "${zdraw_ui_input[$_zui_key]-}" || return 1
  done
  [[ ${zdraw_ui_input[paste_active]-} == [01] && ${zdraw_ui_input[paste_failed]-} == [01] ]] || return 1
  _zdraw_ui_input_pos _zui_cursor "${zdraw_ui_input[text]-}" byte "$zdraw_ui_input[cursor]" || return
  _zdraw_ui_input_pos _zui_anchor "${zdraw_ui_input[text]-}" byte "$zdraw_ui_input[anchor]" || return
  (( _zui_cursor[byte_start] == 10#$zdraw_ui_input[cursor] &&
     _zui_anchor[byte_start] == 10#$zdraw_ui_input[anchor] &&
     _zui_cursor[total_bytes] <= 10#$zdraw_ui_input[limit] ))
}

function zdraw-input-edit {
  emulate -L zsh
  [[ $# -ge 1 && $# -le 2 && ${(t)zdraw_ui_input} == (association|association-local) ]] || return 1
  local _zui_action=$1 _zui_insert=${2-} _zui_candidate REPLY
  [[ $_zui_action == (insert|left|right|home|end|select-left|select-right|select-home|select-end|select-all|backspace|delete|clear) ]] || return 1
  [[ ( $_zui_action == insert && $# == 2 ) || ( $_zui_action != insert && $# == 1 ) ]] || return 1
  local -A _zui_cursor _zui_anchor _zui_left _zui_right _zui_new
  _zdraw_ui_input_state || return
  [[ $zdraw_ui_input[paste_active] == 0 ]] || return 1
  local -i _zui_c=$_zui_cursor[byte_start] _zui_a=$_zui_anchor[byte_start] _zui_lo _zui_hi
  _zui_lo=$((_zui_c < _zui_a ? _zui_c : _zui_a))
  _zui_hi=$((_zui_c > _zui_a ? _zui_c : _zui_a))
  case $_zui_action in
    left|select-left)
      if [[ $_zui_action == left ]] && (( _zui_lo != _zui_hi )); then _zui_c=$_zui_lo
      elif (( _zui_c )); then
        _zdraw_ui_input_pos _zui_new "$zdraw_ui_input[text]" byte "$((_zui_c-1))" || return
        _zui_c=$_zui_new[byte_start]
      fi ;;
    right|select-right)
      if [[ $_zui_action == right ]] && (( _zui_lo != _zui_hi )); then _zui_c=$_zui_hi
      else _zui_c=$_zui_cursor[byte_end]; fi ;;
    home|select-home) _zui_c=0 ;;
    end|select-end) _zui_c=$_zui_cursor[total_bytes] ;;
    select-all) _zui_a=0 _zui_c=$_zui_cursor[total_bytes] ;;
    *)
      case $_zui_action in
        clear) _zui_lo=0 _zui_hi=$_zui_cursor[total_bytes] ;;
        backspace)
          if (( _zui_lo == _zui_hi && _zui_lo > 0 )); then
            _zdraw_ui_input_pos _zui_new "$zdraw_ui_input[text]" byte "$((_zui_lo-1))" || return
            _zui_lo=$_zui_new[byte_start]
          fi ;;
        delete) (( _zui_lo == _zui_hi )) && _zui_hi=$_zui_cursor[byte_end] ;;
      esac
      _zdraw_ui_input_pos _zui_left "$zdraw_ui_input[text]" byte "$_zui_lo" || return
      _zdraw_ui_input_pos _zui_right "$zdraw_ui_input[text]" byte "$_zui_hi" || return
      _zui_candidate="$_zui_left[prefix]$_zui_insert$_zui_right[text]$_zui_right[remainder]"
      _zdraw_ui_bytes "$_zui_left[prefix]$_zui_insert"
      _zui_c=$REPLY
      _zdraw_ui_input_pos _zui_new "$_zui_candidate" byte "$_zui_c" || return
      (( _zui_new[total_bytes] <= 10#$zdraw_ui_input[limit] )) || return 1
      # Inserting a base before combining characters may join an existing unit.
      (( _zui_new[byte_start] < _zui_c )) && _zui_c=$_zui_new[byte_end]
      zdraw_ui_input[text]=$_zui_candidate ;;
  esac
  [[ $_zui_action == select-* ]] || _zui_a=$_zui_c
  zdraw_ui_input[cursor]=$_zui_c zdraw_ui_input[anchor]=$_zui_a
}

# Data can split UTF-8 anywhere. Keep edits atomic and drain a rejected paste.
function zdraw-input-paste {
  emulate -L zsh
  [[ $# -ge 1 && $# -le 2 && ${(t)zdraw_ui_input} == (association|association-local) ]] || return 1
  [[ $1 == data || $# == 1 ]] || return 1
  local -A _zui_cursor _zui_anchor
  local REPLY _zui_buffer
  _zdraw_ui_input_state || return
  case $1 in
    begin)
      [[ $zdraw_ui_input[paste_active] == 0 ]] || return 1
      zdraw_ui_input[paste_active]=1 zdraw_ui_input[paste_failed]=0 zdraw_ui_input[paste_buffer]='' ;;
    data)
      [[ $# == 2 && $zdraw_ui_input[paste_active] == 1 ]] || return 1
      [[ $zdraw_ui_input[paste_failed] == 0 ]] || return 1
      _zdraw_ui_bytes "${zdraw_ui_input[paste_buffer]-}$2"
      if (( REPLY > 10#$zdraw_ui_input[limit] )); then
        zdraw_ui_input[paste_failed]=1 zdraw_ui_input[paste_buffer]=''
        return 1
      fi
      zdraw_ui_input[paste_buffer]+=$2 ;;
    end)
      [[ $zdraw_ui_input[paste_active] == 1 ]] || return 1
      _zui_buffer=${zdraw_ui_input[paste_buffer]-}
      zdraw_ui_input[paste_active]=0 zdraw_ui_input[paste_buffer]=''
      [[ $zdraw_ui_input[paste_failed] == 0 ]] || { zdraw_ui_input[paste_failed]=0; return 1; }
      zdraw-input-edit insert "$_zui_buffer" || return ;;
    cancel) zdraw_ui_input[paste_active]=0 zdraw_ui_input[paste_failed]=0 zdraw_ui_input[paste_buffer]='' ;;
    *) return 1 ;;
  esac
  return 0
}

# 0 valid, 1 validation failure (message), 2 invalid API/rules (no output change).
function zdraw-input-check {
  emulate -L zsh
  [[ ${(t)zdraw_ui_error} == (scalar|scalar-local) && $# -le 16 ]] || return 2
  local -A _zui_cursor _zui_anchor
  _zdraw_ui_input_state || return 2
  local _zui_rule _zui_value _zui_error=''
  local -i _zui_number=0 _zui_numeric=0
  if [[ $zdraw_ui_input[text] == <-> && ${#zdraw_ui_input[text]} -le 9 ]]; then
    _zui_numeric=1 _zui_number=$((10#$zdraw_ui_input[text]))
  fi
  for _zui_rule in "$@"; do
    case $_zui_rule in
      required|integer) ;;
      min-length=*|max-length=*|min=*|max=*)
        _zui_value=${_zui_rule#*=}
        [[ $_zui_value == <-> && ${#_zui_value} -le 9 ]] || return 2 ;;
      *) return 2 ;;
    esac
    [[ -z $_zui_error ]] || continue
    case $_zui_rule in
      required) [[ -n $zdraw_ui_input[text] ]] || _zui_error='This field is required.' ;;
      integer) (( _zui_numeric )) || _zui_error='Enter an unsigned integer (up to 9 digits).' ;;
      min-length=*) (( ${#zdraw_ui_input[text]} >= 10#$_zui_value )) || _zui_error="Use at least $((10#$_zui_value)) characters." ;;
      max-length=*) (( ${#zdraw_ui_input[text]} <= 10#$_zui_value )) || _zui_error="Use at most $((10#$_zui_value)) characters." ;;
      min=*|max=*)
        if (( ! _zui_numeric )); then _zui_error='Enter an unsigned integer (up to 9 digits).'
        elif [[ $_zui_rule == min=* ]]; then
          (( _zui_number >= 10#$_zui_value )) || _zui_error="Enter a value of at least $((10#$_zui_value))."
        else
          (( _zui_number <= 10#$_zui_value )) || _zui_error="Enter a value of at most $((10#$_zui_value))."
        fi ;;
    esac
  done
  zdraw_ui_error=$_zui_error
  [[ -z $_zui_error ]]
}

function zdraw-input {
  emulate -L zsh
  (( $# >= 5 )) || return 1
  local _zui_win=$1 _zui_states=$5 _zui_base _zui_selected _zui_caret
  local -i _zui_y _zui_x _zui_h _zui_w _zui_start=0 _zui_col _zui_left _zui_right _zui_width
  local -A _zui_cursor _zui_anchor _zui_pos zdraw_ui_style
  local -a _zui_spans
  _zdraw_ui_input_state || return
  _zdraw_ui_rect "$1" "$2" "$3" 1 "$4" || return
  zdraw-ui-style "$_zui_states" fg=text bg=surface "${@:6}" || return
  [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[py] == 0 && $zdraw_ui_style[px] == 0 && $zdraw_ui_style[align] == left ]] || return 1
  _zui_base=$zdraw_ui_style[style]
  zdraw-ui-style "$_zui_states,selected" fg=text bg=surface selected:fg=on-selection selected:bg=selection selected:reverse "${@:6}" || return
  _zui_selected=$zdraw_ui_style[style]
  zdraw-ui-style "$_zui_states,cursor" fg=text bg=surface cursor:reverse "${@:6}" || return
  _zui_caret=$zdraw_ui_style[style]
  _zui_left=$((_zui_cursor[byte_start] < _zui_anchor[byte_start] ? _zui_cursor[byte_start] : _zui_anchor[byte_start]))
  _zui_right=$((_zui_cursor[byte_start] > _zui_anchor[byte_start] ? _zui_cursor[byte_start] : _zui_anchor[byte_start]))
  _zui_width=$((_zui_cursor[column_end]-_zui_cursor[column_start]))
  (( _zui_width < 1 || _zui_width > _zui_w )) && _zui_width=1
  _zui_col=$((_zui_cursor[column_start]+_zui_width-_zui_w))
  if (( _zui_col > 0 )); then
    _zdraw_ui_input_pos _zui_pos "$zdraw_ui_input[text]" column "$_zui_col" || return
    _zui_start=$_zui_pos[byte_start]
    (( _zui_pos[column_start] < _zui_col )) && _zui_start=$_zui_pos[byte_end]
  fi
  _zdraw_ui_input_pos _zui_pos "$zdraw_ui_input[text]" byte "$_zui_start" || return
  _zui_col=$((_zui_cursor[column_start]-_zui_pos[column_start]))
  # Group units into same-style runs; native clipping validates the complete row.
  local _zui_style _zui_run='' _zui_previous=''
  local -i _zui_rendered=0 _zui_unit_width
  while [[ $_zui_pos[at_end] == 0 ]]; do
    _zui_unit_width=$((_zui_pos[column_end]-_zui_pos[column_start]))
    if [[ ${zdraw_ui_input[boundary]:-cell} == grapheme ]] && (( _zui_unit_width > _zui_w-_zui_rendered )); then break; fi
    (( _zui_rendered += _zui_unit_width ))
    _zui_style=$_zui_base
    (( _zui_pos[byte_start] >= _zui_left && _zui_pos[byte_start] < _zui_right )) && _zui_style=$_zui_selected
    if [[ $_zui_style != $_zui_previous && -n $_zui_run ]]; then
      _zui_spans+=("$_zui_previous" "$_zui_run") _zui_run=''
    fi
    _zui_previous=$_zui_style _zui_run+=$_zui_pos[text]
    _zdraw_ui_input_pos _zui_pos "$zdraw_ui_input[text]" byte "$_zui_pos[byte_end]" || return
    # Only a screenful is needed; avoid walking a long invisible suffix.
    (( _zui_pos[column_start] >= _zui_cursor[column_start] + _zui_w )) && break
  done
  [[ -n $_zui_run ]] && _zui_spans+=("$_zui_previous" "$_zui_run")
  zdraw fill "$_zui_win" "$_zui_y" "$_zui_x" 1 "$_zui_w" "$_zui_base" ' ' || return
  if (( ${#_zui_spans} )); then
    zdraw spansclip "$_zui_win" "$_zui_y" "$_zui_x" "$_zui_w" "${_zui_spans[@]}" || return
  fi
  if [[ ,$_zui_states, == *,focus,* && $_zui_col -ge 0 && $_zui_col -lt $_zui_w ]]; then
    local _zui_glyph=${_zui_cursor[text]:- }
    (( _zui_cursor[column_end]-_zui_cursor[column_start] > _zui_w )) && _zui_glyph=' '
    if [[ ${zdraw_ui_input[boundary]:-cell} == grapheme ]] && (( _zui_cursor[column_end]-_zui_cursor[column_start] > _zui_w-_zui_col )); then _zui_glyph=' '; fi
    zdraw spansclip "$_zui_win" "$_zui_y" "$((_zui_x+_zui_col))" "$((_zui_w-_zui_col))" "$_zui_caret" "$_zui_glyph" || return
  fi
  return 0
}
