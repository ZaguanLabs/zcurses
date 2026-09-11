#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
zmodload zdraw || exit 1
source "${0:A:h:h}/examples/components/status-strip.zsh" || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A zdraw_ui_theme zdraw_ui_style=(sentinel unchanged) before after theme_before cell
typeset -a reply=(sentinel)
typeset field phase word marker
check zdraw-ui-theme dark 256
theme_before=("${(@kv)zdraw_ui_theme}")
check zdraw init
{
  check zdraw attr stdscr underline green/black
  check zdraw move stdscr 0 0
  check zdraw-status-strip stdscr 2 3 2 74 working 'Check sources' 'Scanning headers' value=1 total=2
  check zdraw snapshot stdscr after
  [[ $after[2,3,text] == '*' && $after[2,5,text] == W && $after[2,13,text] == C &&
     $after[3,13,text] == S && $after[3,59,text] == '=' && $after[3,76,text] == '%' &&
     $after[cursor_row] == 0 && $after[cursor_column] == 0 ]] || fail 'layout, meter or cursor'
  check zdraw string stdscr X
  check zdraw move stdscr 0 0
  check zdraw cellinfo stdscr cell
  [[ $cell[color] == green/black && $cell[attributes] == underline ]] || fail 'window style changed'
  check zdraw-status-strip stdscr 2 3 2 74 working title detail key:fg=5
  check zdraw snapshot stdscr after
  [[ $after[2,3,color] == 5/234 && $after[3,59,text] == ' ' && $reply == sentinel &&
     $zdraw_ui_style[sentinel] == unchanged ]] || fail 'override, unknown total or caller scope'
  for field in "${(@k)theme_before}"; do [[ $theme_before[$field] == "$zdraw_ui_theme[$field]" ]] || fail 'theme changed'; done
  check zdraw-status-strip stdscr 2 3 2 74 working title detail
  check zdraw snapshot stdscr before
  [[ $before[2,3,color] == 80/234 ]] || fail 'override leaked'
  reject zdraw-status-strip stdscr 2 3 2 74 unknown title detail
  reject zdraw-status-strip stdscr 2 3 2 74 working title detail value=2 total=1
  reject zdraw-status-strip stdscr 2 3 2 74 working title detail value=0 total=0
  reject zdraw-status-strip stdscr 2 3 2 74 working title detail value=1
  reject zdraw-status-strip stdscr 2 3 2 74 working title detail value= total=
  reject zdraw-status-strip stdscr 2 3 2 74 working title detail value='evil=1' total=2
  reject zdraw-status-strip stdscr 2 3 1 74 working title $'hidden\e'
  reject zdraw-status-strip stdscr 2 3 2 74 working title detail invalid:fg=bogus
  reject zdraw-status-strip stdscr 2 3 2 74 working title detail px=1
  zdraw-status-strip stdscr 2 3 2 23 working title detail 2>/dev/null
  (( $?==2 && !${+evil} )) || fail 'small width or evaluated value'
  check zdraw snapshot stdscr after
  for field in "${(@k)before}"; do [[ $before[$field] == "$after[$field]" ]] || fail 'failure changed screen'; done
  for phase word marker in working W '*' waiting W '?' done D '+' failed F '!'; do
    check zdraw-status-strip stdscr 2 3 1 24 "$phase" 'A deliberately long title' 'Hidden detail' value=1 total=2
    check zdraw snapshot stdscr after
    [[ $after[2,3,text] == "$marker" && $after[2,5,text] == "$word" && $after[2,26,text] == '%' ]] || fail 'narrow state lost'
  done
  check zdraw-status-strip stdscr 2 3 2 24 failed title 'Failure detail' value=1 total=2
  check zdraw snapshot stdscr after
  [[ $after[3,3,text] == F && $after[3,26,text] == '%' && $after[2,3,color] == 210/234 ]] || fail 'narrow detail or failure color'
  check zdraw-ui-theme dark mono
  check zdraw-status-strip stdscr 2 3 2 74 working title detail
  check zdraw snapshot stdscr after
  [[ $after[2,3,text] == '*' && $after[2,5,text] == W && $after[3,76,text] == ' ' ]] || fail 'mono unknown total'
} always {
  zdraw end
}
print -r -- 'STATUS STRIP PASS'
