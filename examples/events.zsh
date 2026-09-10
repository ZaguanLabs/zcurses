#!/usr/bin/env zsh
# Run with the matching .build/zsh/Src/zsh; optionally pass --mouse.
emulate -R zsh
setopt errexit nounset
module_path=("${0:A:h:h}/.build/modules")
typeset -a input_options dimensions example_protocol_queue
typeset example_protocol_current='' protocol_note='Legacy input.' option
typeset -i example_keyboard_active=0
for option in "$@"; do
  case $option in
    --mouse) input_options+=(mouse) ;;
    --focus) example_protocol_queue+=(focus_events) ;;
    --keyboard) example_protocol_queue+=(keyboard_events) ;;
    *) print -ru2 -- 'Usage: events.zsh [--mouse] [--focus] [--keyboard]'; exit 1 ;;
  esac
done
input_options=("${(@u)input_options}")
example_protocol_queue=("${(@u)example_protocol_queue}")
source "${0:A:h}/input-protocols.zsh"
zmodload zdraw
(( ${zdraw_features[(Ie)structured_events]} && ${zdraw_features[(Ie)prepared_rows]} ))
if (( ${zdraw_features[(Ie)norefresh_events]} )); then
  input_options+=(norefresh)
fi
typeset -A event
typeset field value
typeset -i row
zdraw init
{
  zdraw prepare heading bold 'zdraw events - q to quit'
  zdraw timeout stdscr 100
  example-protocol-next
  event=(type ready key '' text '' code '' encoding '' modifiers unknown)
  while true; do
    zdraw position stdscr dimensions
    if (( dimensions[5] >= 18 && dimensions[6] >= 20 )); then
      zdraw clear stdscr
      zdraw draw stdscr 0 0 heading "$dimensions[6]"
      row=2
      for field in type source key action text code encoding modifiers focused supported reason buttons; do
        value=${event[$field]-}
        zdraw spansclip stdscr "$row" 0 "$dimensions[6]" bold "$field: " '' "${(qqqq)value}"
        (( ++row ))
      done
      zdraw spansclip stdscr 16 0 "$dimensions[6]" dim "$protocol_note"
      zdraw refresh
    fi
    # ERR includes timeout/interruption; leave the previous record displayed.
    if zdraw event stdscr event "${input_options[@]}"; then
      if example-protocol-event; then continue; fi
      [[ $event[type] == character && $event[text] == q ]] && break
      [[ ${event[source]-} == kitty && ${event[action]-} != release &&
         ( ${event[text]-} == q || ${event[key]-} == ESC ) ]] && break
      if [[ $event[type] == resize ]] && (( ${zdraw_features[(Ie)resize]} )); then
        zdraw resize "$event[rows]" "$event[columns]" nosave
      fi
    fi
  done
} always {
  zdraw end
}
