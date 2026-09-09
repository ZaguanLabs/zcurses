#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset report_fd=$2 control_fd=$3
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
step() { print -r -u "$report_fd" -- "$1"; read -r -u "$control_fd" || fail 'control EOF'; }
typeset -A event
step baseline
check zdraw init
{
  check zdraw string stdscr BASELINE
  check zdraw refresh stdscr
  check zdraw addwin floating 3 18 1 1
  check zdraw spans floating 0 0 bold WINDOWSECRET
  check zdraw stage floating
  check zdraw movewin floating 4 6
  check zdraw resizewin floating 4 22 8 10
  check zdraw timeout stdscr 0
  zdraw event stdscr event norefresh
  (( $? == 1 )) || fail 'empty no-refresh poll'
  step hidden
  check zdraw stage stdscr floating
  check zdraw present
  step presented
  check zdraw resizewin floating 6 26 2 3
  check zdraw spans floating 4 0 '' LARGERWINDOW
  check zdraw movewin floating 12 20
  step changed
  check zdraw stage stdscr floating
  check zdraw present
  step changedpresented
  check zdraw delwin floating
} always {
  zdraw end
}
print -r -u "$report_fd" -- done
