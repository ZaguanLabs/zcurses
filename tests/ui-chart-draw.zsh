#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
typeset root=${0:A:h:h}
source "$root/lib/zdraw-sparkline.zsh" || exit 1
whence -w zdraw-bars >/dev/null && exit 1
source "$root/lib/zdraw-bars.zsh" || exit 1
module_path=("$1")
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A zdraw_ui_theme zdraw_ui_chart before after info zdraw_ui_style=(sentinel yes)
typeset -a position reply=(sentinel) values
typeset field ramp
typeset -i i
same() {
  for field in "${(@k)before}"; do
    [[ ${after[$field]-} == "$before[$field]" ]] || fail "changed cell $field"
  done
}
check zdraw-ui-theme dark 256
check zdraw init
{
  check zdraw addwin sample 12 40 1 1
  check zdraw attr sample underline 2/0
  check zdraw move sample 11 38
  check zdraw-chart-series fixed 0 7 -- 0 1 2 3 4 5 6 7
  check zdraw-sparkline sample 0 0 8 normal palette=ascii
  if [[ $2 == wide ]]; then
    check zdraw-sparkline sample 1 0 8 normal palette=unicode
  else
    reject zdraw-sparkline sample 1 0 8 normal palette=unicode
    check zdraw-sparkline sample 1 0 8 normal palette=auto
  fi
  check zdraw snapshot sample after
  ramp='.:-=+*#@'
  for (( i=0; i<8; i++ )); do
    [[ $after[0,$i,text] == "$ramp[$((i+1))]" ]] || fail 'ASCII ramp'
  done
  if [[ $2 == wide ]]; then
    [[ $after[1,0,text] == ▁ && $after[1,7,text] == █ ]] || fail 'Unicode ramp'
  else
    [[ $after[1,0,text] == '.' && $after[1,7,text] == '@' ]] || fail 'narrow-build fallback'
  fi
  check zdraw-sparkline sample 0 0 1 normal palette=ascii
  check zdraw snapshot sample after
  [[ $after[0,0,text] == '@' ]] || fail 'newest sample in narrow sparkline'
  check zdraw-chart-series fixed -7 7 -- -20 -7 0 - 7 20
  check zdraw-sparkline sample 2 0 8 normal palette=ascii negative:fg=error missing:fg=muted
  check zdraw snapshot sample after
  [[ $after[2,0,color] == 210/236 && $after[2,0,attributes] == underline && $after[2,1,color] == 210/236 &&
     $after[2,3,text] == '?' && $after[2,3,color] == 245/236 && $after[2,5,attributes] == underline && $after[2,6,text] == ' ' ]] || fail 'signed missing and clipped styles'
  check zdraw-bars sample 3 0 6 15 normal palette=ascii negative-char='<' track-char='.'
  check zdraw snapshot sample after
  [[ $after[3,0,text] == '<' && $after[3,6,text] == '<' && $after[3,7,text] == '|' && $after[3,8,text] == '.' &&
     $after[5,7,text] == '|' && $after[6,7,text] == '?' && $after[7,8,text] == '#' && $after[7,14,text] == '#' ]] || fail 'signed bars and axis'
  [[ $after[3,0,color] == 210/236 && $after[3,0,attributes] == underline ]] || fail 'clipped negative bar style'
  check zdraw-bars sample 3 39 6 1 normal palette=auto
  check zdraw snapshot sample before
  [[ $before[3,39,text] == '|' && $before[3,39,attributes] == underline && $before[6,39,text] == '?' ]] || fail 'one-column bars'
  reject zdraw-sparkline sample 0 0 8 normal missing:fg=bogus
  reject zdraw-sparkline sample 0 0 8 normal negative:px=1
  reject zdraw-sparkline sample 0 0 8 normal ramp=1234
  reject zdraw-sparkline sample 0 0 8 normal missing-char=''
  reject zdraw-bars sample 0 0 6 15 normal fill-char=界
  reject zdraw-bars sample 0 0 6 15 normal track-char=$'\e'
  reject zdraw-bars sample 0 0 6 15 normal palette=unknown
  check zdraw snapshot sample after
  same
  check zdraw-chart-series fixed 0 10 -- -5
  check zdraw-bars sample 10 0 1 8 normal palette=ascii
  check zdraw snapshot sample before
  [[ $before[10,0,text] == '|' && $before[10,0,attributes] == underline && $before[10,1,text] == ' ' ]] || fail 'clipped zero endpoint'
  check zdraw-chart-series fixed 1 10 -- 2 3
  reject zdraw-bars sample 0 0 2 8 normal
  check zdraw snapshot sample after
  same
  # Validate samples omitted by either viewport before painting.
  zdraw_ui_chart[1,value]='evil=1'
  reject zdraw-sparkline sample 0 0 1 normal
  reject zdraw-bars sample 0 0 1 8 normal
  (( ! ${+evil} )) || fail injection
  check zdraw snapshot sample after
  same
  check zdraw-chart-series auto --
  check zdraw-sparkline sample 0 0 8 normal palette=ascii
  check zdraw-bars sample 3 0 6 15 normal palette=ascii
  check zdraw snapshot sample after
  [[ $after[0,0,text] == ' ' && $after[3,7,text] == ' ' ]] || fail 'empty clears'
  # Multiple span chunks must fit exactly and preserve the far edge.
  values=()
  for (( i=1; i<=130; i++ )); do values+=("$((i%2))"); done
  check zdraw addpad long 1 131
  check zdraw-chart-series auto -- "${values[@]}"
  check zdraw-sparkline long 0 0 130 normal palette=ascii ramp=abcdefgh
  check zdraw snapshot long after
  [[ $after[0,0,text] == h && $after[0,129,text] == a && $after[0,130,text] == ' ' ]] || fail 'span chunk edges'
  check zdraw clear sample
  check zdraw move sample 11 38
  () {
    local LC_ALL=C
    check zdraw-chart-series auto -- 0 7
    check zdraw-sparkline sample 0 0 2 normal palette=auto
    check zdraw snapshot sample before
    [[ $before[0,0,text] == '.' && $before[0,1,text] == '@' ]] || fail 'ASCII locale fallback'
    reject zdraw-sparkline sample 0 0 2 normal palette=unicode
    check zdraw snapshot sample after
    same
  }
  check zdraw-ui-theme dark mono
  check zdraw-chart-series fixed 0 5 -- 10 -
  check zdraw-sparkline sample 9 0 2 normal palette=ascii
  check zdraw snapshot sample after
  [[ $after[9,0,pair] == 0 && $after[9,0,attributes] == underline && $after[9,1,text] == '?' ]] || fail 'monochrome distinction'
  check zdraw position sample position
  [[ $position[1] == 11 && $position[2] == 38 ]] || fail cursor
  check zdraw char sample X
  check zdraw move sample 11 38
  check zdraw cellinfo sample info
  [[ $info[color] == 2/0 && $info[attributes] == underline ]] || fail 'style preservation'
  [[ $zdraw_ui_style[sentinel] == yes && $reply == sentinel ]] || fail 'caller outputs'
  check zdraw refresh sample
} always {
  zdraw end
}
print -r -- 'UI CHART DRAW PASS'
