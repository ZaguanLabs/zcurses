#!/usr/bin/env zsh
# Real-terminal evidence capture. The driver injects keys only into its own kitty.
emulate -R zsh
setopt nounset
module_path=("${0:A:h:h:h}/.build/modules")
typeset output=$1 name field
typeset -A cap event result
typeset -i tries pressed=0 released=0 text_received=0
zmodload zdraw || exit 1
zdraw init || exit 1
{
  zdraw timeout stdscr 100 || exit 1
  zdraw inputdelay 25 || exit 1
  zdraw query on || exit 1
  for name in focus_events keyboard_events; do
    zdraw query request "$name" 1000 || exit 1
    while true; do
      zdraw event stdscr event norefresh || continue
      [[ $event[type] == capability && $event[name] == $name && $event[phase] == (reply|timeout) ]] && break
    done
  done
  zdraw capabilities cap || exit 1
  if zdraw focus on 2>/dev/null; then result[focus_activation]=yes
  else result[focus_activation]=no; fi
  if zdraw keyboard on 2>/dev/null; then
    result[keyboard_activation]=yes
    print -r -- ready > "$output.ready"
    for (( tries=0; tries<100; tries++ )); do
      zdraw event stdscr event norefresh || continue
      if [[ ${event[source]-} == kitty ]]; then
        [[ ${event[code]-} == 115 && ${event[action]-} == press && ${event[modifiers]-} == 'SHIFT CTRL' ]] && pressed=1
        [[ ${event[code]-} == 115 && ${event[action]-} == release ]] && released=1
        [[ ${event[text]-} == a && ${event[action]-} == press ]] && text_received=1
      fi
      (( pressed && released && text_received )) && break
    done
    result[shortcut_press]=$pressed result[shortcut_release]=$released result[associated_text]=$text_received
  else result[keyboard_activation]=no; fi
  zdraw keyboard off || exit 1
  zdraw focus off || exit 1
  {
    print -r -- "zsh	$ZSH_VERSION"
    for field in term locale curses_version; do print -r -- "$field	$cap[$field]"; done
    for name in focus_events keyboard_events; do
      for field in support source compiled reported query; do print -r -- "$name,$field	$cap[$name,$field]"; done
    done
    for field in ${(ok)result}; do print -r -- "$field	$result[$field]"; done
  } > "$output"
} always {
  zdraw end
}
