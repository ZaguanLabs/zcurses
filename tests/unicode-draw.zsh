#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
zmodload zdraw || exit 1
source "${0:A:h:h}/lib/zdraw-input.zsh" || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
typeset -A zdraw_ui_input zdraw_ui_theme snap
typeset -a pos
check zdraw-ui-theme dark mono
check zdraw init
{
  check zdraw addwin sample 4 20 1 1
  check zdraw move sample 3 19
  check zdraw-input-init '👍🏽X' 64 grapheme
  check zdraw-input-edit home
  check zdraw-input-edit select-right
  check zdraw-input sample 0 0 5 inactive
  check zdraw snapshot sample snap
  [[ $snap[0,0,text] == '👍' && $snap[0,2,text] == '🏽' && $snap[0,4,text] == X ]] || fail 'retained cells'
  [[ $snap[0,0,attributes] == reverse && $snap[0,2,attributes] == reverse && $snap[0,4,attributes] != reverse ]] || fail 'selection whole unit'
  check zdraw-input-edit home
  check zdraw-input sample 1 0 3 focus
  check zdraw snapshot sample snap
  [[ $snap[1,0,text] == ' ' && $snap[1,1,text] == ' ' && $snap[1,2,text] == ' ' ]] || fail 'partial grapheme drawn'
  check zdraw-input-init 'A👍🏽X' 64 grapheme
  check zdraw-input-edit home
  check zdraw-input sample 2 0 3 inactive
  check zdraw snapshot sample snap
  [[ $snap[2,0,text] == A && $snap[2,1,text] == ' ' && $snap[2,2,text] == ' ' ]] || fail 'right clip split'
  check zdraw-input-edit end
  check zdraw-input sample 3 0 3 focus
  check zdraw position sample pos
  [[ $pos[1] == 3 && $pos[2] == 19 ]] || fail cursor
} always {
  zdraw end || exit 1
}
print -r -- 'UNICODE DRAW PASS'
