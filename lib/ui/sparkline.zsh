# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../../LICENCE
function zdraw-sparkline {
  emulate -L zsh
  (( $# >= 5 && $# <= 133 )) || return 1
  local _zui_win=$1 _zui_states=$5 _zui_token _zui_role _zui_glyph
  local _zui_palette=auto _zui_ramp='' _zui_missing='?' _zui_default_ramp _zui_default_fill
  local -i _zui_y _zui_x _zui_h _zui_w _zui_low _zui_high _zui_first _zui_i _zui_column
  local -a _zui_samples _zui_points _zui_tokens _zui_spans
  local -A zdraw_ui_style _zui_styles
  _zdraw_ui_chart_read || return
  _zdraw_ui_rect "$1" "$2" "$3" 1 "$4" || return
  for _zui_token in "${@:6}"; do
    case $_zui_token in
      palette=*) _zui_palette=${_zui_token#*=} ;;
      ramp=*) _zui_ramp=${_zui_token#*=}; [[ ${#_zui_ramp} == 8 ]] || return 1 ;;
      missing-char=*) _zui_missing=${_zui_token#*=} ;;
      *) _zui_tokens+=("$_zui_token") ;;
    esac
  done
  _zdraw_ui_chart_markers || return
  _zui_ramp=${_zui_ramp:-$_zui_default_ramp}
  for _zui_glyph in "${(@s::)_zui_ramp}" "$_zui_missing"; do
    [[ -n $_zui_glyph ]] || continue
    _zdraw_ui_chart_glyph "$_zui_glyph" || return
  done
  [[ -n $_zui_missing ]] || return 1
  for _zui_role in track positive negative missing positive,clipped negative,clipped; do
    zdraw-ui-style "$_zui_states,$_zui_role" fg=accent bg=surface negative:fg=error missing:fg=muted clipped:underline "${_zui_tokens[@]}" || return
    [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[px] == 0 && $zdraw_ui_style[py] == 0 && $zdraw_ui_style[align] == left ]] || return 1
    _zui_styles[$_zui_role]=$zdraw_ui_style[style]
  done
  _zdraw_ui_chart_project 7 || return
  _zui_first=$(( ${#_zui_samples} > _zui_w ? ${#_zui_samples}-_zui_w+1 : 1 ))
  # Draw in bounded chunks of 64 samples, after complete data/style validation.
  # Alternating styles cannot exceed the native span limit in one call.
  zdraw fill "$_zui_win" "$_zui_y" "$_zui_x" 1 "$_zui_w" "$_zui_styles[track]" ' ' || return
  _zui_column=$_zui_x
  for (( _zui_i=_zui_first; _zui_i<=${#_zui_samples}; _zui_i++ )); do
    if [[ $_zui_points[$_zui_i] == '-' ]]; then
      _zui_role=missing _zui_glyph=$_zui_missing
    else
      _zui_role=positive
      (( _zui_samples[$_zui_i] < 0 )) && _zui_role=negative
      (( _zui_samples[$_zui_i] < _zui_low || _zui_samples[$_zui_i] > _zui_high )) && _zui_role+=,clipped
      _zui_glyph=${_zui_ramp[$((_zui_points[$_zui_i]+1))]}
    fi
    _zui_spans+=("$_zui_styles[$_zui_role]" "$_zui_glyph")
    if (( ${#_zui_spans} == 128 || _zui_i == ${#_zui_samples} )); then
      zdraw spansclip "$_zui_win" "$_zui_y" "$_zui_column" "$(( ${#_zui_spans}/2 ))" "${_zui_spans[@]}" || return
      (( _zui_column += ${#_zui_spans}/2 ))
      _zui_spans=()
    fi
  done
  return 0
}
