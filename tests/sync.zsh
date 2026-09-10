emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2 report_fd=$3 control_fd=$4
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
step() { print -r -u "$report_fd" -- "$1"; read -r -u "$control_fd" || fail EOF; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A cap event
typeset -i attempts
step baseline
check zdraw init
{
  check zdraw spans stdscr 0 0 '' BASEFRAME
  check zdraw stage stdscr
  check zdraw present
  step ready
  zdraw sync on 2>/dev/null; (( $? == 2 )) || fail 'evidence required'
  check zdraw capabilities cap synchronized_output=yes
  zdraw sync on 2>/dev/null; (( $? == 2 )) || fail 'override must not activate'
  if [[ $mode == unavailable ]]; then
    [[ $cap[synchronized_output,compiled] == no ]] || fail 'compile gate'
    zdraw sync off; (( $? == 2 )) || fail 'unavailable off'
  else
    [[ $cap[synchronized_output,compiled] == yes ]] || fail 'compiled'
    reject zdraw sync invalid
    check zdraw query on
    check zdraw timeout stdscr 100
    check zdraw query request synchronized_output 1000
    step query
    for (( attempts=0; attempts<30; attempts++ )); do
      zdraw event stdscr event norefresh && [[ $event[type] == capability ]] && break
    done
    [[ ${event[phase]-} == reply ]] || fail 'query reply'
    if [[ $mode == report* ]]; then
      zdraw sync on 2>/dev/null; (( $? == 2 )) || fail 'non-reset evidence'
      check zdraw sync off
    else
      check zdraw sync on
      check zdraw sync on
      check zdraw capabilities cap
      [[ $cap[synchronized_output,enabled] == yes ]] || fail 'configuration'
      check zdraw spans stdscr 1 0 '' HIDDENFRAME
      check zdraw stage stdscr
      step staged
      if [[ $mode == signal ]]; then
        TRAPINT() { print -rn -- TRAP_AFTER_FRAME; return 0; }
      fi
      if [[ $mode == reset-* ]]; then
        reject zdraw present
        step pending-reset
        case $mode in
          reset-off) check zdraw sync off ;;
          reset-suspend) check zdraw suspend; check zdraw resume ;;
          reset-unload)
            check zmodload -u zdraw
            check zmodload zdraw
            check zdraw init ;;
        esac
        step recovered
      elif [[ $mode == failure ]]; then
        reject zdraw present
        step failed
      else
        check zdraw present
        step framed
        check zdraw present
        step empty
        check zdraw spans stdscr 2 0 '' LEGACYFRAME
        check zdraw refresh stdscr
        reject zdraw stage stdscr missing
        step legacy
        check zdraw suspend
        check zdraw capabilities cap
        [[ $cap[synchronized_output,enabled] == no ]] || fail 'suspended configuration'
        step suspended
        check zdraw resume
        check zdraw capabilities cap
        [[ $cap[synchronized_output,enabled] == yes ]] || fail 'resumed configuration'
        step resumed
        check zdraw spans stdscr 3 0 '' RETAINEDFRAME
        check zdraw stage stdscr
        check zdraw present
        step retained
        check zdraw sync off
        check zdraw sync off
        check zdraw spans stdscr 4 0 '' FALLBACKFRAME
        check zdraw stage stdscr
        check zdraw present
        step fallback
      fi
      [[ $mode == reset-unload ]] || check zdraw sync on
      check zmodload -u zdraw
      check zmodload zdraw
      check zdraw init
      check zdraw capabilities cap
      [[ $cap[synchronized_output,enabled] == no && $cap[synchronized_output,reported] == unknown ]] || fail 'unload reset'
    fi
  fi
} always {
  zdraw end
}
print -r -u "$report_fd" -- done
