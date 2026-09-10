emulate -R zsh
setopt nounset
module_path=("$1")
zmodload zdraw || exit 1
typeset mode=$2 report_fd=$3 control_fd=$4
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
step() { print -r -u "$report_fd" -- "$1"; read -r -u "$control_fd" || fail EOF; }
typeset -A cap event
typeset -Ar frozen=(sentinel yes)
typeset -i attempts
next_event() {
  for (( attempts=0; attempts<2000; attempts++ )); do
    zdraw event stdscr event poll norefresh && return 0
  done
  fail 'missing event'
}
step baseline
check zdraw init
{
  check zdraw timeout stdscr 500
  check zdraw capabilities cap
  [[ $cap[session] == active && $cap[colors,source] == curses && $cap[streaming_paste,support] == unknown ]] || fail 'initial evidence'
  check zdraw spans stdscr 0 0 '' UNPRESENTED
  check zdraw stage stdscr
  reject zdraw capabilities frozen
  reject zdraw capabilities cap streaming_paste=yes streaming_paste=no
  reject zdraw query request streaming_paste 100
  if [[ $mode == unavailable ]]; then
    zdraw query on; (( $? == 2 )) || fail 'unavailable status'
    (( ! ${zdraw_features[(Ie)capability_queries]} )) || fail 'feature advertised'
  elif [[ $mode == registration_failure ]]; then
    reject zdraw query on
    check zdraw capabilities cap
    [[ $cap[query_owner] == no ]] || fail 'failed reservation ownership'
    step rollback
    typeset collected=''
    typeset -i index
    for (( index=0; index<11; index++ )); do
      check next_event
      [[ $event[type] == character ]] || fail 'failed reservation leaked key'
      collected+=$event[text]
    done
    [[ $collected == $'\e[?2004;0$y' ]] || fail 'reservation rollback lost input'
  elif [[ $mode == reports ]]; then
    typeset -i report
    typeset collected
    for report in 0 1 2 3 4; do
      check zdraw query on
      check zdraw query request synchronized_output 1000
      step "report-$report"
      reject zdraw event stdscr frozen poll norefresh
      check next_event
      [[ $event[type] == capability && $event[phase] == reply && $event[report] == $report ]] || fail 'report value'
      check zdraw capabilities cap
      if (( report == 0 )); then
        [[ $cap[synchronized_output,support] == no ]] || fail 'unrecognized mode'
      else
        [[ $cap[synchronized_output,support] == yes ]] || fail 'recognized mode'
      fi
      [[ $cap[synchronized_output,enabled] == no ]] || fail 'report enabled mode'
      check zdraw end
      check zdraw init
    done
    check zdraw query on
    step malformed
    collected=''
    for (( report=0; report<13; report++ )); do
      check next_event
      [[ $event[type] == character ]] || fail 'invalid report consumed'
      collected+=$event[text]
    done
    [[ $collected == $'\e[?2026;9$yXY' ]] || fail 'invalid sequence preservation'
    check zdraw query request focus_events 1000
    check zdraw inputdelay 20
    step slow-prefix
    collected=''
    for (( report=0; report<11; report++ )); do
      check zdraw event stdscr event norefresh
      [[ $event[type] == character ]] || fail 'slow fragment misclassified'
      collected+=$event[text]
    done
    [[ $collected == $'\e[?1004;2$y' ]] || fail 'slow fragment lost'
    check zdraw capabilities cap
    [[ $cap[focus_events,support] == unknown ]] || fail 'slow sequence evidence'
    check zdraw query cancel
  else
    check zdraw query on
    check zdraw query on
    reject zdraw input stdscr
    reject zdraw query request streaming_paste 0
    reject zdraw query request streaming_paste 5001
    reject zdraw query request streaming_paste '1+1'
    reject zdraw query request arbitrary 100
    step unsolicited
    check next_event
    [[ $event[type] == capability && $event[phase] == unsolicited && $event[name] == streaming_paste ]] || fail unsolicited
    check zdraw capabilities cap
    [[ $cap[streaming_paste,support] == unknown ]] || fail 'unsolicited evidence'
    check zdraw query request streaming_paste 1500
    reject zdraw query request focus_events 100
    step fragmented
    check zdraw event stdscr event norefresh
    [[ $event[type] == character && $event[text] == A ]] || fail 'preceding key'
    check zdraw event stdscr event norefresh
    [[ $event[type] == capability && $event[phase] == reply && $event[report] == 2 ]] || fail 'fragmented reply'
    check zdraw capabilities cap
    [[ $cap[streaming_paste,support] == yes && $cap[streaming_paste,source] == reply && $cap[streaming_paste,enabled] == no && $cap[streaming_paste,reported] == reset ]] || fail 'reply record'
    check zdraw capabilities cap streaming_paste=no
    [[ $cap[streaming_paste,support] == no && $cap[streaming_paste,source] == override && $cap[streaming_paste,evidence_support] == yes ]] || fail override
    check next_event
    [[ $event[type] == key && $event[key] == UP ]] || fail 'following key'
    reject zdraw query request streaming_paste 100
    check zdraw paste on
    check zdraw query request focus_events 20
    step timeout
    check zdraw event stdscr event norefresh
    [[ $event[type] == capability && $event[phase] == timeout ]] || fail timeout
    check zdraw capabilities cap
    [[ $cap[focus_events,query] == timeout && $cap[focus_events,support] == unknown ]] || fail 'timeout evidence'
    step late
    check next_event
    [[ $event[type] == capability && $event[phase] == late && $event[name] == focus_events ]] || fail late
    check next_event
    [[ $event[type] == paste && $event[phase] == begin ]] || fail 'paste begin'
    reject zdraw query request synchronized_output 100
    check next_event
    [[ $event[type] == paste && $event[text] == $'\e[?2026;1$y' && $event[phase] == end ]] || fail 'report inside paste'
    check zdraw query request synchronized_output 1000
    check zdraw suspend
    check zdraw capabilities cap
    [[ $cap[session] == suspended && $cap[synchronized_output,query] == cancelled && $cap[streaming_paste,enabled] == no ]] || fail 'suspend cancels'
    step suspended
    check zdraw resume
    step resumed
    check next_event
    [[ $event[type] == capability && $event[phase] == late ]] || fail 'cancelled reply'
    check zdraw capabilities cap
    [[ $cap[synchronized_output,support] == unknown && $cap[streaming_paste,enabled] == yes ]] || fail 'resume evidence'
    check zdraw query off
    check zdraw query on
    reject zdraw query request synchronized_output 100
    check zdraw query off
    check zdraw paste off
    step off
    check zdraw input stdscr
    [[ $REPLY == Z ]] || fail 'input after off'
    check zdraw end
    check zdraw init
    check zdraw query on
    check zdraw query request streaming_paste 1000
    check zdraw query cancel
    check zdraw capabilities cap
    [[ $cap[streaming_paste,query] == cancelled && $cap[streaming_paste,support] == unknown ]] || fail cancel
    check zmodload -u zdraw
    check zmodload zdraw
    check zdraw init
    check zdraw capabilities cap
    [[ $cap[streaming_paste,query] == never && $cap[query_owner] == no ]] || fail cleanup
  fi
} always {
  zdraw end
}
check zdraw capabilities cap
[[ $cap[session] == inactive && $cap[streaming_paste,support] == unknown ]] || fail 'end evidence'
print -r -u "$report_fd" -- done
