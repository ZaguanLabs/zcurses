#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
typeset root=${0:A:h:h}
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
alias local='false ALIAS_LEAK'
setopt shwordsplit ksharrays globsubst
source "$root/lib/zdraw-table.zsh" || exit 1
[[ -o shwordsplit && -o ksharrays && -o globsubst ]] || fail 'loader options'
unsetopt shwordsplit ksharrays globsubst
unalias local
zmodload -e zdraw && fail 'loader loaded native module'
whence -w zdraw-list >/dev/null && fail 'table loaded list renderer'
typeset -A zdraw_ui_theme zdraw_ui_table zdraw_ui_style zdraw_ui_list=(sentinel unchanged)
typeset -a zdraw_ui_headers=(Name Jobs) zdraw_ui_tracks=(flex=1 fixed=4)
typeset -a zdraw_ui_alignments=(left right) reply=(sentinel)
zdraw_ui_table[app-filter]='my query'
check zdraw-table-update 4 3 end
[[ $zdraw_ui_table[selected] == 4 && $zdraw_ui_table[first] == 2 ]] || fail 'table scrolling'
[[ $zdraw_ui_table[app-filter] == 'my query' ]] || fail 'application table state discarded'
[[ $zdraw_ui_list[sentinel] == unchanged ]] || fail 'list state leaked'
reject zdraw-table-update 'evil=1' 3 keep
[[ $zdraw_ui_table[selected] == 4 ]] || fail 'invalid update changed state'
() {
  local -A zdraw_ui_table
  check zdraw-table-update 0 0 keep
  [[ $zdraw_ui_table[selected] == 0 ]] || fail 'local state'
}
() {
  local -Ar zdraw_ui_table=(selected 1 first 1)
  reject zdraw-table-update 4 3 down
}
module_path=("$1")
zmodload zdraw || exit 1
typeset -A before after info zdraw_ui_layout=(sentinel unchanged)
typeset -a position cells=(alpha 1 beta 12 gamma 3 delta 100)
typeset field
same() {
  for field in "${(@k)before}"; do
    [[ $before[$field] == "$after[$field]" ]] || fail "changed snapshot: $field"
  done
}
check zdraw-ui-theme dark 256
zdraw_ui_style=(sentinel unchanged)
check zdraw init
{
  check zdraw addwin sample 10 40 1 1
  check zdraw attr sample underline 2/0
  check zdraw move sample 9 38
  check zdraw-table sample 0 0 4 30 focus gap=2 -- "${cells[@]}"
  check zdraw snapshot sample before
  [[ $before[0,2,text] == N && $before[0,26,text] == J && $before[0,2,color] == 80/236 && $before[0,2,attributes] == bold ]] || fail 'header layout/style'
  [[ $before[1,2,text] == b && $before[1,28,text] == 1 && $before[1,29,text] == 2 ]] || fail 'cell alignment'
  [[ $before[1,2,color] == 252/234 && $before[2,2,color] == 252/236 ]] || fail 'source row stripes'
  [[ $before[3,0,text] == '>' && $before[3,2,text] == d && $before[3,27,text] == 1 && $before[3,2,color] == 231/30 ]] || fail 'selected row'
  check zdraw-table sample 0 0 4 30 inactive gap=2 header:fg=error selected+inactive:bg=52 -- "${cells[@]}"
  check zdraw snapshot sample before
  [[ $before[0,2,color] == 210/236 && $before[3,2,color] == 252/52 ]] || fail 'part overrides'
  # Validation includes offscreen cells, missing values and inactive variants.
  reject zdraw-table sample 0 0 4 30 focus -- $'bad\ncell' 1 beta 12 gamma 3 delta 100
  reject zdraw-table sample 0 0 4 30 focus -- "${cells[@]}" dangling
  reject zdraw-table sample 0 0 4 30 focus gap=evil -- "${cells[@]}"
  reject zdraw-table sample 0 0 4 30 focus header:fg=unknown -- "${cells[@]}"
  reject zdraw-table sample 0 0 4 30 focus selected:py=1 -- "${cells[@]}"
  () {
    local -a zdraw_ui_tracks=(fixed=30 fixed=20)
    zdraw-table sample 0 0 4 30 focus -- "${cells[@]}"
    [[ $? == 2 ]] || fail 'insufficient column space'
  }
  () {
    local -a zdraw_ui_alignments=(left 'evil=1')
    reject zdraw-table sample 0 0 4 30 focus -- "${cells[@]}"
  }
  check zdraw snapshot sample after
  same
  check zdraw-table sample 0 0 4 30 disabled gap=2 -- "${cells[@]}"
  check zdraw snapshot sample after
  [[ $after[3,2,color] == 245/236 && -z $after[3,2,attributes] ]] || fail 'disabled style'
  check zdraw-table-update 4 4 home
  check zdraw-table sample 0 0 4 30 focus header=off -- "${cells[@]}"
  check zdraw snapshot sample after
  [[ $after[0,2,text] == a ]] || fail 'header off'
  check zdraw-table-update 0 3 keep
  check zdraw-table sample 0 0 4 30 focus empty-text=Empty empty:fg=accent empty:bg=canvas --
  check zdraw snapshot sample after
  [[ $after[1,0,text] == E && $after[1,0,color] == 80/234 && $after[1,29,color] == 80/234 && $after[3,2,text] == ' ' ]] || fail 'empty table clearing'
  check zdraw-table sample 0 0 1 30 focus --
  check zdraw-ui-theme dark mono
  check zdraw-table-update 1 1 keep
  check zdraw-table sample 0 0 2 30 focus -- alpha 1
  check zdraw snapshot sample after
  [[ $after[1,2,pair] == 0 && $after[1,2,attributes] == 'bold reverse' ]] || fail 'mono selection'
  () {
    local -a zdraw_ui_headers=(Only) zdraw_ui_tracks=(flex=1) zdraw_ui_alignments=(inherit)
    check zdraw-table sample 0 39 1 1 focus header=off -- alpha
  }
  check zdraw-ui-theme dark 256
  () {
    local -a zdraw_ui_headers=(Word) zdraw_ui_tracks=(flex=1) zdraw_ui_alignments
    unset zdraw_ui_alignments
    setopt shwordsplit ksharrays globsubst
    check zdraw-table sample 5 0 2 10 focus align=right -- '-*'
    [[ -o shwordsplit && -o ksharrays && -o globsubst ]] || fail 'caller options changed'
    unsetopt shwordsplit ksharrays globsubst
    check zdraw snapshot sample after
    [[ $after[6,8,text] == '-' && $after[6,9,text] == '*' ]] || fail 'inherited alignment / literal cells'
  }
  () {
    local -a zdraw_ui_headers=(Word) zdraw_ui_tracks=(flex=1) zdraw_ui_alignments=(right)
    check zdraw-table sample 5 0 2 4 focus -- $'e\u0301界'
    check zdraw snapshot sample after
    [[ $after[6,3,text] == $'e\u0301' ]] || fail 'complete clipping units'
  }
  check zdraw position sample position
  [[ $position[1] == 9 && $position[2] == 38 ]] || fail 'cursor moved'
  check zdraw char sample X
  check zdraw move sample 9 38
  check zdraw cellinfo sample info
  [[ $info[color] == 2/0 && $info[attributes] == underline ]] || fail 'drawing style leaked'
  [[ $reply == sentinel && $zdraw_ui_layout[sentinel] == unchanged && $zdraw_ui_style[sentinel] == unchanged ]] || fail 'caller outputs changed'
  check zdraw refresh sample
} always {
  zdraw end
}
print -r -- 'UI TABLE PASS'
