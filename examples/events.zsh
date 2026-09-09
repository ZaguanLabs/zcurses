#!/usr/bin/env zsh
# Run with the matching .build/zsh/Src/zsh; optionally pass --mouse.
emulate -R zsh
setopt errexit nounset
module_path=("${0:A:h:h}/.build/modules")
typeset -a input_options dimensions
if (( $# )); then
  [[ $# == 1 && $1 == --mouse ]] || { print -ru2 -- 'Usage: events.zsh [--mouse]'; exit 1; }
  input_options=(mouse)
fi
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
  event=(type ready key '' text '' code '' encoding '' modifiers unknown)
  while true; do
    zdraw position stdscr dimensions
    if (( dimensions[5] >= 10 && dimensions[6] >= 20 )); then
      zdraw clear stdscr
      zdraw draw stdscr 0 0 heading "$dimensions[6]"
      row=2
      for field in type key text code encoding modifiers buttons; do
        value=${event[$field]-}
        zdraw spansclip stdscr "$row" 0 "$dimensions[6]" bold "$field: " '' "${(qqqq)value}"
        (( ++row ))
      done
      zdraw refresh
    fi
    # ERR includes timeout/interruption; leave the previous record displayed.
    if zdraw event stdscr event "${input_options[@]}"; then
      [[ $event[type] == character && $event[text] == q ]] && break
      if [[ $event[type] == resize ]] && (( ${zdraw_features[(Ie)resize]} )); then
        zdraw resize "$event[rows]" "$event[columns]" nosave
      fi
    fi
  done
} always {
  zdraw end
}
