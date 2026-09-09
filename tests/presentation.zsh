#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset report_fd=$2 control_fd=$3
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
step() { print -r -u "$report_fd" -- "$1"; read -r -u "$control_fd" || fail 'control EOF'; }
typeset -A event=(sentinel yes)
typeset -a before after
step baseline
check zdraw init
{
  (( ${zdraw_features[(Ie)norefresh_events]} )) || fail 'feature missing'
  check zdraw addwin child 2 30 5 0
  check zdraw string stdscr BEFORE
  check zdraw refresh stdscr child
  step ready
  check zdraw prepare hidden bold SECRETFRAME
  check zdraw draw stdscr 1 0 hidden
  check zdraw string child HIDDENCHILD
  check zdraw move stdscr 2 3
  check zdraw position stdscr before
  check zdraw timeout stdscr 150
  zdraw event stdscr event norefresh
  (( $? == 1 )) || fail 'finite empty read'
  check zdraw timeout child 0
  zdraw event child event norefresh
  (( $? == 1 )) || fail 'child empty poll'
  [[ $event[sentinel] == yes && ${#zdraw_windows} == 2 ]] || fail 'poll mutated state'
  check zdraw position stdscr after
  [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'poll moved cursor'
  step hidden
  check zdraw event child event norefresh
  [[ $event[text] == X ]] || fail 'character read'
  check zdraw event stdscr event norefresh
  [[ $event[key] == UP ]] || fail 'shared queued key'
  step stillhidden
  check zdraw refresh stdscr child
  step presented
  check zdraw move stdscr 3 0
  check zdraw string stdscr LEGACYVISIBLE
  check zdraw timeout stdscr 0
  zdraw input stdscr
  (( $? == 1 )) || fail 'legacy empty poll'
  step legacyvisible
  check zdraw delwin child
  check zdraw end
  check zdraw init
  check zdraw timeout stdscr 0
  zdraw event stdscr event norefresh
  (( $? == 1 )) || fail 'new session empty poll'
  check zmodload -u zdraw
  check zmodload zdraw
  check zdraw init
  check zdraw timeout stdscr 0
  zdraw event stdscr event norefresh
  (( $? == 1 )) || fail 'module reload empty poll'
} always {
  zdraw end
}
print -r -u "$report_fd" -- done
