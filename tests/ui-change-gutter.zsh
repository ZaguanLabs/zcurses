#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
zmodload zdraw || exit 1
source "${0:A:h:h}/examples/components/change-gutter.zsh" || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A zdraw_ui_theme zdraw_ui_gutter zdraw_ui_style=(sentinel unchanged)
typeset -A before after theme_before output_before cell
typeset -a data=(hunk - - '@@ Reading notes @@' context 41 41 'Keep this line.' remove 42 - 'Old wording.' add - 42 'New wording.')
typeset field
check zdraw-ui-theme dark 256
theme_before=("${(@kv)zdraw_ui_theme}")
check zdraw init
{
  check zdraw attr stdscr underline green/black
  check zdraw move stdscr 0 0
  check zdraw-change-gutter stdscr 2 3 8 74 1 glyphs=ascii -- "${data[@]}"
  check zdraw snapshot stdscr after
  [[ $after[2,3,text] == O && $after[2,7,text] == N && $after[3,3,text] == @ &&
     $after[5,11,text] == '-' && $after[6,11,text] == '+' &&
     $after[5,15,text] == O && $after[6,15,text] == N &&
     $after[cursor_row] == 0 && $after[cursor_column] == 0 ]] || fail 'gutter alignment or cursor'
  [[ $after[5,11,color] == 210/236 && $after[6,11,color] == 80/236 ]] || fail 'semantic marker colors'
  check zdraw string stdscr X
  check zdraw move stdscr 0 0
  check zdraw cellinfo stdscr cell
  [[ $cell[color] == green/black && $cell[attributes] == underline ]] || fail 'window style changed'
  check zdraw-change-gutter stdscr 2 3 8 74 1 positive:fg=5 -- "${data[@]}"
  check zdraw snapshot stdscr after
  [[ $after[6,11,color] == 5/236 && $zdraw_ui_style[sentinel] == unchanged ]] || fail 'local override'
  for field in "${(@k)theme_before}"; do
    [[ $theme_before[$field] == "$zdraw_ui_theme[$field]" ]] || fail 'theme changed'
  done
  check zdraw-change-gutter stdscr 2 3 8 74 1 -- "${data[@]}"
  check zdraw snapshot stdscr before
  [[ $before[6,11,color] == 80/236 ]] || fail 'override leaked'
  output_before=("${(@kv)zdraw_ui_gutter}")
  reject zdraw-change-gutter stdscr 2 3 8 74 1 -- add 1 2 invalid
  reject zdraw-change-gutter stdscr 2 3 8 74 1 -- remove - 2 invalid
  reject zdraw-change-gutter stdscr 2 3 8 74 1 -- context 'evil=1' 1 invalid
  reject zdraw-change-gutter stdscr 2 3 8 74 1 -- context 0 1 invalid
  reject zdraw-change-gutter stdscr 2 3 8 74 1 -- context 1234567 1 invalid
  reject zdraw-change-gutter stdscr 2 3 8 74 1 -- add - 2 $'hidden\e'
  reject zdraw-change-gutter stdscr 2 3 8 74 1 -- add - 2
  reject zdraw-change-gutter stdscr 2 3 8 74 1 offset='evil=1' -- "${data[@]}"
  reject zdraw-change-gutter stdscr 2 3 8 74 1 negative:fg=bogus -- "${data[@]}"
  zdraw-change-gutter stdscr 2 3 1 16 1 -- "${data[@]}" 2>/dev/null
  (( $? == 2 && ! ${+evil} )) || fail 'small rectangle or evaluated geometry'
  check zdraw snapshot stdscr after
  for field in "${(@k)before}"; do [[ $before[$field] == "$after[$field]" ]] || fail 'failure changed screen'; done
  for field in "${(@k)output_before}"; do [[ $output_before[$field] == "$zdraw_ui_gutter[$field]" ]] || fail 'failure changed output'; done
  # A wide character straddling the pan boundary becomes one blank cell.
  check zdraw-change-gutter stdscr 2 3 5 28 1 offset=1 -- add - 99 $'界e\u0301abcdefghijklmnopqrstuvwxyz'
  check zdraw snapshot stdscr after
  [[ $zdraw_ui_gutter[numbers] == single && $after[3,11,text] == ' ' &&
     $after[3,12,text] == $'e\u0301' && $after[3,30,text] == '>' && $after[3,7,text] == '+' ]] || fail 'cell-aligned pan or clipping'
  check zdraw-change-gutter stdscr 2 3 5 28 1 -- remove 123456 - old add - 123456 new
  check zdraw snapshot stdscr after
  [[ $after[3,3,text] == 1 && $after[3,8,text] == 6 && $after[3,10,text] == '-' &&
     $after[4,10,text] == '+' && $after[4,14,text] == n ]] || fail 'six-digit compact line numbers'
  check zdraw-change-gutter stdscr 2 3 3 28 32767 -- "${data[@]}"
  [[ $zdraw_ui_gutter[first] == 3 && $zdraw_ui_gutter[visible] == 2 ]] || fail 'scroll clamp'
  check zdraw-change-gutter stdscr 2 3 3 28 32767 offset=32767 --
  check zdraw snapshot stdscr after
  [[ $zdraw_ui_gutter[first] == 1 && $zdraw_ui_gutter[offset] == 0 &&
     $after[3,3,text] == N && $after[4,3,text] == ' ' ]] || fail 'empty clears stale rows'
} always {
  zdraw end
}
print -r -- 'CHANGE GUTTER PASS'
