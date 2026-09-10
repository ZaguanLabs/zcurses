emulate -R zsh
setopt nounset
module_path=("${0:A:h:h}/.build/modules")
typeset report_fd=$1 control_fd=$2
typeset -A info
typeset -i continued=0 stopped=0 signalled=0
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
TRAPUSR1() { (( signalled++ )); return 0; }
TRAPCONT() { (( continued++ )); return 0; }
TRAPTSTP() {
  (( stopped++ ))
  zdraw suspend || fail suspend
  print -r -u "$report_fd" -- suspended
  kill -STOP $$
  return 0
}
check zmodload zdraw
check zdraw init
{
  check zdraw paste on
  check zdraw focus on force
  check zdraw query on
  check zdraw query request focus_events 5000
  print -r -u "$report_fd" -- "ready $$"
  # Wait through a trap-driven stop. A separate pipe remains usable in bg.
  while (( ! continued )); do read -r -u "$control_fd"; done
  zdraw resume && fail 'background resume succeeded'
  check zdraw capabilities info
  [[ $info[session] == suspended && $info[focus_events,query] == cancelled ]] || fail 'background state'
  print -r -u "$report_fd" -- background
  kill -STOP $$
  check zdraw resume
  kill -USR1 $$
  (( stopped == 1 && continued >= 2 && signalled == 1 )) || fail 'application traps'
  check zdraw capabilities info
  [[ $info[session] == active && $info[streaming_paste,enabled] == yes && $info[focus_events,enabled] == yes ]] || fail 'foreground resume'
  print -r -u "$report_fd" -- foreground
} always {
  zdraw end
}
print -r -u "$report_fd" -- done
