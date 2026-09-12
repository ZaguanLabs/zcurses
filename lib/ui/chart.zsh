# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../../LICENCE
# Bounded signed decimal data, never arithmetic expressions. REPLY is caller-owned.
function _zdraw_ui_chart_number {
  emulate -L zsh
  local _zui_digits=${1#-}
  [[ $_zui_digits == <-> && ${#_zui_digits} -le 5 ]] &&
    (( 10#$_zui_digits <= 32767 )) || return 1
  REPLY=$((10#$_zui_digits))
  [[ $1 == -* ]] && REPLY=$((-REPLY))
  return 0
}

function zdraw-chart-series {
  emulate -L zsh
  [[ ${(t)zdraw_ui_chart} == (association|association-local) && $# -ge 2 ]] || return 1
  local _zui_mode=$1 _zui_sample REPLY
  local -i _zui_low=0 _zui_high=0 _zui_i=0 _zui_valid=0 _zui_missing=0 _zui_below=0 _zui_above=0 _zui_min=0 _zui_max=0 _zui_value
  local -A _zui_series=(format zdraw-chart-1 mode "$_zui_mode")
  shift
  case $_zui_mode in
    auto) ;;
    fixed)
      (( $# >= 3 )) || return 1
      _zdraw_ui_chart_number "$1" || return
      _zui_low=$REPLY
      _zdraw_ui_chart_number "$2" || return
      _zui_high=$REPLY
      (( _zui_low < _zui_high )) || return 1
      shift 2 ;;
    *) return 1 ;;
  esac
  [[ $1 == -- ]] || return 1
  shift
  (( $# <= 4096 )) || return 1
  for _zui_sample in "$@"; do
    (( _zui_i++ ))
    if [[ $_zui_sample == '-' ]]; then
      _zui_series[$_zui_i,value]='-'
      (( _zui_missing++ ))
      continue
    fi
    _zdraw_ui_chart_number "$_zui_sample" || return
    _zui_value=$REPLY
    _zui_series[$_zui_i,value]=$_zui_value
    if (( _zui_valid == 0 )); then _zui_min=$_zui_value _zui_max=$_zui_value; fi
    (( _zui_value < _zui_min )) && _zui_min=$_zui_value
    (( _zui_value > _zui_max )) && _zui_max=$_zui_value
    (( _zui_valid++ ))
  done
  if [[ $_zui_mode == auto ]]; then
    # Zero is always included: constant positive/negative series remain useful.
    _zui_low=$((_zui_min < 0 ? _zui_min : 0))
    _zui_high=$((_zui_max > 0 ? _zui_max : 0))
    (( _zui_low == _zui_high )) && _zui_high=1
  fi
  for (( _zui_i=1; _zui_i<=$#; _zui_i++ )); do
    [[ $_zui_series[$_zui_i,value] == '-' ]] && continue
    _zui_value=$_zui_series[$_zui_i,value]
    (( _zui_value < _zui_low )) && (( _zui_below++ ))
    (( _zui_value > _zui_high )) && (( _zui_above++ ))
  done
  _zui_series[count]=$# _zui_series[valid]=$_zui_valid _zui_series[missing]=$_zui_missing
  _zui_series[low]=$_zui_low _zui_series[high]=$_zui_high
  _zui_series[below]=$_zui_below _zui_series[above]=$_zui_above
  _zui_series[data_min]=${_zui_min} _zui_series[data_max]=${_zui_max}
  if (( ! _zui_valid )); then _zui_series[data_min]=unknown _zui_series[data_max]=unknown; fi
  _zui_series[latest]=unknown
  (( $# )) && _zui_series[latest]=$_zui_series[$#,value]
  zdraw_ui_chart=("${(@kv)_zui_series}")
}

# Readers validate retained numeric data again before using it in arithmetic.
# Caller owns _zui_low, _zui_high and _zui_samples scratch variables.
function _zdraw_ui_chart_read {
  emulate -L zsh
  [[ ${(t)zdraw_ui_chart} == association* && ${zdraw_ui_chart[format]-} == zdraw-chart-1 ]] || return 1
  local REPLY _zui_sample
  local -i _zui_index
  _zdraw_ui_uint "${zdraw_ui_chart[count]-}" || return 1
  (( 10#$zdraw_ui_chart[count] <= 4096 )) || return 1
  _zdraw_ui_chart_number "${zdraw_ui_chart[low]-}" || return
  _zui_low=$REPLY
  _zdraw_ui_chart_number "${zdraw_ui_chart[high]-}" || return
  _zui_high=$REPLY
  (( _zui_low < _zui_high )) || return 1
  _zui_samples=()
  for (( _zui_index=1; _zui_index<=10#$zdraw_ui_chart[count]; _zui_index++ )); do
    _zui_sample=${zdraw_ui_chart[$_zui_index,value]-}
    if [[ $_zui_sample == '-' ]]; then _zui_samples+=('-')
    else
      _zdraw_ui_chart_number "$_zui_sample" || return
      _zui_samples+=("$REPLY")
    fi
  done
}

# Input values have already been validated. The product fits signed 32-bit math:
# maximum domain span 65534, maximum projection endpoint 32767.
function _zdraw_ui_chart_project {
  emulate -L zsh
  local _zui_sample
  local -i _zui_value
  _zui_points=()
  for _zui_sample in "${_zui_samples[@]}"; do
    if [[ $_zui_sample == '-' ]]; then _zui_points+=('-'); continue; fi
    _zui_value=$_zui_sample
    (( _zui_value < _zui_low )) && _zui_value=$_zui_low
    (( _zui_value > _zui_high )) && _zui_value=$_zui_high
    _zui_points+=("$(( (_zui_value-_zui_low)*$1/(_zui_high-_zui_low) ))")
  done
}

function zdraw-chart-project {
  emulate -L zsh
  [[ $# == 1 && ${(t)reply} == (array|array-local) ]] || return 1
  _zdraw_ui_uint "$1" || return 1
  local -i _zui_low _zui_high
  local -a _zui_samples _zui_points
  _zdraw_ui_chart_read || return
  _zdraw_ui_chart_project "$((10#$1))" || return
  reply=("${_zui_points[@]}")
}

# Resolve a marker profile by querying native cell widths, never terminal replies.
# Explicit Unicode returns 2 when unavailable; auto chooses ASCII instead.
function _zdraw_ui_chart_markers {
  emulate -L zsh
  [[ $_zui_palette == (auto|ascii|unicode) ]] || return 1
  local _zui_glyph
  local -A _zui_info
  local -i _zui_supported=1
  if [[ $_zui_palette != ascii ]]; then
    for _zui_glyph in ▁ ▂ ▃ ▄ ▅ ▆ ▇ █; do
      if ! zdraw textinfo _zui_info "$_zui_glyph" 2>/dev/null || [[ ${_zui_info[width]-} != 1 ]]; then
        _zui_supported=0
        break
      fi
    done
    if (( ! _zui_supported )); then
      [[ $_zui_palette != unicode ]] || return 2
      _zui_palette=ascii
    else _zui_palette=unicode; fi
  fi
  if [[ $_zui_palette == unicode ]]; then
    _zui_default_ramp=▁▂▃▄▅▆▇█ _zui_default_fill=█
  else
    _zui_default_ramp='.:-=+*#@' _zui_default_fill='#'
  fi
}

function _zdraw_ui_chart_glyph {
  emulate -L zsh
  local -A _zui_info
  [[ ${#1} == 1 ]] || return 1
  zdraw textinfo _zui_info "$1" || return
  [[ $_zui_info[width] == 1 ]]
}
