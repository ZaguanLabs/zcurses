# Caller-owned zdraw_ui_image data; _zi_* and _zui_* locals are reserved.
function zdraw-image-load {
  emulate -L zsh
  [[ $# == 2 && ${(t)zdraw_ui_image} == (association|association-local) && ${#1} -le 8500 && ${#2} -le 256 && -n $2 ]] || return 1
  local _zi_packet=${1%$'\n'} _zi_line
  local -a _zi_lines=("${(@f)_zi_packet}") _zi_header
  local -A _zi_new _zi_alt
  _zi_header=("${(@s: :)_zi_lines[1]}")
  [[ ${#_zi_header} == 3 && $_zi_header[1] == zdraw-image-1 ]] || return 1
  _zdraw_ui_uint "$_zi_header[2]" && _zdraw_ui_uint "$_zi_header[3]" || return 1
  local -i _zi_rows=$((10#$_zi_header[2])) _zi_columns=$((10#$_zi_header[3])) _zi_i=0
  (( _zi_rows > 0 && _zi_rows <= 64 && _zi_columns > 0 && _zi_columns <= 128 && _zi_rows*_zi_columns <= 4096 && ${#_zi_lines} == 1+2*_zi_rows )) || return 1
  zdraw textpos _zi_alt "$2" byte 0 || return
  (( _zi_alt[total_bytes] <= 256 )) || return 1
  _zi_new=(format zdraw-image-1 rows "$_zi_rows" columns "$_zi_columns" alt "$2")
  for _zi_line in "${_zi_lines[@]:1}"; do
    [[ ${#_zi_line} == $_zi_columns && $_zi_line != *[^0-9a-f]* ]] || return 1
    (( _zi_i++ ))
    _zi_new[$_zi_i,pixels]=$_zi_line
  done
  zdraw_ui_image=("${(@kv)_zi_new}")
}

function _zdraw_image_read {
  emulate -L zsh
  [[ ${(t)zdraw_ui_image} == association* && ${zdraw_ui_image[format]-} == zdraw-image-1 ]] || return 1
  _zdraw_ui_uint "${zdraw_ui_image[rows]-}" && _zdraw_ui_uint "${zdraw_ui_image[columns]-}" || return 1
  _zi_rows=$((10#$zdraw_ui_image[rows])) _zi_columns=$((10#$zdraw_ui_image[columns]))
  (( _zi_rows > 0 && _zi_rows <= 64 && _zi_columns > 0 && _zi_columns <= 128 && _zi_rows*_zi_columns <= 4096 )) || return 1
  local -i _zi_i
  local _zi_line
  _zi_pixels=()
  for (( _zi_i=1; _zi_i<=2*_zi_rows; _zi_i++ )); do
    _zi_line=${zdraw_ui_image[$_zi_i,pixels]-}
    [[ ${#_zi_line} == $_zi_columns && $_zi_line != *[^0-9a-f]* ]] || return 1
    _zi_pixels+=("$_zi_line")
  done
}

function _zdraw_image_ascii {
  emulate -L zsh
  # Integer luminance of the documented 16-color palette; two pixels per cell.
  local -a _zi_luma=(0 27 92 119 9 36 101 192 128 54 182 237 18 73 201 255)
  local _zi_ramp=' .:-=+*#%@'
  REPLY=${_zi_ramp[$((1+(_zi_luma[$1+1]+_zi_luma[$2+1])*9/510))]}
}

function zdraw-image-rows {
  emulate -L zsh
  [[ $# == 0 && ${(t)reply} == (array|array-local) ]] || return 1
  local -i _zi_rows _zi_columns _zi_y _zi_x _zi_top _zi_bottom
  local -a _zi_pixels _zi_output
  local _zi_line REPLY
  _zdraw_image_read || return
  for (( _zi_y=1; _zi_y<=_zi_rows; _zi_y++ )); do
    _zi_line=''
    for (( _zi_x=1; _zi_x<=_zi_columns; _zi_x++ )); do
      _zi_top=$((16#${_zi_pixels[2*_zi_y-1][$_zi_x]})) _zi_bottom=$((16#${_zi_pixels[2*_zi_y][$_zi_x]}))
      _zdraw_image_ascii "$_zi_top" "$_zi_bottom"
      _zi_line+=$REPLY
    done
    _zi_output+=("$_zi_line")
  done
  reply=("${_zi_output[@]}")
}

function zdraw-image-draw {
  emulate -L zsh
  (( $# >= 6 && $# <= 134 )) || return 1
  local -i _zi_rows _zi_columns _zui_y _zui_x _zui_h _zui_w _zi_y _zi_x _zi_top _zi_bottom
  local -a _zi_pixels _zi_tokens _zi_spans
  local -A zdraw_ui_style _zi_info _zi_colors
  local _zi_palette=auto _zi_color=image _zi_token _zi_attributes='' _zi_style _zi_glyph REPLY
  _zdraw_image_read || return
  _zdraw_ui_rect "$1" "$2" "$3" "$4" "$5" || return
  (( _zui_h*_zui_w <= 4096 )) || return 1
  for _zi_token in "${@:7}"; do
    case $_zi_token in
      palette=*) _zi_palette=${_zi_token#*=} ;;
      colors=*) _zi_color=${_zi_token#*=} ;;
      *) _zi_tokens+=("$_zi_token") ;;
    esac
  done
  [[ $_zi_palette == (auto|ascii|block) && $_zi_color == (image|theme) ]] || return 1
  zdraw-ui-style "$6" fg=text bg=surface "${_zi_tokens[@]}" || return
  [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[px] == 0 && $zdraw_ui_style[py] == 0 && $zdraw_ui_style[align] == left ]] || return 1
  zdraw colorinfo _zi_colors || return
  if [[ ${zdraw_ui_theme[profile]-} == mono || -n ${NO_COLOR:-} ]] || (( _zi_colors[colors] < 16 )); then _zi_color=theme; fi
  if [[ $_zi_palette != ascii ]]; then
    if [[ $_zi_color != image ]] || ! zdraw textinfo _zi_info '▀' 2>/dev/null || [[ ${_zi_info[width]-} != 1 ]]; then
      [[ $_zi_palette == auto ]] || return 2
      _zi_palette=ascii
    else _zi_palette=block; fi
  fi
  for _zi_token in bold underline reverse; do
    [[ $zdraw_ui_style[$_zi_token] == 1 ]] && _zi_attributes+="$_zi_token,"
  done
  zdraw fill "$1" "$_zui_y" "$_zui_x" "$_zui_h" "$_zui_w" "$zdraw_ui_style[style]" ' ' || return
  for (( _zi_y=1; _zi_y<=_zi_rows && _zi_y<=_zui_h; _zi_y++ )); do
    _zi_spans=()
    for (( _zi_x=1; _zi_x<=_zi_columns && _zi_x<=_zui_w; _zi_x++ )); do
      _zi_top=$((16#${_zi_pixels[2*_zi_y-1][$_zi_x]})) _zi_bottom=$((16#${_zi_pixels[2*_zi_y][$_zi_x]}))
      if [[ $_zi_palette == block ]]; then
        _zi_glyph=▀ _zi_style="$_zi_attributes$_zi_top/$_zi_bottom"
      else
        _zdraw_image_ascii "$_zi_top" "$_zi_bottom"
        _zi_glyph=$REPLY _zi_style=$zdraw_ui_style[style]
        [[ $_zi_color == image ]] && _zi_style="$_zi_attributes$_zi_top/$zdraw_ui_style[bg]"
      fi
      _zi_spans+=("$_zi_style" "$_zi_glyph")
    done
    zdraw spansclip "$1" "$((_zui_y+_zi_y-1))" "$_zui_x" "$_zui_w" "${_zi_spans[@]}" || return
  done
  return 0
}
