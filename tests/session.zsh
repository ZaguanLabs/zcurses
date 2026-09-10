emulate -R zsh
setopt nounset
module_path=("$1" "${0:A:h:h}/.build/modules")
typeset mode=$2 report_fd=$3 control_fd=$4
zmodload zdraw || exit 1
source "${0:A:h:h}/lib/zdraw-run.zsh"
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
step() { print -r -u "$report_fd" -- "$1"; read -r -u "$control_fd" || fail 'control EOF'; }
typeset -A event info before after
typeset -Ar frozen=(sentinel yes)
typeset -i attempts total chunks worker
typeset data
next_event() {
  for (( attempts=0; attempts<1000; attempts++ )); do
    zdraw event stdscr event poll norefresh && return 0
  done
  fail 'missing event'
}
step baseline
check zdraw init
{
  check zdraw timeout stdscr 0
  check zdraw addwin sample 2 8 1 1
  check zdraw spans sample 0 0 bold RETAINED
  check zdraw prepare label underline DATA
  check zdraw snapshot sample before
  check zdraw spans stdscr 0 0 '' QUEUEDFRAME
  check zdraw stage stdscr
  reject zdraw event stdscr event poll norefresh
  check zdraw inputinfo info
  [[ $info[fd] == 0 && $info[suspended] == 0 && $info[queued] == unknown ]] || fail 'input information'
  if [[ $mode == unavailable ]]; then
    for feature in streaming_paste suspend_resume input_delay; do
      (( ! ${zdraw_features[(Ie)$feature]} )) || fail 'unsupported feature advertised'
    done
    zdraw paste on; (( $? == 2 )) || fail 'paste unavailable status'
    zdraw suspend; (( $? == 2 )) || fail 'suspend unavailable status'
    zdraw inputdelay 20; (( $? == 2 )) || fail 'delay unavailable status'
  else
    reject zdraw paste invalid
    reject zdraw inputdelay -1
    reject zdraw inputdelay 1001
    check zdraw paste on
    check zdraw paste on
    check zdraw init
    step enabled
    check next_event
    [[ $event[type] == paste && $event[phase] == begin ]] || fail 'paste begin'
    reject zdraw input stdscr
    reject zdraw suspend
    reject zdraw paste off
    reject zdraw event stdscr frozen poll norefresh
    check next_event
    [[ $event[phase] == data && $event[text] == $'A\0é\r\3\23' && $event[bytes] == 7 ]] || fail 'paste binary data'
    check zdraw inputinfo info
    [[ $info[paste_active] == 1 && $info[paste_pending] == 4 ]] || fail 'partial delimiter'
    step partial
    check next_event
    [[ $event[text] == $'\e[201xB' ]] || fail 'false delimiter preservation'
    step finish
    check next_event
    [[ $event[phase] == end && $event[text] == '' ]] || fail 'split paste end'
    check next_event
    [[ $event[type] == character && $event[text] == Z ]] || fail 'post-paste queue'
    step large
    check next_event
    [[ $event[phase] == begin ]] || fail 'large paste begin'
    total=0 chunks=0
    while true; do
      check next_event
      (( event[bytes] <= 4096 )) || fail 'unbounded chunk'
      total=$(( total + event[bytes] )) chunks=$(( chunks + 1 ))
      [[ $event[phase] == end ]] && break
    done
    (( total == 5000 && chunks >= 2 )) || fail 'streamed paste length'
    check next_event
    [[ $event[text] == q ]] || fail 'large paste consumed following key'
    step splitbegin
    check next_event
    [[ $event[phase] == begin ]] || fail 'split start delimiter'
    check next_event
    [[ $event[phase] == end && $event[text] == fragment ]] || fail 'fragment payload'
    check zdraw paste off
    check zdraw init
    step pasteoff
    check zdraw paste on
    check zdraw suspend
    check zdraw suspend
    check zdraw inputinfo info
    [[ $info[suspended] == 1 ]] || fail 'suspend state'
    reject zdraw init
    reject zdraw present
    reject zdraw event stdscr event
    reject zdraw-run true
    step suspended
    read -r data
    [[ $data == foreground ]] || fail 'foreground input'
    check zdraw resume
    check zdraw resume
    check zdraw inputinfo info
    [[ $info[suspended] == 0 && $info[paste_enabled] == 1 ]] || fail 'resume state'
    check zdraw snapshot sample after
    [[ ${(kv)before} == ${(kv)after} ]] || fail 'suspend lost retained cells'
    check zdraw draw sample 1 0 label
    check next_event
    [[ $event[type] == resize && $event[rows] == 32 && $event[columns] == 100 ]] || fail 'resume geometry event'
    zdraw-run false
    (( $? == 1 )) || fail 'foreground failure status'
    zdraw-run "${0:A:h:h}/.build/zsh/Src/zsh" -dfc 'kill -INT $$'
    (( $? == 130 )) || fail 'interrupted foreground status'
    check zdraw inputinfo info
    [[ $info[suspended] == 0 ]] || fail 'failed foreground command left suspended'
    check zdraw inputdelay 25
    check zdraw inputinfo info
    [[ $info[escape_delay_ms] == 25 ]] || fail 'escape delay'
    zmodload zsh/zselect || fail zselect
    exec {worker}< <(print -r -- WORKER)
    reject zdraw event stdscr event poll norefresh
    check zselect -t 100 -r 0 "$worker"
    read -r -u "$worker" data
    [[ $data == WORKER ]] || fail 'worker data'
    exec {worker}<&-
    step resumed
    check next_event
    [[ $event[phase] == begin ]] || fail 'cleanup paste begin'
    check zdraw end
    check zdraw init
    check zdraw inputinfo info
    [[ $info[paste_enabled] == 0 && $info[paste_active] == 0 && $info[escape_delay_ms] != 25 ]] || fail 'session cleanup'
    check zdraw suspend
    check zdraw end
    check zdraw init
    check zdraw paste on
    check zmodload -u zdraw
    check zmodload zdraw
    check zdraw init
    check zdraw inputinfo info
    [[ $info[paste_enabled] == 0 && $info[suspended] == 0 ]] || fail 'unload state'
  fi
} always {
  zdraw end
}
check zmodload -u zdraw
check zmodload zdraw
print -r -u "$report_fd" -- done
