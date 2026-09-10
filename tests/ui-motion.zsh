#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
zmodload zdraw || exit 1
source "${0:A:h:h}/lib/zdraw-motion.zsh" || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A zdraw_ui_theme zdraw_ui_motion pixels before after colors resources
check zdraw init
{
  check zdraw addwin sample 3 12 1 1
  check zdraw addpad large 65 65
  check zdraw-motion-init settle on
  reject zdraw-settle large 0 0 65 65 normal
  check zdraw delwin large
  for profile in 256 mono; do
    check zdraw-ui-theme dark "$profile"
    check zdraw-motion-init activity on
    typeset -a expected=('|' '/' '-' '\')
    for glyph in "${expected[@]}"; do
      check zdraw-activity sample 0 0 normal
      check zdraw snapshot sample pixels
      [[ $pixels[0,0,text] == "$glyph" ]] || fail 'activity glyph'
      check zdraw-motion-action advance
    done
    for mode in reduced off; do
      check zdraw-motion-action "$mode"
      check zdraw-activity sample 0 0 normal
      check zdraw snapshot sample pixels
      [[ $pixels[0,0,text] == '*' ]] || fail 'static glyph'
    done
    check zdraw-motion-action pause
    check zdraw-activity sample 0 0 normal
    check zdraw snapshot sample pixels
    [[ $pixels[0,0,text] == '=' ]] || fail 'paused glyph'
    check zdraw-motion-action cancel
    check zdraw-activity sample 0 0 normal
    check zdraw snapshot sample pixels
    [[ $pixels[0,0,text] == x ]] || fail 'cancelled glyph'
    check zdraw-motion-action finish
    check zdraw-activity sample 0 0 normal
    check zdraw snapshot sample pixels
    [[ $pixels[0,0,text] == '+' ]] || fail 'finished glyph'
    check zdraw-motion-init activity on
    check zdraw-activity sample 0 0 normal glyphs=dots
    check zdraw snapshot sample pixels
    [[ $pixels[0,0,text] == ⠋ ]] || fail 'dot glyph'
    reject zdraw-activity sample 0 0 normal glyphs=bogus
    reject zdraw-activity sample 0 0 normal inactive:fg=bogus
    check zdraw spans sample 1 0 '' 'Keep é界'
    check zdraw attr sample reverse
    check zdraw move sample 2 8
    check zdraw snapshot sample before
    check zdraw-motion-init settle on
    for attrs in bold underline ''; do
      check zdraw-settle sample 1 0 1 10 focus fg=text bg=surface focus:fg=accent
      check zdraw snapshot sample after
      [[ $after[1,0,attributes] == "$attrs" ]] || fail 'settle attributes'
      for (( c=0; c<12; c++ )); do
        [[ $before[1,$c,text] == "$after[1,$c,text]" ]] || fail 'settle lost content'
      done
      [[ $after[cursor_row] == 2 && $after[cursor_column] == 8 ]] || fail 'cursor moved'
      check zdraw-motion-action advance
    done
    check zdraw colorinfo colors
    typeset pairs=$colors[pairs_used]
    repeat 100; do
      check zdraw-motion-action restart
      repeat 3; do
        check zdraw-settle sample 1 0 1 10 focus fg=text bg=surface focus:fg=accent
        check zdraw-motion-action advance
      done
    done
    check zdraw colorinfo colors
    [[ $colors[pairs_used] == "$pairs" ]] || fail 'frame color allocation grew'
    check zdraw-motion-action restart
    check zdraw-motion-action cancel
    check zdraw-settle sample 1 0 1 10 normal
    check zdraw snapshot sample pixels
    [[ $pixels[1,0,attributes] == '' ]] || fail 'cancel did not restore base'
    check zdraw-motion-action restart
    check zdraw-motion-action off
    check zdraw-settle sample 1 0 1 10 normal
    check zdraw snapshot sample before
    reject zdraw-settle sample 1 9 1 10 normal
    reject zdraw-settle sample 1 0 1 10 normal border=ascii
    check zdraw snapshot sample after
    for key in "${(@k)before}"; do [[ $before[$key] == "$after[$key]" ]] || fail 'invalid render changed cells'; done
  done
  check zdraw resourceinfo resources
  [[ $resources[prepared_rows] == 0 ]] || fail 'retained native resources'
} always {
  zdraw end
}
print -r -- 'UI MOTION PASS'
