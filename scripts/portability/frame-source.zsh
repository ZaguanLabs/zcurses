#!/usr/bin/env zsh
# Native frame producer for the private PTY/terminal rendering probe.
emulate -R zsh
setopt nounset
module_path=("${0:A:h:h:h}/.build/modules")
typeset frame_mode=$1 report_fd=$2 control_fd=$3 evidence_file=$4
step() { print -r -u "$report_fd" -- "$1"; read -r -u "$control_fd"; }
typeset -A cap event
typeset -a dimensions
zmodload zdraw || exit 1
zdraw init || exit 1
{
  zdraw position stdscr dimensions || exit 1
  zdraw timeout stdscr 100 || exit 1
  zdraw fill stdscr 0 0 "$((dimensions[5]-1))" "$dimensions[6]" 'white/blue' A || exit 1
  zdraw stage stdscr && zdraw present || exit 1
  print -rn -- $'\e[?25l'
  zdraw query on || exit 1
  zdraw query request synchronized_output 1000 || exit 1
  while true; do
    zdraw event stdscr event norefresh || continue
    [[ $event[type] == capability && $event[name] == synchronized_output && $event[phase] == (reply|timeout) ]] && break
  done
  zdraw capabilities cap || exit 1
  {
    print -r -- "zsh	$ZSH_VERSION"
    for field in term locale curses_version; do print -r -- "$field	$cap[$field]"; done
    for field in support reported query; do print -r -- "$field	$cap[synchronized_output,$field]"; done
  } > "$evidence_file"
  if [[ $frame_mode == sync ]] && ! zdraw sync on 2>/dev/null; then
    step unsupported
  else
    zdraw fill stdscr 0 0 "$((dimensions[5]-1))" "$dimensions[6]" 'black/yellow' B || exit 1
    zdraw stage stdscr || exit 1
    step staged || exit 1
    zdraw present || exit 1
    step framed || exit 1
  fi
} always {
  zdraw end
}
print -r -u "$report_fd" -- done
