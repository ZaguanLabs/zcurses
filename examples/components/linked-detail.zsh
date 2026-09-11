# SPDX-License-Identifier: LicenseRef-Zsh
# Reusable experimental treatment; see docs/linked-detail.md for the contract.
# Loading is passive. Keep this file beside a checkout's lib/ directory structure.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h:h:h}/lib/zdraw-list.zsh" || return
  builtin source "${1:A:h:h:h}/lib/zdraw-layout.zsh"
} "${(%):-%x}" || return

function zdraw-linked-detail {
  emulate -L zsh
  # State and outputs use the toolkit's existing caller-owned dynamic scope.
  [[ $# -ge 7 && ${(t)zdraw_ui_list} == (association|association-local) &&
     ${(t)zdraw_ui_link} == (association|association-local) &&
     ${(t)reply} == (array|array-local) && ${(t)zdraw_ui_theme} == association* ]] || {
    _zdraw_ui_error 1 "${(%):-%N}" 'requires rectangle, list|detail focus, -- title/description pairs, theme/list/link associations and reply array'; return $?
  }
  local _ld_win=$1 _ld_focus=$6 _ld_name='Items' _ld_detail='Details' _ld_glyphs=auto
  local _ld_gap=1
  local -i _zui_y _zui_x _zui_h _zui_w _ld_count _ld_visible _ld_i _ld_y _ld_selected_y=-1
  local -i _ld_split=0 _ld_lw _ld_dx _ld_dw _ld_first _ld_selected
  local -A zdraw_ui_style _ld_info _ld_base _ld_selected_style _ld_header _ld_muted
  local -A _ld_state=("${(@kv)zdraw_ui_list}")
  local -a _ld_items _ld_titles _ld_descriptions _ld_body _ld_link
  local -a _ld_overrides _ld_tokens=(fg=text bg=canvas selected:bg=selection selected:fg=on-selection
    selected:bold selected+inactive:bg=inactive selected+inactive:fg=on-inactive
    header:fg=accent header:bold)
  [[ $_ld_focus == (list|detail) ]] || { _zdraw_ui_error 1 "${(%):-%N}" 'focus must be list or detail'; return $?; }
  _zdraw_ui_rect "${@:1:5}" || return
  (( _zui_w >= 24 && _zui_h >= 6 )) || { _zdraw_ui_error 2 "${(%):-%N}" 'requires at least 24 columns and 6 rows'; return $?; }
  shift 6
  while (( $# )) && [[ $1 != -- ]]; do
    case $1 in
      list-title=*) _ld_name=${1#*=} ;;
      detail-title=*) _ld_detail=${1#*=} ;;
      glyphs=*) _ld_glyphs=${1#*=} ;;
      item-gap=*) _ld_gap=${1#*=} ;;
      *) _ld_overrides+=("$1") ;;
    esac
    shift
  done
  (( $# )) || { _zdraw_ui_error 1 "${(%):-%N}" 'missing -- before item pairs'; return $?; }
  shift
  (( $# % 2 == 0 && $# <= 256 )) && [[ $_ld_glyphs == (auto|ascii) ]] || {
    _zdraw_ui_error 1 "${(%):-%N}" 'expected at most 128 title/description pairs, glyphs=auto|ascii'; return $?
  }
  [[ $_ld_gap == (0|1) ]] || {
    _zdraw_ui_error 1 "${(%):-%N}" 'expected item-gap=0|1'; return $?
  }
  _ld_items=("$@") _ld_count=$(($#/2))
  local _ld_text _ld_caption _ld_mode=single _ld_part _ld_state_name
  local -i _ld_total=0
  for _ld_text in "$_ld_name" "$_ld_detail" "${_ld_items[@]}"; do
    (( _ld_total+=${#_ld_text} ))
    (( _ld_total <= 262144 )) || { _zdraw_ui_error 1 "${(%):-%N}" 'text exceeds 262144 characters'; return $?; }
    zdraw textinfo _ld_info "$_ld_text" || return
  done
  for _ld_text _ld_caption in "${_ld_items[@]}"; do
    _ld_titles+=("$_ld_text") _ld_descriptions+=("$_ld_caption")
  done
  # Preflight styles and a reconciled copy before touching the window or outputs.
  [[ $zdraw_ui_theme[profile] == mono ]] && _ld_tokens+=(selected:reverse)
  [[ $zdraw_ui_theme[profile] == 16 ]] && _ld_tokens+=(selected:no-bold)
  _ld_tokens+=("${_ld_overrides[@]}")
  for _ld_part in base selected header muted; do
    _ld_state_name=normal
    [[ $_ld_part == selected ]] && _ld_state_name=selected,focus
    [[ $_ld_part == selected && $_ld_focus == detail ]] && _ld_state_name=selected,inactive
    [[ $_ld_part == header ]] && _ld_state_name=header
    local -a _ld_extra=()
    [[ $_ld_part == muted ]] && _ld_extra=(fg=muted)
    zdraw-ui-style "$_ld_state_name" "${_ld_tokens[@]}" "${_ld_extra[@]}" || return
    [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[px] == 0 &&
       $zdraw_ui_style[py] == 0 && $zdraw_ui_style[align] == left ]] || {
      _zdraw_ui_error 1 "${(%):-%N}" 'only color and emphasis utilities are supported'; return $?
    }
    case $_ld_part in
      base) _ld_base=("${(@kv)zdraw_ui_style}") ;;
      selected) _ld_selected_style=("${(@kv)zdraw_ui_style}") ;;
      header) _ld_header=("${(@kv)zdraw_ui_style}") ;;
      muted) _ld_muted=("${(@kv)zdraw_ui_style}") ;;
    esac
  done
  _ld_lw=$_zui_w _ld_dx=$_zui_x _ld_dw=$_zui_w
  if (( _zui_w >= 72 )); then
    _ld_split=1 _ld_mode=split _ld_lw=$((_zui_w/3))
    (( _ld_lw > 38 )) && _ld_lw=38
    _ld_dx=$((_zui_x+_ld_lw+6)) _ld_dw=$((_zui_w-_ld_lw-6))
  fi
  _ld_visible=$(((_zui_h-3)/(2+_ld_gap)))
  () {
    local -A zdraw_ui_list=("${(@kv)_ld_state}")
    zdraw-list-update "$_ld_count" "$_ld_visible" keep || return
    _ld_state=("${(@kv)zdraw_ui_list}")
  } || return
  _ld_first=$_ld_state[first] _ld_selected=$_ld_state[selected]
  local _ld_horizontal='-' _ld_vertical='|' _ld_turn='+' _ld_top='+' _ld_marker='>'
  if [[ $_ld_glyphs == auto ]] && (( ${zdraw_features[(Ie)wide_spans]} )); then
    local -i _ld_wide=1
    for _ld_text in '─' '│' '┘' '┌' '▌'; do
      if ! zdraw textinfo _ld_info "$_ld_text" 2>/dev/null || [[ $_ld_info[width] != 1 ]]; then _ld_wide=0; break; fi
    done
    if (( _ld_wide )); then
      _ld_horizontal='─' _ld_vertical='│' _ld_turn='┘' _ld_top='┌' _ld_marker='▌'
    fi
  fi
  zdraw fill "$_ld_win" "$_zui_y" "$_zui_x" "$_zui_h" "$_zui_w" "$_ld_base[style]" ' ' || return
  if (( _ld_split )) || [[ $_ld_focus == list ]]; then
    zdraw spansclip "$_ld_win" "$_zui_y" "$_zui_x" "$_ld_lw" "$_ld_header[style]" "$_ld_name" || return
    for (( _ld_i=_ld_first, _ld_y=_zui_y+2; _ld_i<=_ld_count && _ld_i<_ld_first+_ld_visible; _ld_i++, _ld_y+=2+_ld_gap )); do
      local _ld_title_style=$_ld_base[style] _ld_description_style=$_ld_muted[style]
      if (( _ld_i == _ld_selected )); then
        _ld_selected_y=$_ld_y
        zdraw fill "$_ld_win" "$_ld_y" "$_zui_x" 2 "$_ld_lw" "$_ld_selected_style[style]" ' ' || return
        zdraw fill "$_ld_win" "$_ld_y" "$_zui_x" 2 1 "$_ld_header[style]" "$_ld_marker" || return
        _ld_title_style=$_ld_selected_style[style] _ld_description_style=$_ld_selected_style[style]
      fi
      zdraw spansclip "$_ld_win" "$_ld_y" "$((_zui_x+2))" "$((_ld_lw-3))" "$_ld_title_style" "$_ld_titles[$_ld_i]" || return
      zdraw spansclip "$_ld_win" "$((_ld_y+1))" "$((_zui_x+2))" "$((_ld_lw-3))" "$_ld_description_style" "$_ld_descriptions[$_ld_i]" || return
    done
    if (( !_ld_count )); then
      zdraw spansclip "$_ld_win" "$((_zui_y+2))" "$_zui_x" "$_ld_lw" "$_ld_muted[style]" 'No items' || return
    fi
    zdraw spansclip "$_ld_win" "$((_zui_y+_zui_h-1))" "$_zui_x" "$_ld_lw" "$_ld_muted[style]" "$_ld_selected / $_ld_count selected" || return
  fi
  _ld_body=("$((_zui_y+2))" "$_ld_dx" "$((_zui_h-2))" "$_ld_dw")
  if (( _ld_split )) || [[ $_ld_focus == detail ]]; then
    zdraw spansclip "$_ld_win" "$_zui_y" "$_ld_dx" "$_ld_dw" "$_ld_header[style]" "$_ld_detail" || return
  else
    _ld_body=(0 0 0 0)
  fi
  if (( _ld_split && _ld_selected_y >= 0 )); then
    local -i _ld_spine=$((_zui_x+_ld_lw+2)) _ld_top_y=$((_zui_y+2))
    if (( _ld_selected_y == _ld_top_y )); then
      zdraw fill "$_ld_win" "$_ld_top_y" "$((_zui_x+_ld_lw))" 1 5 "$_ld_header[style]" "$_ld_horizontal" || return
    else
      zdraw fill "$_ld_win" "$_ld_selected_y" "$((_zui_x+_ld_lw))" 1 2 "$_ld_header[style]" "$_ld_horizontal" || return
      zdraw spans "$_ld_win" "$_ld_selected_y" "$_ld_spine" "$_ld_header[style]" "$_ld_turn" || return
      zdraw fill "$_ld_win" "$((_ld_top_y+1))" "$_ld_spine" "$((_ld_selected_y-_ld_top_y-1))" 1 "$_ld_header[style]" "$_ld_vertical" || return
      zdraw spans "$_ld_win" "$_ld_top_y" "$_ld_spine" "$_ld_header[style]" "$_ld_top$_ld_horizontal$_ld_horizontal" || return
    fi
  fi
  zdraw_ui_list=("${(@kv)_ld_state}")
  zdraw_ui_link=(mode "$_ld_mode" visible "$_ld_visible" selected_row "$_ld_selected_y")
  reply=("${_ld_body[@]}")
}
