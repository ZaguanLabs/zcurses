#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
zmodload zdraw || exit 1
source "${0:A:h:h}/examples/components/linked-detail.zsh" || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A zdraw_ui_theme zdraw_ui_list=(selected 3 first 1) zdraw_ui_link=(sentinel unchanged)
typeset -A zdraw_ui_style=(sentinel unchanged) before after theme_before state_before link_before cell
typeset -a reply=(sentinel) items=(one first two second three third four fourth five fifth six sixth) reply_before
typeset field
same() {
  (( ${#before} == ${#after} )) || fail 'snapshot shape'
  for field in "${(@k)before}"; do
    [[ $before[$field] == "$after[$field]" ]] || fail "snapshot mismatch: $field"
  done
}
check zdraw-ui-theme dark 256
theme_before=("${(@kv)zdraw_ui_theme}")
check zdraw init
{
  check zdraw attr stdscr underline green/black
  check zdraw move stdscr 0 0
  check zdraw-linked-detail stdscr 2 3 18 74 list glyphs=ascii -- "${items[@]}"
  [[ $reply == '4 33 16 44' && $zdraw_ui_list[selected] == 3 && $zdraw_ui_link[selected_row] == 10 ]] || fail 'geometry or caller state'
  check zdraw snapshot stdscr after
  [[ $after[10,3,text] == '>' && $after[12,4,text] == ' ' && $after[11,27,text] == ' ' && $after[4,29,text] == '+' &&
     $after[cursor_row] == 0 && $after[cursor_column] == 0 ]] || fail 'connector, shadow or cursor'
  check zdraw string stdscr X
  check zdraw move stdscr 0 0
  check zdraw cellinfo stdscr cell
  [[ $cell[color] == green/black && $cell[attributes] == underline ]] || fail 'window style changed'
  check zdraw-linked-detail stdscr 2 3 18 74 list glyphs=ascii selected:bg=5 -- "${items[@]}"
  check zdraw snapshot stdscr after
  [[ $after[10,5,color] == 231/5 && $zdraw_ui_style[sentinel] == unchanged ]] || fail 'override or style scope'
  for field in "${(@k)theme_before}"; do
    [[ $theme_before[$field] == "$zdraw_ui_theme[$field]" ]] || fail 'theme mutated'
  done
  check zdraw-linked-detail stdscr 2 3 18 74 list glyphs=ascii -- "${items[@]}"
  check zdraw snapshot stdscr before
  [[ $before[10,5,color] == 231/30 && $before[12,4,text] == ' ' ]] || fail 'override/shadow leaked'
  state_before=("${(@kv)zdraw_ui_list}") link_before=("${(@kv)zdraw_ui_link}") reply_before=("${reply[@]}")
  reject zdraw-linked-detail stdscr 2 3 18 74 list -- unpaired
  reject zdraw-linked-detail stdscr 2 3 18 74 list -- one $'bad\e'
  reject zdraw-linked-detail stdscr 2 3 18 74 list inactive:fg=bogus -- "${items[@]}"
  reject zdraw-linked-detail stdscr 2 3 18 74 list px=1 -- "${items[@]}"
  reject zdraw-linked-detail stdscr 2 3 18 74 list depth=raised -- "${items[@]}"
  reject zdraw-linked-detail stdscr 2 3 18 74 list shadow-size=thin -- "${items[@]}"
  reject zdraw-linked-detail stdscr 2 3 18 74 list item-gap='evil=1' -- "${items[@]}"
  reject zdraw-linked-detail stdscr 'evil=1' 3 18 74 list -- "${items[@]}"
  zdraw-linked-detail stdscr 2 3 5 23 list -- "${items[@]}" 2>/dev/null
  (( $? == 2 && ! ${+evil} )) || fail 'small rectangle or evaluated geometry'
  check zdraw snapshot stdscr after
  same
  [[ $reply == "$reply_before" ]] || fail 'failure changed reply'
  for field in "${(@k)state_before}"; do [[ $state_before[$field] == "$zdraw_ui_list[$field]" ]] || fail 'failure changed list'; done
  for field in "${(@k)link_before}"; do [[ $link_before[$field] == "$zdraw_ui_link[$field]" ]] || fail 'failure changed link'; done
  check zdraw-linked-detail stdscr 2 3 18 74 list item-gap=0 -- "${items[@]}"
  check zdraw snapshot stdscr after
  [[ $zdraw_ui_link[visible] == 7 && $after[9,27,text] == ' ' && $after[10,5,text] == f &&
     $after[10,27,text] == ' ' ]] || fail 'compact spacing overwrote following entry'
  zdraw_ui_list=(selected 6 first 1)
  check zdraw-linked-detail stdscr 2 3 9 40 list -- "${items[@]}"
  [[ $zdraw_ui_list[first] == 5 && $reply == '0 0 0 0' ]] || fail 'viewport reconciliation'
  check zdraw-linked-detail stdscr 2 3 9 40 detail -- "${items[@]}"
  [[ $reply == '4 3 7 40' && $zdraw_ui_list[selected] == 6 ]] || fail 'focused narrow pane'
  check zdraw-linked-detail stdscr 2 3 9 40 detail --
  [[ $zdraw_ui_list[selected] == 0 && $zdraw_ui_link[selected_row] == -1 ]] || fail 'empty reconciliation'
} always {
  zdraw end
}
print -r -- 'LINKED DETAIL PASS'
