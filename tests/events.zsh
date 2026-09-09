#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2 report_fd=$3 control_fd=$4
typeset -a event_flags
[[ ${5-} == norefresh ]] && event_flags=(norefresh)
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
step() { print -r -u "$report_fd" -- "$1"; read -r -u "$control_fd" || fail 'control EOF'; }
typeset -A event=(sentinel yes)
typeset -Ar frozen=(sentinel yes)
typeset scalar=sentinel legacy key
typeset -a array=(sentinel)
reject zdraw event stdscr event "${event_flags[@]}"
[[ $event[sentinel] == yes ]] || fail 'uninitialized query changed target'
step baseline
check zdraw init
{
  (( ${zdraw_features[(Ie)structured_events]} )) || fail 'feature missing'
  check zdraw timeout stdscr 500
  check zdraw refresh
  step ascii
  reject zdraw event stdscr event mouse mouse
  reject zdraw event stdscr event norefresh norefresh
  if [[ $mode == noncurses ]]; then
    (( ! ${zdraw_features[(Ie)norefresh_events]} )) || fail 'unsupported feature advertised'
  fi
  if [[ $mode == noncurses || $mode == pad_failure ]]; then
    zdraw event stdscr event norefresh 2>/dev/null
    typeset -i actual_status=$? expected_status=2
    [[ $mode == pad_failure ]] && expected_status=1
    (( actual_status == expected_status )) || fail 'norefresh failure status'
    [[ $event[sentinel] == yes ]] || fail 'norefresh failure changed output'
  fi
  reject zdraw event stdscr frozen "${event_flags[@]}"
  reject zdraw event stdscr scalar "${event_flags[@]}"
  reject zdraw event stdscr array "${event_flags[@]}"
  reject zdraw event stdscr parameters "${event_flags[@]}"
  reject zdraw event stdscr 'event[x]' "${event_flags[@]}"
  reject zdraw event missing event "${event_flags[@]}"
  reject zdraw event stdscr event bogus "${event_flags[@]}"
  if [[ $mode == nomouse ]]; then
    zdraw event stdscr event mouse "${event_flags[@]}"
    (( $? == 2 )) || fail 'unsupported mouse status'
  fi
  check zdraw event stdscr event "${event_flags[@]}"
  [[ $event[type] == character && $event[text] == a && $event[key] == '' &&
     $event[code] == 97 && $event[modifiers] == unknown && ! -v 'event[sentinel]' ]] || fail 'ASCII record'
  [[ $scalar == sentinel && $array == sentinel && $frozen[sentinel] == yes ]] || fail 'invalid targets changed'
  step encoded
  check zdraw event stdscr event "${event_flags[@]}"
  if [[ $mode == narrow ]]; then
    [[ $event[text] == $'\xff' && $event[encoding] == byte && $event[code] == 255 ]] || fail 'byte event'
  else
    [[ $event[text] == é && $event[encoding] == multibyte && $event[code] == 233 ]] || fail 'Unicode event'
  fi
  step nul
  check zdraw event stdscr event "${event_flags[@]}"
  [[ $event[type] == character && $event[text] == $'\0' && $event[code] == 0 ]] || fail 'NUL event'
  step up
  check zdraw event stdscr event "${event_flags[@]}"
  [[ $event[type] == key && $event[key] == UP && $event[text] == '' &&
     $event[modifiers] == unknown ]] || fail 'UP key'
  step function
  check zdraw event stdscr event "${event_flags[@]}"
  [[ $event[type] == key && $event[key] == F5 ]] || fail 'function key'
  check zdraw timeout stdscr 0
  zdraw event stdscr event "${event_flags[@]}"
  (( $? == 1 )) || fail 'nonblocking empty status'
  [[ $event[key] == F5 ]] || fail 'empty read changed output'
  zdraw event stdscr absent "${event_flags[@]}"
  (( $? == 1 && ! ${+absent} )) || fail 'empty read created output'
  check zdraw timeout stdscr 500
  step legacy
  check zdraw input stdscr legacy key
  [[ $legacy == L && $key == '' ]] || fail 'legacy input'
  step local
  local_event() {
    local -A event
    zdraw event stdscr event || return 1 "${event_flags[@]}"
    [[ $event[type] == character && $event[text] == E ]]
  }
  check local_event
  [[ $event[key] == F5 ]] || fail 'local assignment leaked'
  step create
  check zdraw event stdscr created "${event_flags[@]}"
  [[ $created[type] == character && $created[text] == C ]] || fail 'created target'
  if (( ${zdraw_features[(Ie)resize_events]} )); then
    step resize
    reject zdraw event stdscr frozen "${event_flags[@]}"
    check zdraw event stdscr event "${event_flags[@]}"
    [[ $event[type] == resize && $event[key] == RESIZE &&
       $event[rows] == 32 && $event[columns] == 100 ]] || fail "resize record: ${(kv)event}"
    check zdraw event stdscr event "${event_flags[@]}"
    [[ $event[type] == character && $event[text] == R && ! -v 'event[rows]' ]] || fail 'resize consumed keyboard input'
    check zdraw timeout stdscr 0
    zdraw event stdscr event "${event_flags[@]}"
    (( $? == 1 )) || fail 'resize reported repeatedly'
    check zdraw timeout stdscr 500
  fi
  if (( ${zdraw_features[(Ie)mouse]} )); then
    check zdraw timeout stdscr 0
    zdraw event stdscr event mouse "${event_flags[@]}"
    (( $? == 1 )) || fail 'mouse setup should find no event'
    check zdraw timeout stdscr 500
    step mouse
    check zdraw event stdscr event mouse "${event_flags[@]}"
    [[ $event[type] == mouse && $event[key] == MOUSE &&
       $event[x] == 4 && $event[y] == 2 && $event[modifiers] == '' &&
       ( $event[buttons] == *CLICKED1* || $event[buttons] == *PRESSED1* ) ]] || fail "mouse record: ${(kv)event}"
    step mouseoff
    check zdraw event stdscr event "${event_flags[@]}"
    [[ $event[type] == character && $event[text] == N && ! -v 'event[buttons]' ]] || fail 'mouse state leaked into character'
    check zdraw end
    check zdraw init
    check zdraw timeout stdscr 0
    zdraw event stdscr event mouse "${event_flags[@]}"
    typeset -i result=$?
    if (( result == 0 )); then
      [[ $event[type] == resize ]] || fail 'unexpected event on reinitialization'
      zdraw event stdscr event mouse "${event_flags[@]}"
      result=$?
    fi
    (( result == 1 )) || fail 'second session mouse setup'
    check zdraw timeout stdscr 500
    step mouseagain
    check zdraw event stdscr event mouse "${event_flags[@]}"
    [[ $event[type] == mouse ]] || fail 'mouse did not re-enable after end'
  fi
} always {
  zdraw end
}
print -r -u "$report_fd" -- done
