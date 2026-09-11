# SPDX-License-Identifier: LicenseRef-Zsh
# Zsh licence: ../../LICENCE
# Pure state transition: the application translates its own keymap to actions.
function zdraw-list-update {
  emulate -L zsh
  [[ $# == 3 && ${(t)zdraw_ui_list} == (association|association-local) ]] || { _zdraw_ui_error 1 "${(%):-%N}" "requires count visible action and a writable zdraw_ui_list association"; return $?; }
  _zdraw_ui_uint "$1" && _zdraw_ui_uint "$2" || { _zdraw_ui_error 1 "${(%):-%N}" "count and visible must be integers from 0 to 32767"; return $?; }
  local _zui_action=$3
  [[ $_zui_action == (keep|up|down|home|end|page-up|page-down) ]] || { _zdraw_ui_error 1 "${(%):-%N}" "unknown selection action ${(qqq)_zui_action}"; return $?; }
  local _zui_selected=${zdraw_ui_list[selected]:-1} _zui_first=${zdraw_ui_list[first]:-1}
  _zdraw_ui_uint "$_zui_selected" && _zdraw_ui_uint "$_zui_first" || { _zdraw_ui_error 1 "${(%):-%N}" "selected and first must be integers from 0 to 32767"; return $?; }
  local -i _zui_count=$((10#$1)) _zui_visible=$((10#$2))
  local -i _zui_s=$((10#$_zui_selected)) _zui_f=$((10#$_zui_first)) _zui_step
  if (( _zui_count )); then
    (( _zui_s < 1 )) && _zui_s=1
    (( _zui_s > _zui_count )) && _zui_s=$_zui_count
    _zui_step=$(( _zui_visible > 0 ? _zui_visible : 1 ))
    case $_zui_action in
      up) (( _zui_s-- )) ;; down) (( _zui_s++ )) ;;
      home) _zui_s=1 ;; end) _zui_s=$_zui_count ;;
      page-up) (( _zui_s -= _zui_step )) ;; page-down) (( _zui_s += _zui_step )) ;;
    esac
    (( _zui_s < 1 )) && _zui_s=1
    (( _zui_s > _zui_count )) && _zui_s=$_zui_count
    (( _zui_f < 1 )) && _zui_f=1
    (( _zui_f > _zui_s )) && _zui_f=$_zui_s
    if (( _zui_visible )); then
      (( _zui_s >= _zui_f + _zui_visible )) && _zui_f=$(( _zui_s - _zui_visible + 1 ))
      _zui_step=$(( _zui_count > _zui_visible ? _zui_count - _zui_visible + 1 : 1 ))
      (( _zui_f > _zui_step )) && _zui_f=$_zui_step
    fi
  else
    _zui_s=0 _zui_f=1
  fi
  zdraw_ui_list[selected]=$_zui_s zdraw_ui_list[first]=$_zui_f
}
