#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset report_fd=$2 control_fd=$3
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
step() { print -r -u "$report_fd" -- "$1"; read -r -u "$control_fd" || fail 'control EOF'; }
typeset -A event=(sentinel yes)
step baseline
check zdraw init
{
  check zdraw string stdscr BASELINE
  check zdraw refresh stdscr
  check zdraw addpad canvas 40 100
  check zdraw spans canvas 30 50 bold PADSECRET
  check zdraw spans stdscr 2 0 '' FRAMEHEADER
  check zdraw stage stdscr
  check zdraw viewport canvas 30 50 4 0 1 12
  step staged
  # The parent queued X before releasing this barrier. Rejected pad input
  # must neither consume it nor reveal the staged frame.
  reject zdraw input canvas
  reject zdraw event canvas event norefresh
  [[ $event[sentinel] == yes ]] || fail 'invalid input changed result'
  check zdraw timeout stdscr 100
  check zdraw event stdscr event norefresh
  [[ $event[type] == character && $event[text] == X ]] || fail 'pad input consumed shared queue'
  step input
  check zdraw present
  step presented
  check zdraw spans canvas 31 50 '' SCROLLEDVIEW
  check zdraw viewport canvas 31 50 6 0 1 12
  step moved
  check zdraw present
  step movedpresented
  if (( ${zdraw_features[(Ie)pad_resize]} )); then
    check zdraw spans canvas 39 50 '' QUEUEDOLD
    check zdraw viewport canvas 39 50 8 0 1 12
    # Shrink away the source of queued cells before presenting that frame.
    check zdraw resizepad canvas 2 16
    check zdraw spans canvas 1 0 '' NEWRESIZED
    step resized
    check zdraw present
    step resizedqueuedold
    check zdraw viewport canvas 1 0 10 0 1 12
    step restaged
    check zdraw present
    step resizedpresented
  fi
  check zdraw delwin canvas
  check zdraw end
} always {
  zdraw end
}
print -r -u "$report_fd" -- done
