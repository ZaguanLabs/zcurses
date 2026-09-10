#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
typeset root=${0:A:h:h}
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
alias local='false ALIAS_LEAK'
setopt shwordsplit ksharrays globsubst
source "$root/lib/zdraw-chart.zsh" || exit 1
[[ -o shwordsplit && -o ksharrays && -o globsubst ]] || fail options
unsetopt shwordsplit ksharrays globsubst
unalias local
zmodload -e zdraw && fail 'loader loaded native module'
whence -w zdraw-sparkline >/dev/null && fail 'data loader loaded drawing'
typeset -A zdraw_ui_chart before
typeset -a reply=(sentinel) samples
typeset bad key
typeset -i i
same() {
  [[ ${#before} == ${#zdraw_ui_chart} ]] || fail 'changed state size'
  for key in "${(@k)before}"; do
    [[ ${zdraw_ui_chart[$key]-} == "$before[$key]" ]] || fail "changed state: $key"
  done
}
check zdraw-chart-series auto -- -10 - 0 10
[[ $zdraw_ui_chart[count] == 4 && $zdraw_ui_chart[low] == -10 && $zdraw_ui_chart[high] == 10 &&
   $zdraw_ui_chart[valid] == 3 && $zdraw_ui_chart[missing] == 1 && $zdraw_ui_chart[latest] == 10 ]] || fail 'series metadata'
check zdraw-chart-project 10
[[ $reply == '0 - 5 10' ]] || fail 'signed projection'
check zdraw-chart-project 0
[[ $reply == '0 - 0 0' ]] || fail 'one-column projection'
check zdraw-chart-series fixed -5 5 -- -10 0 10 -
[[ $zdraw_ui_chart[below] == 1 && $zdraw_ui_chart[above] == 1 && $zdraw_ui_chart[1,value] == -10 && $zdraw_ui_chart[latest] == - ]] || fail 'clipping metadata'
check zdraw-chart-project 10
[[ $reply == '0 5 10 -' ]] || fail clamp
check zdraw-chart-series auto -- 7 7
[[ $zdraw_ui_chart[low] == 0 && $zdraw_ui_chart[high] == 7 ]] || fail 'positive constant scale'
check zdraw-chart-project 7
[[ $reply == '7 7' ]] || fail 'positive constant projection'
check zdraw-chart-series auto -- -7 -7
[[ $zdraw_ui_chart[low] == -7 && $zdraw_ui_chart[high] == 0 ]] || fail 'negative constant scale'
check zdraw-chart-series auto -- 0 0
[[ $zdraw_ui_chart[low] == 0 && $zdraw_ui_chart[high] == 1 ]] || fail 'zero constant scale'
check zdraw-chart-series auto -- - -
[[ $zdraw_ui_chart[data_min] == unknown && $zdraw_ui_chart[missing] == 2 ]] || fail 'all missing'
check zdraw-chart-project 7
[[ $reply == '- -' ]] || fail 'missing projection'
check zdraw-chart-series auto --
check zdraw-chart-project 7
[[ ${#reply} == 0 && $zdraw_ui_chart[latest] == unknown ]] || fail empty
check zdraw-chart-series fixed -32767 32767 -- -32767 0 32767
check zdraw-chart-project 32767
[[ $reply == '0 16383 32767' ]] || fail 'maximum product'
check zdraw-chart-series auto -- 00008 -00002 -0
[[ $zdraw_ui_chart[1,value] == 8 && $zdraw_ui_chart[2,value] == -2 && $zdraw_ui_chart[3,value] == 0 ]] || fail 'decimal canonicalization'
before=("${(@kv)zdraw_ui_chart}")
for bad in '' '+1' '--1' '1.5' '1e2' 'NaN' '32768' '-32768' '123456' ' 1' 'evil=1' 'a[evil=1]' '$((1))' '$(touch SHOULD_NOT_EXIST)'; do
  reject zdraw-chart-series auto -- 1 "$bad"
  same
  reject zdraw-chart-series fixed "$bad" 10 -- 1
  same
done
reject zdraw-chart-series fixed 1 1 -- 1
reject zdraw-chart-series fixed 3 -2 -- 1
reject zdraw-chart-series auto 1
reject zdraw-chart-series unknown -- 1
# Bound the count independently of text size.
samples=()
for (( i=1; i<=4097; i++ )); do samples+=(1); done
reject zdraw-chart-series auto -- "${samples[@]}"
same
reply=(sentinel)
reject zdraw-chart-project 'evil=1'
[[ $reply == sentinel ]] || fail 'projection failure mutated output'
zdraw_ui_chart[1,value]='evil=1'
reject zdraw-chart-project 7
[[ $reply == sentinel ]] || fail 'malformed state changed output'
(( ! ${+evil} )) || fail 'arithmetic injection'
() {
  local -A zdraw_ui_chart
  local -a reply
  check zdraw-chart-series auto -- 5
  check zdraw-chart-project 7
  [[ $reply == 7 ]] || fail 'local outputs'
}
() {
  local -Ar zdraw_ui_chart=(sentinel yes)
  reject zdraw-chart-series auto -- 1
}
() {
  local -A zdraw_ui_chart
  local -ar reply=(sentinel)
  check zdraw-chart-series auto -- 1
  reject zdraw-chart-project 7
}
setopt shwordsplit ksharrays globsubst octalzeroes
check zdraw-chart-series auto -- 00008
[[ -o shwordsplit && -o ksharrays && -o globsubst && -o octalzeroes ]] || fail 'caller options'
unsetopt shwordsplit ksharrays globsubst octalzeroes
print -r -- 'UI CHART PASS'
