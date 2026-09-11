#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
typeset root=${0:A:h:h} logfile=${0:A:h:h}/.build/ui-diagnostics-$$.log
source "$root/lib/zdraw-panel.zsh" || exit 1
source "$root/lib/zdraw-table.zsh" || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
expect() {
  local expected=$1 result
  shift
  "$@"
  result=$?
  [[ $result == $expected ]] || fail "expected $expected, got $result: $*"
}
typeset -A zdraw_ui_theme zdraw_ui_style=(sentinel unchanged) zdraw_ui_layout=(sentinel unchanged)
typeset -a reply
# No sink: failures preserve status and produce no stdout/stderr.
expect 1 zdraw-ui-style normal border=cloud
{
  exec {ZDRAW_UI_DEBUG_FD}>"$logfile"
  expect 1 zdraw-ui-style normal border=cloud
  expect 1 zdraw-ui-style normal px=17
  expect 1 zdraw-ui-style normal 'fg=$(touch SHOULD_NOT_EXIST)'
  () {
    local reply=wrong-type
    expect 1 zdraw-panel sample 0 0 2 4 Title normal
  }
  expect 2 zdraw-layout-split 0 0 1 3 columns 1 fixed=2 fixed=2
  # A real native failure must retain its original status, including a
  # nonstandard one supplied by an application wrapper.
  function zdraw { return 7; }
  expect 7 zdraw-label sample 0 0 4 Text normal
  expect 7 _zdraw_ui_row sample 0 0 4 left Text ''
  unfunction zdraw
  print -r -u "$ZDRAW_UI_DEBUG_FD" -- 'descriptor still owned by caller'
  exec {ZDRAW_UI_DEBUG_FD}>&-
  # Closed/malformed sinks must not make logging a new source of failure.
  expect 1 zdraw-ui-style normal px=17
  unset ZDRAW_UI_DEBUG_FD
  ZDRAW_UI_DEBUG_FD='1+evil=1'
  expect 1 zdraw-ui-style normal px=17
  (( ! ${+evil} )) || fail 'descriptor arithmetic evaluated'
  unset ZDRAW_UI_DEBUG_FD
  typeset log=$(<"$logfile")
  [[ $log == *'unknown border "cloud"'* && $log == *'padding must be from 0 to 16'* &&
     $log == *'writable reply array'* && $log == *'(status 2)'* &&
     $log == *'native position failed (status 7)'* &&
     $log == *'native spansclip failed (status 7)'* &&
     $log == *'descriptor still owned by caller'* ]] || fail "missing diagnosis: $log"
  [[ $zdraw_ui_style[sentinel] == unchanged && $zdraw_ui_layout[sentinel] == unchanged ]] || fail 'failed validation changed output'
} always {
  rm -f -- "$logfile"
}
print -r -- 'UI DIAGNOSTICS PASS'
