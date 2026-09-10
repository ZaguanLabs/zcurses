#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
typeset root=${0:A:h:h}
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
alias local='false ALIAS_LEAK'
setopt shwordsplit ksharrays globsubst
source "$root/lib/zdraw-tabs.zsh" || exit 1
source "$root/lib/zdraw-meter.zsh" || exit 1
source "$root/lib/zdraw-badge.zsh" || exit 1
source "$root/lib/zdraw-help.zsh" || exit 1
[[ -o shwordsplit && -o ksharrays && -o globsubst ]] || fail 'loader options'
unsetopt shwordsplit ksharrays globsubst
unalias local
zmodload -e zdraw && fail 'loader loaded native module'
whence -w zdraw-table >/dev/null && fail 'presentation loaded table'
module_path=("$1")
zmodload zdraw || exit 1
typeset -A zdraw_ui_theme zdraw_ui_style=(sentinel unchanged) before after info
typeset -a reply=(sentinel) position
typeset field
same() {
  for field in "${(@k)before}"; do
    [[ $before[$field] == "$after[$field]" ]] || fail "changed snapshot: $field"
  done
}
check zdraw-ui-theme dark 256
check zdraw init
{
  check zdraw addwin sample 12 40 1 1
  check zdraw attr sample underline 2/0
  check zdraw move sample 11 38
  check zdraw-tabs sample 0 0 30 2 focus -- One Two Three
  check zdraw snapshot sample before
  [[ $before[0,9,text] == '>' && $before[0,11,text] == T && $before[0,11,color] == 231/30 ]] || fail 'selected tab'
  check zdraw-tabs sample 0 0 8 3 inactive -- One Two Three
  check zdraw snapshot sample before
  [[ $before[0,1,text] == '>' && $before[0,3,text] == T && $before[0,3,color] == 252/238 ]] || fail 'narrow inactive tab'
  check zdraw-tabs sample 0 39 1 3 focus -- One Two Three
  check zdraw snapshot sample before
  [[ $before[0,39,text] == '>' ]] || fail 'one-column selected tab'
  reject zdraw-tabs sample 0 0 30 0 focus -- One
  reject zdraw-tabs sample 0 0 30 1 focus -- One $'offscreen\e'
  reject zdraw-tabs sample 0 0 30 1 focus inactive:fg=bogus -- One
  check zdraw snapshot sample after
  same
  check zdraw-tabs sample 0 0 30 0 focus --
  check zdraw snapshot sample after
  [[ $after[0,3,text] == ' ' ]] || fail 'empty tabs clear'
  check zdraw-meter sample 1 0 15 50 100 normal
  check zdraw snapshot sample before
  [[ $before[1,4,text] == '#' && $before[1,5,text] == '-' && $before[1,12,text] == 5 && $before[1,14,text] == '%' ]] || fail 'meter fraction and label'
  [[ $before[1,0,color] == 80/236 && $before[1,5,color] == 240/236 ]] || fail 'meter parts'
  check zdraw-meter sample 1 0 15 100 100 normal filled:fg=error label:fg=accent
  check zdraw snapshot sample before
  [[ $before[1,9,text] == '#' && $before[1,11,text] == 1 && $before[1,0,color] == 210/236 ]] || fail 'full meter'
  reject zdraw-meter sample 1 0 15 'evil=1' 100 normal
  reject zdraw-meter sample 1 0 15 101 100 normal
  reject zdraw-meter sample 1 0 15 0 0 normal
  reject zdraw-meter sample 1 0 15 0 100 normal fill-char=界
  reject zdraw-meter sample 1 0 15 0 100 normal filled:fg=bogus
  check zdraw snapshot sample after
  same
  check zdraw-meter sample 1 39 1 0 100 normal
  check zdraw snapshot sample after
  [[ $after[1,39,text] == '-' ]] || fail 'tiny meter omits numeric label'
  check zdraw-meter sample 2 0 10 25 100 normal label=off fill-char='=' empty-char='.'
  check zdraw snapshot sample after
  [[ $after[2,1,text] == '=' && $after[2,2,text] == '.' ]] || fail 'custom meter glyphs'
  check zdraw-badge sample 3 0 10 Ready normal
  check zdraw snapshot sample after
  [[ $after[3,2,text] == R && $after[3,0,color] == 231/30 ]] || fail 'badge alignment'
  check zdraw-help sample 4 0 16 normal -- q quit Space pause
  check zdraw snapshot sample before
  [[ $before[4,0,text] == q && $before[4,0,color] == 80/234 && $before[4,1,color] == 245/234 && $before[4,8,text] == ' ' ]] || fail 'whole help items'
  reject zdraw-help sample 4 0 16 normal -- q quit orphan
  reject zdraw-help sample 4 0 16 normal -- q quit x $'bad\ntext'
  check zdraw snapshot sample after
  same
  check zdraw-help sample 4 0 16 normal --
  check zdraw-ui-theme dark mono
  check zdraw-tabs sample 5 0 30 1 focus -- One Two
  check zdraw-badge sample 6 0 10 Ready normal
  check zdraw snapshot sample after
  [[ $after[5,3,pair] == 0 && $after[5,3,attributes] == 'bold reverse' && $after[6,2,attributes] == 'bold reverse' ]] || fail 'mono attributes'
  setopt shwordsplit ksharrays globsubst
  check zdraw-meter sample 7 0 10 1 3 normal
  [[ -o shwordsplit && -o ksharrays && -o globsubst ]] || fail 'caller options'
  unsetopt shwordsplit ksharrays globsubst
  check zdraw position sample position
  [[ $position[1] == 11 && $position[2] == 38 ]] || fail 'cursor moved'
  check zdraw char sample X
  check zdraw move sample 11 38
  check zdraw cellinfo sample info
  [[ $info[color] == 2/0 && $info[attributes] == underline ]] || fail 'drawing style leaked'
  [[ $reply == sentinel && $zdraw_ui_style[sentinel] == unchanged ]] || fail 'caller output changed'
  check zdraw refresh sample
} always {
  zdraw end
}
print -r -- 'UI PRESENTATION PASS'
