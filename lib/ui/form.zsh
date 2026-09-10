function zdraw-form-init {
  emulate -L zsh
  [[ ${(t)zdraw_ui_form} == (association|association-local) ]] || return 1
  (( $# > 0 && $# <= 48 && $# % 3 == 0 )) || return 1
  local -A _zui_form=(count "$(( $# / 3 ))" focus 1) zdraw_ui_input _zui_info
  local zdraw_ui_error _zui_key
  local -a _zui_rules
  local -i _zui_i=0 _zui_result
  while (( $# )); do
    (( _zui_i++ ))
    (( ${#1} <= 128 )) || return 1
    zdraw textinfo _zui_info "$1" || return
    zdraw-input-init "$2" || return
    _zui_rules=()
    [[ -n $3 ]] && _zui_rules=("${(@s:,:)3}")
    zdraw-input-check "${_zui_rules[@]}"
    _zui_result=$?
    (( _zui_result < 2 )) || return 1
    _zui_form[$_zui_i,label]=$1 _zui_form[$_zui_i,rules]=$3 _zui_form[$_zui_i,error]=''
    for _zui_key in "${(@k)zdraw_ui_input}"; do
      _zui_form[$_zui_i,$_zui_key]=$zdraw_ui_input[$_zui_key]
    done
    shift 3
  done
  zdraw_ui_form=("${(@kv)_zui_form}")
}

function _zdraw_ui_form_state {
  emulate -L zsh
  [[ ${(t)zdraw_ui_form} == association* ]] || return 1
  _zdraw_ui_uint "${zdraw_ui_form[count]-}" && _zdraw_ui_uint "${zdraw_ui_form[focus]-}" || return 1
  (( 10#$zdraw_ui_form[count] >= 1 && 10#$zdraw_ui_form[count] <= 16 &&
     10#$zdraw_ui_form[focus] >= 1 && 10#$zdraw_ui_form[focus] <= 10#$zdraw_ui_form[count] ))
}

# Caller owns the scratch zdraw_ui_input association. Field indexes are internal.
function _zdraw_ui_form_load {
  emulate -L zsh
  local _zui_key
  zdraw_ui_input=()
  for _zui_key in text cursor anchor limit paste_active paste_failed paste_buffer; do
    zdraw_ui_input[$_zui_key]=${zdraw_ui_form[$1,$_zui_key]-}
  done
}

function zdraw-form-action {
  emulate -L zsh
  [[ $# -ge 1 && ${(t)zdraw_ui_form} == (association|association-local) ]] || return 2
  _zdraw_ui_form_state || return 2
  local -A zdraw_ui_input _zui_work=("${(@kv)zdraw_ui_form}")
  local zdraw_ui_error _zui_key
  local -a _zui_rules
  local -i _zui_focus=$((10#$zdraw_ui_form[focus])) _zui_i _zui_result _zui_invalid=0
  _zdraw_ui_form_load "$_zui_focus"
  case $1 in
    edit|paste)
      local _zui_operation=$1
      shift
      "zdraw-input-$_zui_operation" "$@"
      _zui_result=$?
      # Failed paste data/end still needs its drain/cleanup state persisted.
      for _zui_key in "${(@k)zdraw_ui_input}"; do
        zdraw_ui_form[$_zui_focus,$_zui_key]=$zdraw_ui_input[$_zui_key]
      done
      (( _zui_result == 0 )) && zdraw_ui_form[$_zui_focus,error]=''
      return "$_zui_result" ;;
    next|previous|validate)
      (( $# == 1 )) || return 2
      # A form cannot transfer an unfinished paste to another field.
      [[ $zdraw_ui_input[paste_active] == 0 ]] || return 2
      for (( _zui_i=1; _zui_i<=10#$zdraw_ui_form[count]; _zui_i++ )); do
        [[ $1 == validate || $_zui_i == $_zui_focus ]] || continue
        _zdraw_ui_form_load "$_zui_i"
        [[ $zdraw_ui_input[paste_active] == 0 ]] || return 2
        _zui_rules=()
        [[ -n ${zdraw_ui_form[$_zui_i,rules]-} ]] && _zui_rules=("${(@s:,:)zdraw_ui_form[$_zui_i,rules]}")
        zdraw-input-check "${_zui_rules[@]}"
        _zui_result=$?
        (( _zui_result < 2 )) || return 2
        _zui_work[$_zui_i,error]=$zdraw_ui_error
        (( _zui_result == 1 && _zui_invalid == 0 )) && _zui_invalid=$_zui_i
      done
      case $1 in
        next) _zui_work[focus]=$((_zui_focus % 10#$zdraw_ui_form[count] + 1)) ;;
        previous) _zui_work[focus]=$((_zui_focus > 1 ? _zui_focus-1 : 10#$zdraw_ui_form[count])) ;;
        validate) (( _zui_invalid )) && _zui_work[focus]=$_zui_invalid ;;
      esac
      zdraw_ui_form=("${(@kv)_zui_work}")
      [[ $1 != validate || $_zui_invalid == 0 ]] ;;
    *) return 2 ;;
  esac
}

# Three rows per field: label, editable value, validation message.
function zdraw-form {
  emulate -L zsh
  (( $# >= 6 )) || return 1
  _zdraw_ui_form_state || return
  [[ $6 == (focus|inactive|disabled) ]] || return 1
  local _zui_win=$1 _zui_state=$6 _zui_field_state _zui_variant
  local -i _zui_y _zui_x _zui_h _zui_w _zui_i _zui_row _zui_first _zui_visible
  local -A zdraw_ui_input zdraw_ui_style _zui_cursor _zui_anchor _zui_info
  _zdraw_ui_rect "$1" "$2" "$3" "$4" "$5" || return
  (( _zui_h >= 3 )) || return 2
  _zui_visible=$((_zui_h / 3))
  _zui_first=$((10#$zdraw_ui_form[focus] > _zui_visible ? 10#$zdraw_ui_form[focus]-_zui_visible+1 : 1))
  # Preflight all fields and styles, including off-screen labels/errors.
  for (( _zui_i=1; _zui_i<=10#$zdraw_ui_form[count]; _zui_i++ )); do
    _zdraw_ui_form_load "$_zui_i"
    _zdraw_ui_input_state || return
    zdraw textinfo _zui_info "${zdraw_ui_form[$_zui_i,label]-}" || return
    zdraw textinfo _zui_info "${zdraw_ui_form[$_zui_i,error]-}" || return
  done
  for _zui_field_state in focus inactive disabled focus,invalid inactive,invalid disabled,invalid; do
    for _zui_variant in "$_zui_field_state" "$_zui_field_state,selected" "$_zui_field_state,cursor"; do
      zdraw-ui-style "$_zui_variant" fg=text bg=surface "${@:7}" || return
      [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[px] == 0 && $zdraw_ui_style[py] == 0 && $zdraw_ui_style[align] == left ]] || return 1
    done
  done
  zdraw-ui-style "$_zui_state" fg=text bg=surface "${@:7}" || return
  zdraw fill "$_zui_win" "$_zui_y" "$_zui_x" "$_zui_h" "$_zui_w" "$zdraw_ui_style[style]" ' ' || return
  for (( _zui_i=_zui_first; _zui_i<=10#$zdraw_ui_form[count] && _zui_i<_zui_first+_zui_visible; _zui_i++ )); do
    _zui_row=$((_zui_y + 3*(_zui_i-_zui_first)))
    _zui_field_state=inactive
    (( _zui_i == 10#$zdraw_ui_form[focus] )) && _zui_field_state=$_zui_state
    [[ $_zui_state == disabled ]] && _zui_field_state=disabled
    zdraw-label "$_zui_win" "$_zui_row" "$_zui_x" "$_zui_w" "${zdraw_ui_form[$_zui_i,label]-}" "$_zui_field_state" fg=muted focus:fg=accent bold "${@:7}" || return
    [[ -n ${zdraw_ui_form[$_zui_i,error]-} ]] && _zui_field_state+=,invalid
    _zdraw_ui_form_load "$_zui_i"
    zdraw-input "$_zui_win" "$((_zui_row+1))" "$_zui_x" "$_zui_w" "$_zui_field_state" invalid:fg=error "${@:7}" || return
    zdraw-label "$_zui_win" "$((_zui_row+2))" "$_zui_x" "$_zui_w" "${zdraw_ui_form[$_zui_i,error]-}" normal fg=error "${@:7}" || return
  done
  return 0
}
