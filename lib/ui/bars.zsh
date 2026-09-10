# One sample per row. Labels and units are deliberately separate components.
function zdraw-bars {
  emulate -L zsh
  (( $# >= 6 && $# <= 134 )) || return 1
  local _zui_win=$1 _zui_states=$6 _zui_token _zui_role _zui_glyph
  local _zui_palette=auto _zui_fill='' _zui_negative='' _zui_axis='|' _zui_missing='?' _zui_track=' '
  local _zui_default_ramp _zui_default_fill
  local -i _zui_y _zui_x _zui_h _zui_w _zui_low _zui_high _zui_zero _zui_i _zui_end _zui_start _zui_length
  local -a _zui_samples _zui_points _zui_tokens
  local -A zdraw_ui_style _zui_styles
  _zdraw_ui_chart_read || return
  # Unlike a sparkline, a bar's length is meaningful only with a zero origin.
  (( _zui_low <= 0 && _zui_high >= 0 )) || return 1
  _zdraw_ui_rect "$1" "$2" "$3" "$4" "$5" || return
  for _zui_token in "${@:7}"; do
    case $_zui_token in
      palette=*) _zui_palette=${_zui_token#*=} ;;
      fill-char=*) _zui_fill=${_zui_token#*=}; _zdraw_ui_chart_glyph "$_zui_fill" || return ;;
      negative-char=*) _zui_negative=${_zui_token#*=}; _zdraw_ui_chart_glyph "$_zui_negative" || return ;;
      axis-char=*) _zui_axis=${_zui_token#*=} ;;
      missing-char=*) _zui_missing=${_zui_token#*=} ;;
      track-char=*) _zui_track=${_zui_token#*=} ;;
      *) _zui_tokens+=("$_zui_token") ;;
    esac
  done
  _zdraw_ui_chart_markers || return
  _zui_fill=${_zui_fill:-$_zui_default_fill} _zui_negative=${_zui_negative:-$_zui_fill}
  for _zui_glyph in "$_zui_fill" "$_zui_negative" "$_zui_axis" "$_zui_missing" "$_zui_track"; do
    _zdraw_ui_chart_glyph "$_zui_glyph" || return
  done
  for _zui_role in track positive negative axis missing positive,clipped negative,clipped axis,clipped; do
    zdraw-ui-style "$_zui_states,$_zui_role" fg=accent bg=surface negative:fg=error axis:fg=border missing:fg=muted clipped:underline "${_zui_tokens[@]}" || return
    [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[px] == 0 && $zdraw_ui_style[py] == 0 && $zdraw_ui_style[align] == left ]] || return 1
    _zui_styles[$_zui_role]=$zdraw_ui_style[style]
  done
  _zdraw_ui_chart_project "$((_zui_w-1))" || return
  _zui_zero=$(( (0-_zui_low)*(_zui_w-1)/(_zui_high-_zui_low) ))
  zdraw fill "$_zui_win" "$_zui_y" "$_zui_x" "$_zui_h" "$_zui_w" "$_zui_styles[track]" "$_zui_track" || return
  for (( _zui_i=1; _zui_i<=${#_zui_samples} && _zui_i<=_zui_h; _zui_i++ )); do
    _zui_glyph=$_zui_axis _zui_role=axis
    if [[ $_zui_points[$_zui_i] == '-' ]]; then
      _zui_glyph=$_zui_missing _zui_role=missing
    else
      _zui_end=$_zui_points[$_zui_i]
      if (( _zui_end != _zui_zero )); then
        _zui_role=positive _zui_glyph=$_zui_fill
        _zui_start=$((_zui_zero+1)) _zui_length=$((_zui_end-_zui_zero))
        if (( _zui_end < _zui_zero )); then
          _zui_role=negative _zui_glyph=$_zui_negative
          _zui_start=$_zui_end _zui_length=$((_zui_zero-_zui_end))
        fi
        (( _zui_samples[$_zui_i] < _zui_low || _zui_samples[$_zui_i] > _zui_high )) && _zui_role+=,clipped
        zdraw fill "$_zui_win" "$((_zui_y+_zui_i-1))" "$((_zui_x+_zui_start))" 1 "$_zui_length" "$_zui_styles[$_zui_role]" "$_zui_glyph" || return
      fi
      _zui_glyph=$_zui_axis _zui_role=axis
      # Clamping to the zero endpoint (or a one-column viewport) leaves no bar
      # cells. Keep the clipped indicator on the axis instead of losing it.
      if (( _zui_end == _zui_zero && (_zui_samples[$_zui_i] < _zui_low || _zui_samples[$_zui_i] > _zui_high) )); then
        _zui_role=axis,clipped
      fi
    fi
    zdraw fill "$_zui_win" "$((_zui_y+_zui_i-1))" "$((_zui_x+_zui_zero))" 1 1 "$_zui_styles[$_zui_role]" "$_zui_glyph" || return
  done
  return 0
}
