# Internal helpers reserve _zui_* locals. Public results use documented,
# caller-owned parameters through Zsh dynamic scope. No strings are evaluated.
function _zdraw_ui_uint {
  emulate -L zsh
  [[ $1 == <-> && ${#1} -le 5 ]] && (( 10#$1 <= 32767 ))
}

function _zdraw_ui_color {
  emulate -L zsh
  local _zui_color=$1
  if [[ $_zui_color == default || $_zui_color == \#[[:xdigit:]][[:xdigit:]][[:xdigit:]][[:xdigit:]][[:xdigit:]][[:xdigit:]] ]]; then
    return 0
  fi
  [[ $_zui_color == <-> && ${#_zui_color} -le 3 ]] && (( 10#$_zui_color <= 255 ))
}

function zdraw-ui-theme {
  emulate -L zsh
  [[ ${(t)zdraw_ui_theme} == (association|association-local) && $# -ge 1 ]] || return 1
  local _zui_name=$1 _zui_profile=${2:-${NO_COLOR:+mono}} _zui_pair _zui_key _zui_value
  local -A _zui_theme
  _zui_profile=${_zui_profile:-16}
  case $_zui_name in
    dark) _zui_theme=(canvas 0 surface 0 text 7 muted 6 accent 6 border 4
                     selection 6 on-selection 0 inactive 4 on-inactive 7 error 1) ;;
    light) _zui_theme=(canvas 7 surface 7 text 0 muted 4 accent 4 border 6
                      selection 4 on-selection 7 inactive 6 on-inactive 0 error 1) ;;
    *) return 1 ;;
  esac
  case $_zui_profile in
    16) ;;
    256)
      if [[ $_zui_name == dark ]]; then
        _zui_theme=(canvas 234 surface 236 text 252 muted 245 accent 80 border 240
                    selection 30 on-selection 231 inactive 238 on-inactive 252 error 210)
      else
        _zui_theme=(canvas 255 surface 231 text 235 muted 242 accent 24 border 250
                    selection 24 on-selection 231 inactive 253 on-inactive 235 error 124)
      fi ;;
    mono)
      for _zui_key in "${(@k)_zui_theme}"; do _zui_theme[$_zui_key]=default; done ;;
    *) return 1 ;;
  esac
  shift
  (( $# )) && shift
  (( $# <= 32 )) || return 1
  for _zui_pair in "$@"; do
    [[ $_zui_pair == *=* ]] || return 1
    _zui_key=${_zui_pair%%=*} _zui_value=${_zui_pair#*=}
    case $_zui_key in
      canvas|surface|text|muted|accent|border|selection|on-selection|inactive|on-inactive|error) ;;
      *) return 1 ;;
    esac
    _zdraw_ui_color "$_zui_value" || return 1
    # Canonical spelling keeps numeric aliases from consuming extra color pairs.
    [[ $_zui_value == <-> ]] && _zui_value=$(( 10#$_zui_value ))
    _zui_theme[$_zui_key]=${(L)_zui_value}
  done
  _zui_theme[name]=$_zui_name _zui_theme[profile]=$_zui_profile
  zdraw_ui_theme=("${(@kv)_zui_theme}")
}

# Applies one validated property to the resolver's local association.
function _zdraw_ui_property {
  emulate -L zsh
  local _zui_key=${1%%=*} _zui_value=${1#*=}
  case $1 in
    bold|underline|reverse) _zui_resolved[$1]=1; return 0 ;;
    no-bold|no-underline|no-reverse) _zui_resolved[${1#no-}]=0; return 0 ;;
  esac
  [[ $1 == *=* ]] || return 1
  case $_zui_key in
    fg|bg|border-fg)
      case $_zui_value in
        canvas|surface|text|muted|accent|border|selection|on-selection|inactive|on-inactive|error)
          [[ ${(t)zdraw_ui_theme} == association* ]] || return 1
          _zui_value=${zdraw_ui_theme[$_zui_value]-} ;;
      esac
      _zdraw_ui_color "$_zui_value" || return 1
      [[ $_zui_value == <-> ]] && _zui_value=$(( 10#$_zui_value ))
      _zui_value=${(L)_zui_value} ;;
    px|py)
      [[ $_zui_value == <-> && ${#_zui_value} -le 2 ]] || return 1
      (( 10#$_zui_value <= 16 )) || return 1
      _zui_value=$(( 10#$_zui_value )) ;;
    border) [[ $_zui_value == (none|ascii|rounded|double) ]] || return 1 ;;
    align) [[ $_zui_value == (left|center|right) ]] || return 1 ;;
    *) return 1 ;;
  esac
  _zui_resolved[$_zui_key]=$_zui_value
}

function zdraw-ui-style {
  emulate -L zsh
  [[ ${(t)zdraw_ui_style} == (association|association-local) && $# -ge 1 && $# -le 129 ]] || return 1
  local -a _zui_states=("${(@s:,:)1}") _zui_conditions _zui_base _zui_variants
  local _zui_token _zui_condition _zui_property _zui_flag _zui_style=''
  local -i _zui_match
  local -A _zui_resolved=(fg default bg default border-fg default
    border none px 0 py 0 align left bold 0 underline 0 reverse 0)
  for _zui_flag in "${_zui_states[@]}"; do
    [[ $_zui_flag == (normal|focus|selected|inactive|disabled|empty|title|header|alternate|filled|track|label|key|invalid|cursor|heading|subheading|paragraph|bullet|quote|code|separator|spacer|positive|negative|axis|missing|clipped) ]] || return 1
  done
  (( ${#_zui_states} )) || return 1
  shift
  # Validate even inactive variants. Resolve into scratch storage, then replay
  # ordinary utilities followed by matching variants in their declaration order.
  for _zui_token in "$@"; do
    (( ${#_zui_token} <= 128 )) || return 1
    if [[ $_zui_token == *:* ]]; then
      _zui_condition=${_zui_token%%:*} _zui_property=${_zui_token#*:}
      _zui_conditions=("${(@s:+:)_zui_condition}")
      (( ${#_zui_conditions} )) || return 1
      _zui_match=1
      for _zui_flag in "${_zui_conditions[@]}"; do
        [[ $_zui_flag == (normal|focus|selected|inactive|disabled|empty|title|header|alternate|filled|track|label|key|invalid|cursor|heading|subheading|paragraph|bullet|quote|code|separator|spacer|positive|negative|axis|missing|clipped) ]] || return 1
        (( ${_zui_states[(Ie)$_zui_flag]} )) || _zui_match=0
      done
      _zdraw_ui_property "$_zui_property" || return 1
      (( _zui_match )) && _zui_variants+=("$_zui_property")
    else
      _zdraw_ui_property "$_zui_token" || return 1
      _zui_base+=("$_zui_token")
    fi
  done
  _zui_resolved=(fg default bg default border-fg default
    border none px 0 py 0 align left bold 0 underline 0 reverse 0)
  for _zui_token in "${_zui_base[@]}" "${_zui_variants[@]}"; do
    _zdraw_ui_property "$_zui_token" || return 1
  done
  for _zui_flag in bold underline reverse; do
    (( _zui_resolved[$_zui_flag] )) && _zui_style+="$_zui_flag,"
  done
  if [[ $_zui_resolved[fg] == default && $_zui_resolved[bg] == default ]]; then
    _zui_style=${_zui_style%,}
  else
    _zui_style+="$_zui_resolved[fg]/$_zui_resolved[bg]"
  fi
  _zui_resolved[style]=$_zui_style
  if [[ $_zui_resolved[border-fg] == default && $_zui_resolved[bg] == default ]]; then
    _zui_resolved[border-style]=''
  else
    _zui_resolved[border-style]="$_zui_resolved[border-fg]/$_zui_resolved[bg]"
  fi
  zdraw_ui_style=("${(@kv)_zui_resolved}")
}

# Validates all geometry before integer assignment or native drawing. The
# caller owns the prefixed integer locals populated here.
function _zdraw_ui_rect {
  emulate -L zsh
  local _zui_number
  local -a _zui_position
  (( $# == 5 )) || return 1
  for _zui_number in "${@:2}"; do _zdraw_ui_uint "$_zui_number" || return 1; done
  _zui_y=$((10#$2)) _zui_x=$((10#$3)) _zui_h=$((10#$4)) _zui_w=$((10#$5))
  (( _zui_h > 0 && _zui_w > 0 && _zui_h * _zui_w <= 262144 )) || return 1
  zdraw position "$1" _zui_position || return
  (( _zui_y + _zui_h <= _zui_position[5] && _zui_x + _zui_w <= _zui_position[6] ))
}

# A single clipped/aligned row. Clearing is separate so components can batch
# backgrounds, and all calls retain the native window's cursor and style.
function _zdraw_ui_row {
  emulate -L zsh
  local -A _zui_text
  local -i _zui_column=$3 _zui_width=$4
  (( _zui_width > 0 )) || return 0
  zdraw textinfo _zui_text "$6" "$_zui_width" || return
  case $5 in
    right) (( _zui_column += _zui_width - _zui_text[width] )) ;;
    center) (( _zui_column += (_zui_width - _zui_text[width]) / 2 )) ;;
  esac
  [[ -n $_zui_text[text] ]] || return 0
  zdraw spansclip "$1" "$2" "$_zui_column" "$_zui_text[width]" "$7" "$_zui_text[text]"
}

function zdraw-label {
  emulate -L zsh
  (( $# >= 6 )) || return 1
  local _zui_win=$1 _zui_label=$5
  local -i _zui_y _zui_x _zui_h _zui_w
  local -A zdraw_ui_style _zui_info
  _zdraw_ui_rect "$1" "$2" "$3" 1 "$4" || return
  (( ${#_zui_label} <= 262144 )) || return 1
  zdraw textinfo _zui_info "$_zui_label" || return
  zdraw-ui-style "$6" fg=text bg=surface "${@:7}" || return
  [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[py] == 0 ]] || return 1
  zdraw fill "$_zui_win" "$_zui_y" "$_zui_x" 1 "$_zui_w" "$zdraw_ui_style[style]" ' ' || return
  _zdraw_ui_row "$_zui_win" "$_zui_y" "$((_zui_x+zdraw_ui_style[px]))" "$((_zui_w-2*zdraw_ui_style[px]))" "$zdraw_ui_style[align]" "$_zui_label" "$zdraw_ui_style[style]"
}
