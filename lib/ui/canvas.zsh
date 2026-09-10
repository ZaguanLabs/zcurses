function zdraw-canvas-init {
  emulate -L zsh
  [[ $# == 4 && ${(t)zdraw_ui_canvas} == (association|association-local) ]] || return 1
  local REPLY _zui_arg
  local -a _zui_bounds
  for _zui_arg in "$@"; do
    _zdraw_ui_chart_number "$_zui_arg" || return
    _zui_bounds+=("$REPLY")
  done
  (( _zui_bounds[1] < _zui_bounds[3] && _zui_bounds[2] < _zui_bounds[4] )) || return 1
  zdraw_ui_canvas=(format zdraw-canvas-1 count 0 xmin "$_zui_bounds[1]" ymin "$_zui_bounds[2]"
    xmax "$_zui_bounds[3]" ymax "$_zui_bounds[4]")
}

function _zdraw_ui_canvas_header {
  emulate -L zsh
  [[ ${(t)zdraw_ui_canvas} == association* && ${zdraw_ui_canvas[format]-} == zdraw-canvas-1 ]] || return 1
  local REPLY _zui_key
  _zui_bounds=()
  for _zui_key in xmin ymin xmax ymax; do
    _zdraw_ui_chart_number "${zdraw_ui_canvas[$_zui_key]-}" || return
    _zui_bounds+=("$REPLY")
  done
  (( _zui_bounds[1] < _zui_bounds[3] && _zui_bounds[2] < _zui_bounds[4] )) || return 1
  _zdraw_ui_uint "${zdraw_ui_canvas[count]-}" || return 1
  (( 10#$zdraw_ui_canvas[count] <= 256 ))
}

function _zdraw_ui_canvas_read {
  emulate -L zsh
  _zdraw_ui_canvas_header || return
  local REPLY _zui_kind _zui_key _zui_paint
  local -i _zui_index
  _zui_ops=()
  for (( _zui_index=1; _zui_index<=10#$zdraw_ui_canvas[count]; _zui_index++ )); do
    _zui_kind=${zdraw_ui_canvas[$_zui_index,kind]-} _zui_paint=${zdraw_ui_canvas[$_zui_index,paint]-}
    [[ $_zui_kind == (point|line|rect|fill) && $_zui_paint == (set|erase) ]] || return 1
    _zui_ops+=("$_zui_kind")
    for _zui_key in x0 y0 x1 y1; do
      _zdraw_ui_chart_number "${zdraw_ui_canvas[$_zui_index,$_zui_key]-}" || return
      _zui_ops+=("$REPLY")
    done
    _zui_ops+=("$_zui_paint")
  done
}

function zdraw-canvas-add {
  emulate -L zsh
  [[ $# -ge 3 && ${(t)zdraw_ui_canvas} == (association|association-local) ]] || return 1
  local -a _zui_bounds _zui_ops _zui_coordinates
  _zdraw_ui_canvas_read || return
  (( 10#$zdraw_ui_canvas[count] < 256 )) || return 1
  local _zui_kind=$1 _zui_paint=set _zui_arg REPLY
  local -i _zui_arity _zui_index=$((10#$zdraw_ui_canvas[count]+1))
  case $_zui_kind in
    point) _zui_arity=2 ;; line|rect|fill) _zui_arity=4 ;; *) return 1 ;;
  esac
  shift
  (( $# == _zui_arity || $# == _zui_arity+1 )) || return 1
  if (( $# > _zui_arity )); then _zui_paint=${@[-1]}; fi
  [[ $_zui_paint == (set|erase) ]] || return 1
  for _zui_arg in "${@:1:$_zui_arity}"; do
    _zdraw_ui_chart_number "$_zui_arg" || return
    _zui_coordinates+=("$REPLY")
  done
  [[ $_zui_kind == point ]] && _zui_coordinates+=("${_zui_coordinates[@]}")
  local -A _zui_new=("${(@kv)zdraw_ui_canvas}")
  _zui_new[$_zui_index,kind]=$_zui_kind _zui_new[$_zui_index,paint]=$_zui_paint
  _zui_new[$_zui_index,x0]=$_zui_coordinates[1] _zui_new[$_zui_index,y0]=$_zui_coordinates[2]
  _zui_new[$_zui_index,x1]=$_zui_coordinates[3] _zui_new[$_zui_index,y1]=$_zui_coordinates[4]
  _zui_new[count]=$_zui_index
  zdraw_ui_canvas=("${(@kv)_zui_new}")
}

function zdraw-canvas-clear {
  emulate -L zsh
  [[ $# == 0 && ${(t)zdraw_ui_canvas} == (association|association-local) ]] || return 1
  local -a _zui_bounds
  _zdraw_ui_canvas_header || return
  zdraw-canvas-init "${_zui_bounds[@]}"
}

# Clip a continuous segment to the world rectangle before rounding to pixels.
# Doubles avoid overflow for products of signed world coordinates. Iteration is
# capped, and every input came through the bounded decimal parser.
function _zdraw_ui_canvas_segment {
  emulate -L zsh
  local LC_NUMERIC=C
  local -F _zui_ax=$1 _zui_ay=$2 _zui_bx=$3 _zui_by=$4 _zui_tx _zui_ty
  local -i _zui_a _zui_b _zui_out _zui_attempt _zui_px0 _zui_py0 _zui_px1 _zui_py1
  _zui_segment=()
  for (( _zui_attempt=0; _zui_attempt<16; _zui_attempt++ )); do
    _zui_a=0 _zui_b=0
    (( _zui_ax < _zui_bounds[1] )) && (( _zui_a |= 1 ))
    (( _zui_ax > _zui_bounds[3] )) && (( _zui_a |= 2 ))
    (( _zui_ay < _zui_bounds[2] )) && (( _zui_a |= 4 ))
    (( _zui_ay > _zui_bounds[4] )) && (( _zui_a |= 8 ))
    (( _zui_bx < _zui_bounds[1] )) && (( _zui_b |= 1 ))
    (( _zui_bx > _zui_bounds[3] )) && (( _zui_b |= 2 ))
    (( _zui_by < _zui_bounds[2] )) && (( _zui_b |= 4 ))
    (( _zui_by > _zui_bounds[4] )) && (( _zui_b |= 8 ))
    if (( (_zui_a | _zui_b) == 0 )); then
      _zui_px0=$(((_zui_ax-_zui_bounds[1])*(_zui_pw-1)/(_zui_bounds[3]-_zui_bounds[1])+0.5))
      _zui_py0=$(((_zui_bounds[4]-_zui_ay)*(_zui_ph-1)/(_zui_bounds[4]-_zui_bounds[2])+0.5))
      _zui_px1=$(((_zui_bx-_zui_bounds[1])*(_zui_pw-1)/(_zui_bounds[3]-_zui_bounds[1])+0.5))
      _zui_py1=$(((_zui_bounds[4]-_zui_by)*(_zui_ph-1)/(_zui_bounds[4]-_zui_bounds[2])+0.5))
      _zui_segment=("$_zui_px0" "$_zui_py0" "$_zui_px1" "$_zui_py1")
      return 0
    fi
    (( _zui_a & _zui_b )) && return 0
    _zui_out=$((_zui_a ? _zui_a : _zui_b))
    if (( _zui_out & 8 )); then
      _zui_ty=$_zui_bounds[4]
      _zui_tx=$((_zui_ax+(_zui_bx-_zui_ax)*((_zui_ty-_zui_ay)/(_zui_by-_zui_ay))))
    elif (( _zui_out & 4 )); then
      _zui_ty=$_zui_bounds[2]
      _zui_tx=$((_zui_ax+(_zui_bx-_zui_ax)*((_zui_ty-_zui_ay)/(_zui_by-_zui_ay))))
    elif (( _zui_out & 2 )); then
      _zui_tx=$_zui_bounds[3]
      _zui_ty=$((_zui_ay+(_zui_by-_zui_ay)*((_zui_tx-_zui_ax)/(_zui_bx-_zui_ax))))
    else
      _zui_tx=$_zui_bounds[1]
      _zui_ty=$((_zui_ay+(_zui_by-_zui_ay)*((_zui_tx-_zui_ax)/(_zui_bx-_zui_ax))))
    fi
    if (( _zui_a )); then _zui_ax=$_zui_tx _zui_ay=$_zui_ty
    else _zui_bx=$_zui_tx _zui_by=$_zui_ty; fi
  done
  return 1
}

# Dot order in a Braille cell: left 1,2,3,7 and right 4,5,6,8.
function _zdraw_ui_canvas_pixel {
  emulate -L zsh
  (( _zui_work < 262144 )) || return 1
  (( _zui_work++ ))
  local -i _zui_cell=$((($2/4)*_zui_columns+$1/2+1))
  local -i _zui_bit=${_zui_bits[$((($1%2)*4+$2%4+1))]} _zui_mask=${_zui_masks[$_zui_cell]:-0}
  if [[ $_zui_paint == set ]]; then (( _zui_mask |= _zui_bit ))
  else (( _zui_mask &= (255 ^ _zui_bit) )); fi
  _zui_masks[$_zui_cell]=$_zui_mask
}

function _zdraw_ui_canvas_line {
  emulate -L zsh
  local -a _zui_segment
  if (( $1 > $3 || ($1 == $3 && $2 > $4) )); then
    _zdraw_ui_canvas_segment "$3" "$4" "$1" "$2" || return
  else
    _zdraw_ui_canvas_segment "$@" || return
  fi
  (( ${#_zui_segment} )) || return 0
  local -i _zui_x0=$_zui_segment[1] _zui_y0=$_zui_segment[2] _zui_x1=$_zui_segment[3] _zui_y1=$_zui_segment[4]
  local -i _zui_dx _zui_dy _zui_sx=1 _zui_sy=1 _zui_error _zui_twice _zui_swap
  # Canonical direction makes reversed endpoints produce the same tie-breaking.
  if (( _zui_x0 > _zui_x1 || (_zui_x0 == _zui_x1 && _zui_y0 > _zui_y1) )); then
    _zui_swap=$_zui_x0 _zui_x0=$_zui_x1 _zui_x1=$_zui_swap
    _zui_swap=$_zui_y0 _zui_y0=$_zui_y1 _zui_y1=$_zui_swap
  fi
  _zui_dx=$((_zui_x1-_zui_x0)) _zui_dy=$((_zui_y1-_zui_y0))
  (( _zui_dy < 0 )) && _zui_dy=$((-_zui_dy))
  (( _zui_y0 > _zui_y1 )) && _zui_sy=-1
  _zui_error=$((_zui_dx-_zui_dy))
  while true; do
    _zdraw_ui_canvas_pixel "$_zui_x0" "$_zui_y0" || return
    (( _zui_x0 == _zui_x1 && _zui_y0 == _zui_y1 )) && break
    _zui_twice=$((2*_zui_error))
    if (( _zui_twice > -_zui_dy )); then (( _zui_error-=_zui_dy, _zui_x0+=_zui_sx )); fi
    if (( _zui_twice < _zui_dx )); then (( _zui_error+=_zui_dx, _zui_y0+=_zui_sy )); fi
  done
  return 0
}

function zdraw-canvas-raster {
  emulate -L zsh
  [[ $# == 2 && ${(t)zdraw_ui_canvas_raster} == (association|association-local) ]] || return 1
  _zdraw_ui_uint "$1" && _zdraw_ui_uint "$2" || return 1
  local -i _zui_rows=$((10#$1)) _zui_columns=$((10#$2)) _zui_ph _zui_pw _zui_work=0
  (( _zui_rows > 0 && _zui_rows <= 256 && _zui_columns > 0 && _zui_columns <= 256 && _zui_rows*_zui_columns <= 4096 )) || return 1
  _zui_ph=$((_zui_rows*4)) _zui_pw=$((_zui_columns*2))
  local -a _zui_bounds _zui_ops _zui_segment _zui_bits=(1 2 4 64 8 16 32 128)
  local -A _zui_masks _zui_raster
  _zdraw_ui_canvas_read || return
  local _zui_kind _zui_paint
  local -i _zui_i _zui_x0 _zui_y0 _zui_x1 _zui_y1 _zui_x _zui_y _zui_mask _zui_bit _zui_pixels=0 _zui_cells=0
  for (( _zui_i=1; _zui_i<=${#_zui_ops}; _zui_i+=6 )); do
    _zui_kind=$_zui_ops[$_zui_i] _zui_x0=$_zui_ops[$((_zui_i+1))] _zui_y0=$_zui_ops[$((_zui_i+2))]
    _zui_x1=$_zui_ops[$((_zui_i+3))] _zui_y1=$_zui_ops[$((_zui_i+4))] _zui_paint=$_zui_ops[$((_zui_i+5))]
    case $_zui_kind in
      point) _zdraw_ui_canvas_line "$_zui_x0" "$_zui_y0" "$_zui_x0" "$_zui_y0" || return ;;
      line) _zdraw_ui_canvas_line "$_zui_x0" "$_zui_y0" "$_zui_x1" "$_zui_y1" || return ;;
      rect)
        _zdraw_ui_canvas_line "$_zui_x0" "$_zui_y0" "$_zui_x1" "$_zui_y0" || return
        _zdraw_ui_canvas_line "$_zui_x1" "$_zui_y0" "$_zui_x1" "$_zui_y1" || return
        _zdraw_ui_canvas_line "$_zui_x1" "$_zui_y1" "$_zui_x0" "$_zui_y1" || return
        _zdraw_ui_canvas_line "$_zui_x0" "$_zui_y1" "$_zui_x0" "$_zui_y0" || return ;;
      fill)
        _zui_x=$((_zui_x0 < _zui_x1 ? _zui_x0 : _zui_x1))
        _zui_x1=$((_zui_x0 > _zui_x1 ? _zui_x0 : _zui_x1)) _zui_x0=$_zui_x
        _zui_y=$((_zui_y0 < _zui_y1 ? _zui_y0 : _zui_y1))
        _zui_y1=$((_zui_y0 > _zui_y1 ? _zui_y0 : _zui_y1)) _zui_y0=$_zui_y
        (( _zui_x1 < _zui_bounds[1] || _zui_x0 > _zui_bounds[3] || _zui_y1 < _zui_bounds[2] || _zui_y0 > _zui_bounds[4] )) && continue
        (( _zui_x0 < _zui_bounds[1] )) && _zui_x0=$_zui_bounds[1]
        (( _zui_y0 < _zui_bounds[2] )) && _zui_y0=$_zui_bounds[2]
        (( _zui_x1 > _zui_bounds[3] )) && _zui_x1=$_zui_bounds[3]
        (( _zui_y1 > _zui_bounds[4] )) && _zui_y1=$_zui_bounds[4]
        _zdraw_ui_canvas_segment "$_zui_x0" "$_zui_y1" "$_zui_x1" "$_zui_y0" || return
        for (( _zui_y=_zui_segment[2]; _zui_y<=_zui_segment[4]; _zui_y++ )); do
          for (( _zui_x=_zui_segment[1]; _zui_x<=_zui_segment[3]; _zui_x++ )); do
            _zdraw_ui_canvas_pixel "$_zui_x" "$_zui_y" || return
          done
        done ;;
    esac
  done
  _zui_raster=(format zdraw-canvas-raster-1 rows "$_zui_rows" columns "$_zui_columns" writes "$_zui_work")
  for (( _zui_i=1; _zui_i<=_zui_rows*_zui_columns; _zui_i++ )); do
    _zui_mask=${_zui_masks[$_zui_i]:-0}
    _zui_raster[$_zui_i,mask]=$_zui_mask
    (( _zui_mask )) && (( _zui_cells++ ))
    for _zui_bit in "${_zui_bits[@]}"; do (( _zui_mask & _zui_bit )) && (( _zui_pixels++ )); done
  done
  _zui_raster[pixels]=$_zui_pixels _zui_raster[cells]=$_zui_cells
  zdraw_ui_canvas_raster=("${(@kv)_zui_raster}")
}

function _zdraw_ui_canvas_raster_read {
  emulate -L zsh
  [[ ${(t)zdraw_ui_canvas_raster} == association* && ${zdraw_ui_canvas_raster[format]-} == zdraw-canvas-raster-1 ]] || return 1
  _zdraw_ui_uint "${zdraw_ui_canvas_raster[rows]-}" && _zdraw_ui_uint "${zdraw_ui_canvas_raster[columns]-}" || return 1
  _zui_rows=$((10#$zdraw_ui_canvas_raster[rows])) _zui_columns=$((10#$zdraw_ui_canvas_raster[columns]))
  (( _zui_rows > 0 && _zui_rows <= 256 && _zui_columns > 0 && _zui_columns <= 256 && _zui_rows*_zui_columns <= 4096 )) || return 1
  local _zui_value
  local -i _zui_index
  _zui_masks=()
  for (( _zui_index=1; _zui_index<=_zui_rows*_zui_columns; _zui_index++ )); do
    _zui_value=${zdraw_ui_canvas_raster[$_zui_index,mask]-}
    _zdraw_ui_uint "$_zui_value" || return 1
    (( 10#$_zui_value <= 255 )) || return 1
    _zui_masks+=("$((10#$_zui_value))")
  done
}

# Encode the validated scratch raster supplied by the public caller. Keeping
# validation once per call avoids rescanning every cell in the draw path.
function _zdraw_ui_canvas_rows {
  emulate -L zsh
  local _zui_profile=$1 _zui_ink=${2-#} _zui_glyph _zui_escape _zui_row=''
  [[ $_zui_profile == (auto|ascii|block|braille) ]] || return 1
  local -i _zui_mask _zui_i _zui_supported=1
  local -a _zui_output _zui_probe
  local -A _zui_info _zui_glyphs
  # ASCII export works without a native module; custom ink is printable ASCII.
  [[ ${#_zui_ink} == 1 && $_zui_ink == [\ -\~] ]] || return 1
  if [[ $_zui_profile != ascii ]]; then
    _zui_glyph=⣿
    [[ $_zui_profile == block ]] && _zui_glyph=█
    if ! zmodload -e zdraw || ! builtin zdraw textinfo _zui_info "$_zui_glyph" 2>/dev/null || [[ ${_zui_info[width]-} != 1 ]]; then
      [[ $_zui_profile == auto ]] || return 2
      _zui_profile=ascii
    fi
  fi
  if [[ $_zui_profile != ascii ]]; then
    if [[ $_zui_profile == block ]]; then _zui_probe=(▀ ▄ █)
    else
      # Check every used Braille mask before assigning output (empty stays space).
      for _zui_mask in "${_zui_masks[@]}"; do
        (( _zui_mask && ! ${+_zui_glyphs[$_zui_mask]} )) || continue
        printf -v _zui_escape '\\u%04x' "$((10240+_zui_mask))" || return
        printf -v _zui_glyph '%b' "$_zui_escape" || return
        _zui_glyphs[$_zui_mask]=$_zui_glyph
      done
      _zui_probe=(⣿ "${(@v)_zui_glyphs}")
    fi
    if ! zmodload -e zdraw; then _zui_supported=0
    else
      for _zui_glyph in "${_zui_probe[@]}"; do
        if ! builtin zdraw textinfo _zui_info "$_zui_glyph" 2>/dev/null || [[ ${_zui_info[width]-} != 1 ]]; then _zui_supported=0; break; fi
      done
    fi
    if (( ! _zui_supported )); then
      [[ $_zui_profile == auto ]] || return 2
      _zui_profile=ascii
    elif [[ $_zui_profile == auto ]]; then _zui_profile=braille; fi
  fi
  for (( _zui_i=1; _zui_i<=${#_zui_masks}; _zui_i++ )); do
    _zui_mask=$_zui_masks[$_zui_i] _zui_glyph=' '
    if (( _zui_mask )); then
      case $_zui_profile in
        ascii) _zui_glyph=$_zui_ink ;;
        braille) _zui_glyph=$_zui_glyphs[$_zui_mask] ;;
        block)
          if (( (_zui_mask & 27) && (_zui_mask & 228) )); then _zui_glyph=█
          elif (( _zui_mask & 27 )); then _zui_glyph=▀
          else _zui_glyph=▄; fi ;;
      esac
    fi
    _zui_row+=$_zui_glyph
    if (( _zui_i % _zui_columns == 0 )); then _zui_output+=("$_zui_row"); _zui_row=''; fi
  done
  reply=("${_zui_output[@]}")
}

function zdraw-canvas-rows {
  emulate -L zsh
  [[ $# -ge 1 && $# -le 2 && ${(t)reply} == (array|array-local) ]] || return 1
  local -i _zui_rows _zui_columns
  local -a _zui_masks
  _zdraw_ui_canvas_raster_read || return
  _zdraw_ui_canvas_rows "$@"
}

# Draw a previously compiled raster, allowing cheap profile/theme changes.
function zdraw-canvas-draw {
  emulate -L zsh
  (( $# >= 4 && $# <= 132 )) || return 1
  local _zui_win=$1 _zui_profile=auto _zui_ink='#' _zui_token
  local -i _zui_rows _zui_columns _zui_y _zui_x _zui_h _zui_w _zui_i
  local -a _zui_masks reply _zui_tokens
  local -A zdraw_ui_style
  _zdraw_ui_canvas_raster_read || return
  _zdraw_ui_rect "$1" "$2" "$3" "$_zui_rows" "$_zui_columns" || return
  for _zui_token in "${@:5}"; do
    case $_zui_token in
      palette=*) _zui_profile=${_zui_token#*=} ;;
      ink-char=*) _zui_ink=${_zui_token#*=} ;;
      *) _zui_tokens+=("$_zui_token") ;;
    esac
  done
  zdraw-ui-style "$4" fg=accent bg=surface "${_zui_tokens[@]}" || return
  [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[px] == 0 && $zdraw_ui_style[py] == 0 && $zdraw_ui_style[align] == left ]] || return 1
  _zdraw_ui_canvas_rows "$_zui_profile" "$_zui_ink" || return
  for (( _zui_i=1; _zui_i<=_zui_rows; _zui_i++ )); do
    zdraw spansclip "$_zui_win" "$((_zui_y+_zui_i-1))" "$_zui_x" "$_zui_columns" "$zdraw_ui_style[style]" "$reply[$_zui_i]" || return
  done
  return 0
}

# Convenience path: compile for this rectangle, then replace its contents.
function zdraw-canvas {
  emulate -L zsh
  (( $# >= 6 )) || return 1
  local -A zdraw_ui_canvas_raster
  zdraw-canvas-raster "$4" "$5" || return
  zdraw-canvas-draw "$1" "$2" "$3" "${@:6}"
}
