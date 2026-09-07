#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset control_fd=$2 report_fd=$3 command=''
zmodload zsh/curses || exit 1

report() { print -r -u "$report_fd" -- "$*"; }
barrier() { read -r -u "$control_fd" command || exit 1; }
check() { "$@" || { report "FAIL $*"; exit 1; }; }

typeset -a dimensions=(sentinel) position cells
typeset -a compiled_features=("${zcurses_features[@]}")
check_features() {
  [[ "${(j: :)zcurses_features}" == "${(j: :)compiled_features}" ]] || exit 1
}
check zmodload -F -e zsh/curses +p:zcurses_features
check_features
check zcurses geometry dimensions
report "before ${(j: :)dimensions}"
barrier

check zcurses init
{
  check zcurses addwin sample 4 20 1 1
  check zcurses attr sample bold green/black
  check zcurses string sample hello
  check zcurses move sample 0 0
  check zcurses querychar sample cells
  [[ $cells[1] == h && $cells[2] == green/black && $cells[3] == bold ]] || exit 1
  check zcurses refresh sample stdscr
  check zcurses position stdscr position
  # Discovery is stable after initialization and agrees with the legacy probes.
  check_features
  zcurses mouse
  [[ $? -eq $(( ! ${zcurses_features[(Ie)mouse]} )) ]] || exit 1
  zcurses resize 0 0
  [[ $? -eq $(( ${zcurses_features[(Ie)resize]} ? 0 : 2 )) ]] || exit 1
  report "ready $position[5] $position[6]"
  barrier

  # Leave a drawing change pending: discovery must not present it.
  check zcurses string sample pending
  check_features
  check zcurses geometry dimensions
  check zcurses position stdscr position
  report "resized ${(j: :)dimensions} cached $position[5] $position[6]"
  barrier

  dimensions=(sentinel)
  check_features
  zcurses geometry dimensions
  report "zero $? ${(j: :)dimensions}"
  barrier

  # Standard parameter assignment must find a caller's local array.
  caller() {
    local -a local_size
    check zcurses geometry local_size
    report "local ${(j: :)local_size}"
  }
  caller
  ( typeset -ra frozen=(keep); zcurses geometry frozen ) 2>/dev/null
  report "readonly $?"
  zcurses geometry 2>/dev/null
  report "missing $?"
  zcurses geometry dimensions extra 2>/dev/null
  report "extra $?"
  check zcurses delwin sample
} always {
  zcurses end
}
check zcurses geometry dimensions
check_features
report "after ${(j: :)dimensions}"
