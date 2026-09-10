#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
typeset root=${0:A:h:h}
source "$root/lib/zdraw-form.zsh" || exit 1
module_path=("$1")
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A zdraw_ui_theme zdraw_ui_input zdraw_ui_form before after info
typeset -a position
check zdraw-ui-theme dark 256
check zdraw init
{
  check zdraw addwin sample 10 30 1 1
  check zdraw attr sample underline 2/0
  check zdraw move sample 9 28
  check zdraw-input-init abcdef
  check zdraw-input sample 0 0 4 focus
  check zdraw snapshot sample after
  [[ $after[0,0,text] == d && $after[0,2,text] == f && $after[0,3,attributes] == reverse ]] || fail 'horizontal scroll/caret'
  check zdraw-input-edit select-home
  check zdraw-input sample 0 0 8 inactive selected:bg=accent selected:no-reverse
  check zdraw snapshot sample after
  [[ $after[0,0,color] == 231/80 && $after[0,5,color] == 231/80 && $after[0,6,color] == 252/236 ]] || fail 'selection styling'
  check zdraw-input-init 界x
  check zdraw-input-edit home
  check zdraw-input sample 1 29 1 focus
  check zdraw snapshot sample before
  [[ $before[1,29,text] == ' ' && $before[1,29,attributes] == reverse ]] || fail 'narrow wide caret'
  reject zdraw-input sample 1 0 30 focus 'cursor:fg=bogus'
  check zdraw snapshot sample after
  [[ ${(kv)before} == ${(kv)after} ]] || fail 'invalid draw changed screen'
  check zdraw-form-init Name '' required Port 80 integer,min=1,max=65535
  reject zdraw-form-action validate
  check zdraw-form sample 2 0 6 30 focus
  check zdraw snapshot sample after
  [[ $after[2,0,text] == N && $after[4,0,text] == T && $after[4,0,color] == 210/236 && $after[6,0,text] == 8 ]] || fail 'form labels/value/error'
  check zdraw-form-action next
  check zdraw-form sample 2 0 3 30 focus
  check zdraw snapshot sample after
  [[ $after[2,0,text] == P && $after[3,0,text] == 8 ]] || fail 'focused field viewport'
  reject zdraw-form sample 2 0 2 30 focus
  check zdraw position sample position
  [[ $position[1] == 9 && $position[2] == 28 ]] || fail cursor
  check zdraw char sample X
  check zdraw move sample 9 28
  check zdraw cellinfo sample info
  [[ $info[color] == 2/0 && $info[attributes] == underline ]] || fail attributes
  check zdraw refresh sample
} always {
  zdraw end
}
print -r -- 'UI FORM PASS'
