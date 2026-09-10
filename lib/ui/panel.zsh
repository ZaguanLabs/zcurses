function zdraw-panel {
  emulate -L zsh
  [[ $# -ge 7 && ${(t)reply} == (array|array-local) ]] || return 1
  local _zui_win=$1 _zui_title=$6 _zui_state=$7
  local -i _zui_y _zui_x _zui_h _zui_w _zui_edge=0 _zui_cy _zui_cx _zui_ch _zui_cw
  local -A zdraw_ui_style _zui_panel _zui_heading _zui_text
  local -a _zui_glyphs _zui_tokens=(fg=text bg=surface border=ascii border-fg=border
    px=1 py=0 focus:border-fg=accent title:bold "${@:8}")
  _zdraw_ui_rect "${@:1:5}" || return
  (( ${#_zui_title} <= 262144 )) || return 1
  zdraw textinfo _zui_text "$_zui_title" || return
  zdraw-ui-style "$_zui_state" "${_zui_tokens[@]}" || return
  _zui_panel=("${(@kv)zdraw_ui_style}")
  zdraw-ui-style "$_zui_state,title" "${_zui_tokens[@]}" || return
  _zui_heading=("${(@kv)zdraw_ui_style}")
  if [[ $_zui_panel[border] != none ]] && (( _zui_h >= 2 && _zui_w >= 2 )); then
    _zui_edge=1
    case $_zui_panel[border] in
      rounded) _zui_glyphs=('│' '─' '╭' '╮' '╰' '╯') ;;
      double) _zui_glyphs=('║' '═' '╔' '╗' '╚' '╝') ;;
      *) _zui_glyphs=('|' '-' '+' '+' '+' '+') ;;
    esac
    if (( ! ${zdraw_features[(Ie)wide_spans]} )) ||
       ! zdraw textinfo _zui_text "$_zui_glyphs[1]" 2>/dev/null ||
       [[ $_zui_text[width] != 1 ]]; then
      _zui_glyphs=('|' '-' '+' '+' '+' '+')
    fi
  fi
  # Insets may consume all content. Return an empty content rectangle instead
  # of drawing beyond the frame or asking curses to create a zero-size window.
  _zui_cy=$(( _zui_y + _zui_edge )) _zui_cx=$(( _zui_x + _zui_edge ))
  _zui_ch=$(( _zui_h - 2 * _zui_edge )) _zui_cw=$(( _zui_w - 2 * _zui_edge ))
  _zui_cy=$(( _zui_cy + (_zui_panel[py] < _zui_ch ? _zui_panel[py] : _zui_ch) ))
  _zui_cx=$(( _zui_cx + (_zui_panel[px] < _zui_cw ? _zui_panel[px] : _zui_cw) ))
  _zui_ch=$(( _zui_ch > 2 * _zui_panel[py] ? _zui_ch - 2 * _zui_panel[py] : 0 ))
  _zui_cw=$(( _zui_cw > 2 * _zui_panel[px] ? _zui_cw - 2 * _zui_panel[px] : 0 ))
  zdraw fill "$_zui_win" "$_zui_y" "$_zui_x" "$_zui_h" "$_zui_w" "$_zui_panel[style]" ' ' || return
  if (( _zui_edge )); then
    if (( _zui_w > 2 )); then
      zdraw fill "$_zui_win" "$_zui_y" "$((_zui_x+1))" 1 "$((_zui_w-2))" "$_zui_panel[border-style]" "$_zui_glyphs[2]" || return
      zdraw fill "$_zui_win" "$((_zui_y+_zui_h-1))" "$((_zui_x+1))" 1 "$((_zui_w-2))" "$_zui_panel[border-style]" "$_zui_glyphs[2]" || return
    fi
    if (( _zui_h > 2 )); then
      zdraw fill "$_zui_win" "$((_zui_y+1))" "$_zui_x" "$((_zui_h-2))" 1 "$_zui_panel[border-style]" "$_zui_glyphs[1]" || return
      zdraw fill "$_zui_win" "$((_zui_y+1))" "$((_zui_x+_zui_w-1))" "$((_zui_h-2))" 1 "$_zui_panel[border-style]" "$_zui_glyphs[1]" || return
    fi
    zdraw spans "$_zui_win" "$_zui_y" "$_zui_x" "$_zui_panel[border-style]" "$_zui_glyphs[3]" || return
    zdraw spans "$_zui_win" "$_zui_y" "$((_zui_x+_zui_w-1))" "$_zui_panel[border-style]" "$_zui_glyphs[4]" || return
    zdraw spans "$_zui_win" "$((_zui_y+_zui_h-1))" "$_zui_x" "$_zui_panel[border-style]" "$_zui_glyphs[5]" || return
    zdraw spans "$_zui_win" "$((_zui_y+_zui_h-1))" "$((_zui_x+_zui_w-1))" "$_zui_panel[border-style]" "$_zui_glyphs[6]" || return
    _zdraw_ui_row "$_zui_win" "$_zui_y" "$((_zui_x+1))" "$((_zui_w-2))" "$_zui_heading[align]" "$_zui_title" "$_zui_heading[style]" || return
  elif [[ -n $_zui_title ]] && (( _zui_ch && _zui_cw )); then
    _zdraw_ui_row "$_zui_win" "$_zui_cy" "$_zui_cx" "$_zui_cw" "$_zui_heading[align]" "$_zui_title" "$_zui_heading[style]" || return
    (( _zui_cy++, _zui_ch-- ))
  fi
  reply=("$_zui_cy" "$_zui_cx" "$_zui_ch" "$_zui_cw")
}
