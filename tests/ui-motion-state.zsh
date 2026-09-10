#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
alias local='false ALIAS'
setopt shwordsplit ksharrays globsubst
source "${0:A:h:h}/lib/zdraw-motion.zsh" || exit 1
[[ -o shwordsplit && -o ksharrays && -o globsubst ]] || fail 'loader options'
unsetopt shwordsplit ksharrays globsubst
unalias local
zmodload -e zdraw && fail 'passive loader loaded module'
typeset -A zdraw_ui_motion before
# Pure state and hidden rendering must never call the native module.
zdraw() { fail 'unexpected native call'; }
check zdraw-motion-init activity on
repeat 100; do
  for frame in 1 2 3 0; do
    check zdraw-motion-action advance
    [[ $zdraw_ui_motion[frame] == $frame && $zdraw_ui_motion[changed] == 1 ]] || fail 'frame sequence'
  done
done
check zdraw-motion-action hide
repeat 100; do check zdraw-motion-action advance; done
[[ $zdraw_ui_motion[frame] == 0 && $zdraw_ui_motion[changed] == 0 ]] || fail 'hidden advanced'
check zdraw-activity nonexistent 999 999 normal
check zdraw-motion-action show
check zdraw-motion-action pause
repeat 100; do check zdraw-motion-action advance; done
[[ $zdraw_ui_motion[phase] == paused && $zdraw_ui_motion[changed] == 0 ]] || fail 'pause advanced'
check zdraw-motion-action resume
check zdraw-motion-action advance
check zdraw-motion-action reduced
repeat 100; do check zdraw-motion-action advance; done
[[ $zdraw_ui_motion[frame] == 0 && $zdraw_ui_motion[changed] == 0 ]] || fail 'reduced advanced'
check zdraw-motion-action finish
check zdraw-motion-action on
check zdraw-motion-action advance
[[ $zdraw_ui_motion[phase] == complete ]] || fail 'mode restarted completion'
check zdraw-motion-action restart
check zdraw-motion-action cancel
check zdraw-motion-action advance
[[ $zdraw_ui_motion[phase] == cancelled && $zdraw_ui_motion[changed] == 0 ]] || fail 'cancel advanced'
for mode in on reduced off; do
  check zdraw-motion-init settle "$mode"
  if [[ $mode == on ]]; then
    check zdraw-motion-action advance
    [[ $zdraw_ui_motion[frame] == 1 && $zdraw_ui_motion[phase] == running ]] || fail 'middle frame'
    check zdraw-motion-action advance
  fi
  [[ $zdraw_ui_motion[frame] == 2 && $zdraw_ui_motion[phase] == complete ]] || fail 'completion'
  check zdraw-motion-action advance
  [[ $zdraw_ui_motion[changed] == 0 ]] || fail 'completed advancement'
done
check zdraw-motion-init settle on
check zdraw-motion-action hide
check zdraw-settle nonexistent 99 99 99 99 normal
check zdraw-motion-action reduced
[[ $zdraw_ui_motion[phase] == complete ]] || fail 'hidden reduced completion'
before=("${(@kv)zdraw_ui_motion}")
reject zdraw-motion-init unknown on
reject zdraw-motion-action bogus
for key in "${(@k)before}"; do [[ $before[$key] == "$zdraw_ui_motion[$key]" ]] || fail 'failed action changed state'; done
typeset -i marker=0
zdraw_ui_motion[frame]='marker=1'
reject zdraw-motion-action advance
(( marker == 0 )) || fail 'arithmetic evaluation'
zdraw_ui_motion=("${(@kv)before}")
zdraw_ui_motion[extra]=bad
reject zdraw-motion-action advance
zdraw_ui_motion=("${(@kv)before}")
setopt shwordsplit ksharrays globsubst
check zdraw-motion-action restart
[[ -o shwordsplit && -o ksharrays && -o globsubst ]] || fail 'action options'
print -r -- 'UI MOTION STATE PASS'
