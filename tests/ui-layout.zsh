#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
typeset root=${0:A:h:h}
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
expect_status() {
  local expected=$1 actual
  shift
  "$@" 2>/dev/null
  actual=$?
  [[ $actual == $expected ]] || fail "expected status $expected, got $actual: $*"
}
alias local='false ALIAS_LEAK'
setopt shwordsplit ksharrays globsubst
source "$root/lib/zdraw-layout.zsh" || exit 1
[[ -o shwordsplit && -o ksharrays && -o globsubst ]] || fail 'loader options'
unsetopt shwordsplit ksharrays globsubst
unalias local
zmodload -e zdraw && fail 'layout loaded native module'
whence -w zdraw-panel >/dev/null && fail 'layout loaded panel'
typeset -A zdraw_ui_layout previous
typeset -a reply expected specs
rect() {
  expected=("$@")
  local -i i
  [[ ${#reply} == 4 ]] || fail 'rectangle length'
  for (( i=1; i<=4; i++ )); do
    [[ $reply[$i] == "$expected[$i]" ]] || fail "rectangle: $reply; expected $expected"
  done
}
same_layout() {
  local key
  [[ ${#previous} == ${#zdraw_ui_layout} ]] || fail 'layout size changed'
  for key in "${(@k)previous}"; do
    [[ ${zdraw_ui_layout[$key]-} == "$previous[$key]" ]] || fail "changed layout: $key"
  done
}
check zdraw-layout-center 2 5 11 21 6 10
rect 4 10 6 10
check zdraw-layout-center 2 5 11 21 100 100
rect 2 5 11 21
check zdraw-layout-inset 2 5 11 21 1 2 3 4
rect 3 9 7 15
check zdraw-layout-inset 2 5 3 4 10 1 2 9
rect 5 9 0 0
check zdraw-layout-center 2 5 0 0 10 10
rect 2 5 0 0
check zdraw-layout-split 2 5 10 100 columns 2 fixed=36 flex=1
check zdraw-layout-rect 1
rect 2 5 10 36
check zdraw-layout-rect 02
rect 2 43 10 62
check zdraw-layout-split 0 0 24 80 rows 0 fixed=3 flex=1 fixed=2
check zdraw-layout-rect 2
rect 3 0 19 80
check zdraw-layout-rect 3
rect 22 0 2 80
check zdraw-layout-split 0 0 1 12 columns 1 fixed=2 flex=1 flex=2
[[ $zdraw_ui_layout[2,width] == 3 && $zdraw_ui_layout[3,width] == 5 ]] || fail 'weighted rounding'
check zdraw-layout-split 0 0 1 10 columns 1 fixed=2 fixed=3
check zdraw-layout-rect 2
rect 0 3 1 3
check zdraw-layout-split 0 0 0 0 rows 0 fixed=0 flex=1 flex=32767
check zdraw-layout-rect 3
rect 0 0 0 0
previous=("${(@kv)zdraw_ui_layout}")
expect_status 2 zdraw-layout-split 0 0 2 5 columns 1 fixed=5 flex=1
same_layout
expect_status 2 zdraw-layout-split 0 0 0 0 rows 1 flex=1 flex=1
same_layout
typeset bad
for bad in '' 'flex=0' 'flex=-1' 'fixed=32768' 'fixed=1+1' 'fixed=1=2' 'flex=0x10' \
  'flex=evil=1' 'flex=a[$(touch SHOULD_NOT_EXIST)]' 'percent=50' 'fixed=000000'; do
  expect_status 1 zdraw-layout-split 0 0 2 5 columns 1 fixed=5 "$bad"
  same_layout
done
expect_status 1 zdraw-layout-split 0 0 2 5 diagonal 0 flex=1
expect_status 1 zdraw-layout-split 0 0 2 5 rows 'evil=1' flex=1
expect_status 1 zdraw-layout-split 0 0 2 5 rows 0
expect_status 1 zdraw-layout-split 32767 0 1 1 rows 0 flex=1
same_layout
reply=(2 3 4 5)
expect_status 1 zdraw-layout-inset 0 0 2 5 0 0 0 'evil=1'
expect_status 1 zdraw-layout-center 0 0 2 5 1 'evil=1'
expect_status 1 zdraw-layout-rect 'evil=1'
expect_status 1 zdraw-layout-rect 0
expect_status 1 zdraw-layout-rect 4
rect 2 3 4 5
zdraw_ui_layout[1,row]='evil=1'
expect_status 1 zdraw-layout-rect 1
rect 2 3 4 5
(( ! ${+evil} )) || fail 'arithmetic injection'

# Across small viewports, fixed sizes remain exact; flexible tracks consume
# all remaining space, remain in bounds and never overlap across gaps.
typeset -i extent gap fixed i offset size
for (( extent=0; extent<=60; extent++ )); do
  for (( gap=0; gap<=3; gap++ )); do
    fixed=$((extent%7))
    if (( fixed + 2*gap > extent )); then
      expect_status 2 zdraw-layout-split 3 4 7 "$extent" columns "$gap" "fixed=$fixed" flex=3 flex=1
      continue
    fi
    check zdraw-layout-split 3 4 7 "$extent" columns "$gap" "fixed=$fixed" flex=3 flex=1
    [[ $zdraw_ui_layout[1,width] == $fixed ]] || fail 'fixed size changed'
    offset=4
    for (( i=1; i<=3; i++ )); do
      check zdraw-layout-rect "$i"
      (( reply[1] == 3 && reply[2] == offset && reply[3] == 7 && reply[4] >= 0 )) || fail 'track bounds'
      (( offset += reply[4] + gap ))
    done
    (( offset-gap == 4+extent )) || fail 'unallocated flexible space'
  done
done
repeat 32; do specs+=(flex=32767); done
check zdraw-layout-split 0 0 32767 32767 columns 0 "${specs[@]}"
check zdraw-layout-rect 32
rect 0 31744 32767 1023
specs+=(flex=1)
expect_status 1 zdraw-layout-split 0 0 1 100 columns 0 "${specs[@]}"
() {
  local -A zdraw_ui_layout
  local -a reply
  setopt shwordsplit ksharrays globsubst
  check zdraw-layout-split 0 0 20 40 rows 1 flex=1 flex=1
  check zdraw-layout-rect 2
  [[ -o shwordsplit && -o ksharrays && -o globsubst ]] || fail 'function options'
  unsetopt shwordsplit ksharrays globsubst
  [[ $reply[1] == 11 && $reply[3] == 9 ]] || fail 'local outputs'
}
() {
  local -Ar zdraw_ui_layout=(count 1 1,row 0 1,column 0 1,height 2 1,width 3)
  check zdraw-layout-rect 1
  expect_status 1 zdraw-layout-split 0 0 2 5 rows 0 flex=1
}
() {
  local -ar reply=(1 2 3 4)
  expect_status 1 zdraw-layout-center 0 0 2 5 1 1
  expect_status 1 zdraw-layout-inset 0 0 2 5 0 0 0 0
  expect_status 1 zdraw-layout-rect 1
}
print -r -- 'UI LAYOUT PASS'
