emulate -R zsh
setopt nounset
module_path=("$1")
zmodload zdraw || exit 1
typeset mode=$2 report_fd=$3 control_fd=$4
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
step() { print -r -u "$report_fd" -- "$1"; read -r -u "$control_fd" || fail EOF; }
typeset -A event cap
typeset -Ar frozen=(sentinel yes)
typeset -i i attempts
next_event() {
  for (( attempts=0; attempts<1000; attempts++ )); do
    zdraw event stdscr event norefresh && return 0
  done
  fail 'missing event'
}
step baseline
check zdraw init
{
  check zdraw timeout stdscr 100
  check zdraw spans stdscr 0 0 '' UNPRESENTED_ENHANCED
  check zdraw stage stdscr
  if [[ $mode == unavailable ]]; then
    zdraw focus on force; (( $? == 2 )) || fail 'unavailable focus'
    zdraw keyboard on; (( $? == 2 )) || fail 'unavailable keyboard'
    check zdraw capabilities cap
    [[ $cap[focus_events,compiled] == no && $cap[keyboard_events,compiled] == no ]] || fail 'optional gates'
  else
    check zdraw inputdelay 25
    zdraw focus on 2>/dev/null; (( $? == 2 )) || fail 'focus requires evidence'
    zdraw keyboard on 2>/dev/null; (( $? == 2 )) || fail 'keyboard requires evidence'
    reject zdraw focus on invalid
    reject zdraw keyboard invalid
    check zdraw query on
    check zdraw query request focus_events 1000
    step focus-query
    check next_event
    [[ $event[type] == capability && $event[report] == 2 ]] || fail 'focus query'
    check zdraw focus on
    check zdraw focus on
    check zdraw query request keyboard_events 1000
    step keyboard-query
    check next_event
    [[ $event[type] == capability && $event[source] == kitty-query && $event[report] == 0 ]] || fail 'keyboard query'
    check zdraw keyboard on
    check zdraw keyboard on
    check zdraw capabilities cap
    [[ $cap[focus_events,compiled] == yes && $cap[focus_events,enabled] == yes && $cap[keyboard_events,enabled] == yes && $cap[keyboard_events,support] == yes ]] || fail 'activation records'
    reject zdraw input stdscr
    step active
    reject zdraw event stdscr frozen norefresh
    check next_event
    [[ $event[type] == focus && $event[focused] == 1 ]] || fail 'focus in'
    check next_event
    [[ $event[type] == focus && $event[focused] == 0 ]] || fail 'focus out'
    for action in press repeat release; do
      check next_event
      [[ $event[type] == key && $event[source] == kitty && $event[action] == $action && $event[modifiers] == CTRL && $event[code] == 97 && $event[text] == '' ]] || fail 'key actions'
    done
    check next_event
    [[ $event[text] == a && $event[text_status] == provided && $event[modifiers] == '' ]] || fail 'associated text'
    check next_event
    [[ $event[key] == ENTER ]] || fail enter
    step coexist
    check next_event
    [[ $event[type] == capability && $event[phase] == late ]] || fail 'capability coexistence'
    check next_event
    [[ $event[type] == key && $event[key] == UP && $event[source] == curses ]] || fail 'legacy coexistence'
    step mouse
    check zdraw event stdscr event mouse norefresh
    [[ $event[type] == mouse && $event[x] == 4 && $event[y] == 2 ]] || fail 'mouse coexistence'
    step partial
    reject zdraw event stdscr event poll norefresh
    reject zdraw suspend
    reject zdraw keyboard off
    step finish
    check next_event
    [[ $event[modifiers] == 'SHIFT CTRL' && $event[text] == A ]] || fail 'fragmented key'
    step more
    check next_event
    [[ $event[key] == LEFT && $event[action] == release && $event[modifiers] == SHIFT ]] || fail 'functional release'
    check next_event
    [[ $event[text] == 'é界' && $event[encoding] == utf-8 ]] || fail 'unicode text'
    check next_event
    [[ $event[modifiers] == 'SHIFT ALT CTRL SUPER HYPER META CAPS_LOCK NUM_LOCK' ]] || fail modifiers
    check next_event
    [[ $event[key] == UNKNOWN && $event[supported] == no ]] || fail 'unknown function'
    step invalid
    for (( i=0; i<8; i++ )); do
      check next_event
      [[ $event[type] == unknown && $event[text] == '' ]] || fail 'malformed packet'
    done
    step text-limit
    check next_event
    [[ $event[type] == unknown && $event[reason] == field-limit && $event[text] == '' ]] || fail 'associated text limit'
    step ambiguous
    check next_event
    [[ $event[type] == character && $event[text] == $'\e' ]] || fail 'legacy escape'
    check next_event
    [[ $event[type] == character && $event[text] == x ]] || fail 'non-CSI prefix'
    check next_event
    [[ $event[type] == unknown && $event[reason] == interrupted-sequence ]] || fail 'interrupted packet'
    check next_event
    [[ $event[type] == key && $event[text] == b ]] || fail 'packet after interruption'
    step scalars
    check next_event
    [[ $event[text] == $'\0\U0010ffff' && $event[base_key] == unknown && $event[shifted_key] == unknown ]] || fail 'bounded scalar text'
    step timeout
    reject zdraw event stdscr event poll norefresh
    check next_event
    [[ $event[type] == unknown && $event[reason] == timeout ]] || fail 'partial timeout'
    step overflow
    check next_event
    [[ $event[type] == unknown && $event[reason] == byte-limit ]] || fail 'packet limit'
    check next_event
    [[ $event[type] == unknown && $event[reason] == discarded-tail ]] || fail 'discard tail'
    check next_event
    [[ $event[type] == character && $event[text] == Z ]] || fail 'following input'
    check zdraw paste on
    step paste
    check next_event
    [[ $event[type] == paste && $event[phase] == begin ]] || fail 'paste begin'
    check next_event
    [[ $event[type] == paste && $event[text] == $'\e[I\e[97;5u' && $event[phase] == end ]] || fail 'paste coexistence'
    check zdraw suspend
    check zdraw capabilities cap
    [[ $cap[focus_events,enabled] == no && $cap[keyboard_events,enabled] == no ]] || fail 'suspended modes'
    step suspended
    check zdraw resume
    check zdraw capabilities cap
    [[ $cap[focus_events,enabled] == yes && $cap[keyboard_events,enabled] == yes ]] || fail 'restored modes'
    step resumed
    check next_event
    [[ $event[type] == focus && $event[focused] == 1 ]] || fail 'resumed focus'
    check zdraw keyboard off
    check zdraw keyboard off
    check zdraw focus off
    check zdraw focus off
    check zdraw paste off
    check zdraw query off
    step legacy
    check zdraw input stdscr
    [[ $REPLY == L ]] || fail 'legacy restored'
    check zdraw focus on force
    check zdraw keyboard on
    check zmodload -u zdraw
    check zmodload zdraw
    check zdraw init
    check zdraw capabilities cap
    [[ $cap[focus_events,enabled] == no && $cap[keyboard_events,enabled] == no && $cap[keyboard_events,query] == never ]] || fail 'unload cleanup'
  fi
} always {
  zdraw end
}
print -r -u "$report_fd" -- done
