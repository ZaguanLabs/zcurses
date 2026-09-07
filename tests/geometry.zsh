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
  report "ready $position[5] $position[6]"
  barrier

  check zcurses geometry dimensions
  check zcurses position stdscr position
  report "resized ${(j: :)dimensions} cached $position[5] $position[6]"
  barrier

  dimensions=(sentinel)
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
report "after ${(j: :)dimensions}"
