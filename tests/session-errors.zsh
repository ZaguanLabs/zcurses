emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A info
check zdraw init
{
  if [[ $mode == paste_failure ]]; then
    reject zdraw paste on
    check zdraw inputinfo info
    [[ $info[paste_enabled] == 0 ]] || fail 'failed key registration claimed input'
  elif [[ $mode == suspend_failure ]]; then
    reject zdraw suspend
    check zdraw inputinfo info
    [[ $info[suspended] == 0 ]] || fail 'failed suspend changed state'
    check zdraw stage stdscr
    check zdraw present
  else
    check zdraw suspend
    reject zdraw resume
    check zdraw inputinfo info
    [[ $info[suspended] == 1 ]] || fail 'failed resume lost suspended state'
    reject zdraw present
  fi
} always {
  zdraw end
}
print -r -- 'SESSION ERRORS PASS'
