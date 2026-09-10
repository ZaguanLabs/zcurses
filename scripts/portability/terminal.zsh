#!/usr/bin/env zsh
# Noninteractive evidence capture, launched by terminal-matrix.py in a real emulator.
emulate -R zsh
setopt nounset
module_path=("${0:A:h:h:h}/.build/modules")
typeset output=$1 name field
zmodload zdraw || exit 1
typeset -A cap event
zdraw init || exit 1
{
  zdraw timeout stdscr -1 || exit 1
  zdraw query on || exit 1
  for name in streaming_paste focus_events synchronized_output; do
    zdraw query request "$name" 1500 || exit 1
    while true; do
      zdraw event stdscr event norefresh || exit 1
      [[ $event[type] == capability && $event[name] == $name && $event[phase] == (reply|timeout) ]] && break
    done
  done
  zdraw capabilities cap || exit 1
  {
    print -r -- "zsh	$ZSH_VERSION"
    for field in term locale curses_version; do print -r -- "$field	$cap[$field]"; done
    for name in streaming_paste focus_events synchronized_output; do
      for field in support source compiled enabled reported query; do
        print -r -- "$name,$field	$cap[$name,$field]"
      done
    done
  } > "$output"
} always {
  zdraw end
}
