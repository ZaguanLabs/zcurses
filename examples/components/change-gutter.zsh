# SPDX-License-Identifier: LicenseRef-Zsh
# Experimental drawing treatment. The application supplies already-classified rows.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h:h:h}/lib/zdraw-ui.zsh"
} "${(%):-%x}" || return

function zdraw-change-gutter {
  emulate -L zsh
  [[ $# -ge 7 && ${(t)zdraw_ui_theme} == association* &&
     ${(t)zdraw_ui_gutter} == (association|association-local) ]] || {
    _zdraw_ui_error 1 "${(%):-%N}" 'requires window rectangle, first row, -- kind/old/new/text tuples, theme and writable gutter association'; return $?
  }
  local _cg_win=$1 _cg_first=$6 _cg_numbers=auto _cg_offset=0 _cg_glyphs=auto
  local -i _zui_y _zui_x _zui_h _zui_w _cg_count _cg_digits=3 _cg_total=0 _cg_widest=0
  local -i _cg_i _cg_width _cg_body _cg_gutter _cg_visible _cg_max_first _cg_max_offset _cg_y
  local -a _cg_data _cg_opts _cg_lines _cg_kinds _cg_old_numbers _cg_new_numbers
  local -A _cg_info _cg_hit _cg_styles _cg_gutter_styles zdraw_ui_style
  local _cg_kind _cg_old _cg_new _cg_text _cg_number _cg_state _cg_prefix _cg_marker _cg_separator='|'
  _zdraw_ui_rect "${@:1:5}" || return
  _zdraw_ui_uint "$_cg_first" && (( 10#$_cg_first > 0 )) || return 1
  shift 6
  while (( $# )) && [[ $1 != -- ]]; do
    case $1 in
      numbers=*) _cg_numbers=${1#*=} ;;
      offset=*) _cg_offset=${1#*=} ;;
      glyphs=*) _cg_glyphs=${1#*=} ;;
      *) _cg_opts+=("$1") ;;
    esac
    shift
  done
  (( $# )) || return 1
  shift
  (( $# % 4 == 0 && $# <= 1024 )) && [[ $_cg_numbers == (auto|both|single) && $_cg_glyphs == (auto|ascii) ]] &&
    _zdraw_ui_uint "$_cg_offset" || {
      _zdraw_ui_error 1 "${(%):-%N}" 'expected at most 256 kind/old/new/text tuples, numbers=auto|both|single, glyphs=auto|ascii and offset=0..32767'; return $?
    }
  _cg_first=$((10#$_cg_first)) _cg_offset=$((10#$_cg_offset))
  _cg_data=("$@") _cg_count=$(($#/4))
  # Validate every source row, including off-screen text, before painting.
  for _cg_kind _cg_old _cg_new _cg_text in "${_cg_data[@]}"; do
    case $_cg_kind in
      context) [[ $_cg_old != - && $_cg_new != - ]] || return 1 ;;
      add) [[ $_cg_old == - && $_cg_new != - ]] || return 1 ;;
      remove) [[ $_cg_old != - && $_cg_new == - ]] || return 1 ;;
      hunk) [[ $_cg_old == - && $_cg_new == - ]] || return 1 ;;
      *) return 1 ;;
    esac
    for _cg_number in "$_cg_old" "$_cg_new"; do
      [[ $_cg_number == - ]] && continue
      [[ $_cg_number == <-> && ${#_cg_number} -le 6 ]] && (( 10#$_cg_number > 0 )) || return 1
      (( ${#_cg_number} > _cg_digits )) && _cg_digits=${#_cg_number}
    done
    (( _cg_total+=${#_cg_text}, _cg_total<=65536 )) || return 1
    zdraw textinfo _cg_info "$_cg_text" || return
    (( _cg_info[width] <= 32767 )) || return 1
    [[ $_cg_kind != hunk ]] && (( _cg_info[width] > _cg_widest )) && _cg_widest=$_cg_info[width]
    _cg_kinds+=("$_cg_kind") _cg_old_numbers+=("$_cg_old") _cg_new_numbers+=("$_cg_new")
  done
  if [[ $_cg_numbers == auto ]]; then
    if (( _zui_w >= 60 )); then _cg_numbers=both; else _cg_numbers=single; fi
  fi
  _cg_gutter=$((_cg_digits+5))
  [[ $_cg_numbers == both ]] && _cg_gutter=$((2*_cg_digits+6))
  _cg_body=$((_zui_w-_cg_gutter-1)) _cg_visible=$((_zui_h-1))
  (( _cg_body >= 8 && _cg_visible >= 1 )) || {
    _zdraw_ui_error 2 "${(%):-%N}" 'requires a header, one content row and eight text columns after the gutter'; return $?
  }
  _cg_max_first=$((_cg_count>_cg_visible ? _cg_count-_cg_visible+1 : 1))
  (( _cg_first>_cg_max_first )) && _cg_first=$_cg_max_first
  _cg_max_offset=$((_cg_widest>_cg_body ? _cg_widest-_cg_body : 0))
  (( _cg_offset>_cg_max_offset )) && _cg_offset=$_cg_max_offset
  # Resolve body and gutter styles once per semantic state. No new theme roles.
  for _cg_state in normal positive negative header; do
    zdraw-ui-style "$_cg_state" fg=text bg=canvas positive:bg=surface negative:bg=surface \
      header:fg=accent header:bold "${_cg_opts[@]}" || return
    [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[px] == 0 &&
       $zdraw_ui_style[py] == 0 && $zdraw_ui_style[align] == left ]] || return 1
    _cg_styles[$_cg_state]=$zdraw_ui_style[style]
    zdraw-ui-style "$_cg_state" fg=muted bg=canvas positive:bg=surface negative:bg=surface \
      positive:fg=accent negative:fg=error "${_cg_opts[@]}" || return
    _cg_gutter_styles[$_cg_state]=$zdraw_ui_style[style]
  done
  if [[ $_cg_glyphs == auto ]] && (( ${zdraw_features[(Ie)wide_spans]} )) &&
    zdraw textinfo _cg_info '│' 2>/dev/null && [[ $_cg_info[width] == 1 ]]; then _cg_separator='│'; fi
  # Slice only at the native cell boundaries. A partly hidden wide unit becomes
  # a blank column, preserving alignment without starting at a combining mark.
  for (( _cg_i=1; _cg_i<=_cg_count; _cg_i++ )); do
    _cg_text=$_cg_data[$((_cg_i*4))]
    if (( _cg_offset )) && [[ $_cg_kinds[$_cg_i] != hunk ]]; then
      zdraw textinfo _cg_info "$_cg_text" || return
      if (( _cg_offset >= _cg_info[width] )); then _cg_text=''
      else
        zdraw textpos _cg_hit "$_cg_text" column "$_cg_offset" || return
        _cg_text="$_cg_hit[text]$_cg_hit[remainder]"
        (( _cg_hit[column_start] < _cg_offset )) && _cg_text=" $_cg_hit[remainder]"
      fi
    fi
    _cg_lines+=("$_cg_text")
  done
  zdraw fill "$_cg_win" "$_zui_y" "$_zui_x" "$_zui_h" "$_zui_w" "$_cg_styles[normal]" ' ' || return
  if [[ $_cg_numbers == both ]]; then
    printf -v _cg_prefix '%*s %*s    ' "$_cg_digits" OLD "$_cg_digits" NEW
  else printf -v _cg_prefix '%*s    ' "$_cg_digits" LN; fi
  zdraw spansclip "$_cg_win" "$_zui_y" "$_zui_x" "$_zui_w" "$_cg_gutter_styles[normal]" "$_cg_prefix CHANGE" || return
  if (( !_cg_count )); then
    zdraw spansclip "$_cg_win" "$((_zui_y+1))" "$_zui_x" "$_zui_w" "$_cg_gutter_styles[normal]" 'No changes' || return
  fi
  for (( _cg_i=_cg_first, _cg_y=_zui_y+1; _cg_i<=_cg_count && _cg_y<_zui_y+_zui_h; _cg_i++, _cg_y++ )); do
    _cg_state=normal _cg_marker=' '
    case $_cg_kinds[$_cg_i] in
      add) _cg_state=positive _cg_marker='+' ;;
      remove) _cg_state=negative _cg_marker='-' ;;
      hunk) _cg_state=header ;;
    esac
    zdraw fill "$_cg_win" "$_cg_y" "$_zui_x" 1 "$_zui_w" "$_cg_styles[$_cg_state]" ' ' || return
    _cg_old=$_cg_old_numbers[$_cg_i] _cg_new=$_cg_new_numbers[$_cg_i]
    [[ $_cg_old == - ]] && _cg_old=''
    [[ $_cg_new == - ]] && _cg_new=''
    _cg_text=$_cg_lines[$_cg_i] _cg_width=$_cg_body
    if [[ $_cg_state == header ]]; then
      _cg_prefix='' _cg_width=$((_zui_w-1))
    elif [[ $_cg_numbers == both ]]; then
      printf -v _cg_prefix '%*s %*s %s %s ' "$_cg_digits" "$_cg_old" "$_cg_digits" "$_cg_new" "$_cg_marker" "$_cg_separator"
    else
      _cg_number=$_cg_new
      [[ $_cg_kinds[$_cg_i] == remove ]] && _cg_number=$_cg_old
      printf -v _cg_prefix '%*s %s %s ' "$_cg_digits" "$_cg_number" "$_cg_marker" "$_cg_separator"
    fi
    zdraw textinfo _cg_info "$_cg_text" "$_cg_width" || return
    zdraw spansclip "$_cg_win" "$_cg_y" "$_zui_x" "$((_zui_w-1))" \
      "$_cg_gutter_styles[$_cg_state]" "$_cg_prefix" "$_cg_styles[$_cg_state]" "$_cg_info[text]" || return
    if [[ $_cg_info[truncated] == 1 ]]; then
      zdraw spans "$_cg_win" "$_cg_y" "$((_zui_x+_zui_w-1))" "$_cg_gutter_styles[$_cg_state]" '>' || return
    fi
  done
  zdraw_ui_gutter=(first "$_cg_first" offset "$_cg_offset" max_offset "$_cg_max_offset"
    count "$_cg_count" visible "$_cg_visible" numbers "$_cg_numbers" text_columns "$_cg_body")
}
