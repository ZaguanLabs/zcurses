#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
typeset root=${0:A:h:h}
source "$root/lib/zdraw-document.zsh" || exit 1
module_path=("$1")
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
same() {
  local -A actual=("$@")
  local field
  [[ ${#before} == ${#actual} ]] || fail 'association size changed'
  for field in "${(@k)before}"; do
    [[ ${actual[$field]-} == "$before[$field]" ]] || fail "changed key: $field"
  done
}
typeset -A zdraw_ui_theme zdraw_ui_document before after info zdraw_ui_style=(sentinel yes)
typeset -a position reply=(sentinel)
check zdraw-ui-theme dark 256
check zdraw-document-init 20 intro heading 'A good beginning' text paragraph 'A paragraph with room to breathe.' \
  code code $'echo hello\n  world' line separator '' list bullet 'A useful detail'
check zdraw init
{
  check zdraw addwin sample 12 22 1 1
  check zdraw attr sample underline 2/0
  check zdraw move sample 11 20
  check zdraw-document sample 0 1 10 20 normal heading:fg=error code:bg=inactive
  check zdraw snapshot sample after
  [[ $after[0,1,text] == A && $after[0,1,color] == 210/236 && $after[0,1,attributes] == bold ]] || fail 'heading role'
  [[ $after[2,1,text] == A && $after[3,1,text] == r ]] || fail 'paragraph wrapping'
  [[ $after[5,3,text] == e && $after[5,1,color] == 252/238 && $after[8,1,text] == '-' ]] || fail 'code and separator'
  before=("${(@kv)after}")
  reject zdraw-document sample 0 1 10 19 normal
  reject zdraw-document sample 0 1 10 20 normal quote:fg=bogus
  reject zdraw-document sample 0 1 10 20 normal code:px=1
  check zdraw snapshot sample after
  same "${(@kv)after}"
  check zdraw-document-scroll 2 anchor list
  check zdraw-document sample 0 1 2 20 inactive
  check zdraw snapshot sample after
  [[ $after[1,1,text] == '-' && $after[1,3,text] == A ]] || fail 'anchor viewport'
  check zdraw-document-init 20
  check zdraw-document sample 0 1 10 20 normal
  check zdraw snapshot sample after
  [[ $after[0,1,text] == ' ' && $after[8,1,text] == ' ' ]] || fail 'empty clears'
  check zdraw position sample position
  [[ $position[1] == 11 && $position[2] == 20 ]] || fail cursor
  check zdraw char sample X
  check zdraw move sample 11 20
  check zdraw cellinfo sample info
  [[ $info[color] == 2/0 && $info[attributes] == underline ]] || fail attributes
  [[ $zdraw_ui_style[sentinel] == yes && $reply == sentinel ]] || fail 'public outputs leaked'
  check zdraw refresh sample
} always {
  zdraw end
}
print -r -- 'UI DOCUMENT DRAW PASS'
