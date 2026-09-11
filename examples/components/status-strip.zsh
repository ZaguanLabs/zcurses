# SPDX-License-Identifier: LicenseRef-Zsh
# Passive experimental composition over the existing meter and style helpers.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${1:A:h:h:h}/lib/zdraw-meter.zsh"
} "${(%):-%x}" || return

function zdraw-status-strip {
  emulate -L zsh
  [[ $# -ge 8 && ${(t)zdraw_ui_theme} == association* ]] || {
    _zdraw_ui_error 1 "${(%):-%N}" 'requires window rectangle, working|waiting|done|failed, title, detail and theme'; return $?
  }
  local _ss_win=$1 _ss_phase=$6 _ss_title=$7 _ss_detail=$8 _ss_value='' _ss_total=''
  local _ss_state _ss_word _ss_marker _ss_part _ss_text
  local -i _zui_y _zui_x _zui_h _zui_w _ss_known=0 _ss_meter=0 _ss_text_width _ss_progress_y _ss_indent
  local -A zdraw_ui_style _ss_styles _ss_info
  local -a _ss_opts _ss_defaults=(fg=text bg=canvas title:bold label:fg=muted
    key:fg=accent invalid+key:fg=error inactive+key:fg=muted key:bold
    filled:fg=accent track:fg=border invalid+filled:fg=error inactive+filled:fg=muted)
  _zdraw_ui_rect "${@:1:5}" || return
  (( (_zui_h==1 || _zui_h==2) && _zui_w>=24 )) || {
    _zdraw_ui_error 2 "${(%):-%N}" 'requires one or two rows and at least 24 columns'; return $?
  }
  case $_ss_phase in
    working) _ss_state=focus _ss_word=Working _ss_marker='*' ;;
    waiting) _ss_state=inactive _ss_word=Waiting _ss_marker='?' ;;
    done) _ss_state=positive _ss_word=Done _ss_marker='+' ;;
    failed) _ss_state=invalid _ss_word=Failed _ss_marker='!' ;;
    *) return 1 ;;
  esac
  shift 8
  while (( $# )); do
    case $1 in
      value=*) _ss_value=${1#*=}; _ss_known=1 ;;
      total=*) _ss_total=${1#*=}; _ss_known=1 ;;
      *) _ss_opts+=("$1") ;;
    esac
    shift
  done
  (( ${#_ss_opts}<=64 )) || return 1
  if (( _ss_known )); then
    _zdraw_ui_uint "$_ss_value" && _zdraw_ui_uint "$_ss_total" &&
      (( 10#$_ss_total>0 && 10#$_ss_value<=10#$_ss_total )) || return 1
    _ss_value=$((10#$_ss_value)) _ss_total=$((10#$_ss_total)) _ss_known=1
  fi
  # Validate even hidden detail and styles before any cell is changed.
  for _ss_text in "$_ss_title" "$_ss_detail"; do
    (( ${#_ss_text}<=32767 )) || return 1
    zdraw textinfo _ss_info "$_ss_text" || return
  done
  for _ss_part in normal title label key filled track; do
    zdraw-ui-style "$_ss_state,$_ss_part" "${_ss_defaults[@]}" "${_ss_opts[@]}" || return
    [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[px] == 0 &&
       $zdraw_ui_style[py] == 0 && $zdraw_ui_style[align] == left ]] || return 1
    _ss_styles[$_ss_part]=$zdraw_ui_style[style]
  done
  (( _ss_known && _zui_h==2 && _zui_w>=60 )) && _ss_meter=1
  zdraw fill "$_ss_win" "$_zui_y" "$_zui_x" "$_zui_h" "$_zui_w" "$_ss_styles[normal]" ' ' || return
  zdraw spansclip "$_ss_win" "$_zui_y" "$_zui_x" 9 "$_ss_styles[key]" "$_ss_marker $_ss_word" || return
  _ss_text_width=$((_zui_w-10))
  (( _ss_known && _zui_h==1 )) && (( _ss_text_width-=6 ))
  zdraw spansclip "$_ss_win" "$_zui_y" "$((_zui_x+10))" "$_ss_text_width" "$_ss_styles[title]" "$_ss_title" || return
  if (( _zui_h==2 )); then
    _ss_indent=$((_zui_w<48 ? 0 : 10))
    _ss_text_width=$((_zui_w-_ss_indent))
    (( _ss_known )) && (( _ss_text_width-=_ss_meter ? 20 : 6 ))
    zdraw spansclip "$_ss_win" "$((_zui_y+1))" "$((_zui_x+_ss_indent))" "$_ss_text_width" "$_ss_styles[label]" "$_ss_detail" || return
  fi
  if (( _ss_known )); then
    _ss_progress_y=$((_zui_y+_zui_h-1))
    if (( _ss_meter )); then
      zdraw-meter "$_ss_win" "$_ss_progress_y" "$((_zui_x+_zui_w-18))" 18 "$_ss_value" "$_ss_total" "$_ss_state" \
        fill-char='=' empty-char='-' "${_ss_defaults[@]}" "${_ss_opts[@]}" || return
    else
      printf -v _ss_text '%4s' "$((100*_ss_value/_ss_total))%"
      zdraw spans "$_ss_win" "$_ss_progress_y" "$((_zui_x+_zui_w-4))" "$_ss_styles[key]" "$_ss_text" || return
    fi
  fi
  return 0
}
