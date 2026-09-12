#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A expected actual cell colors
typeset -a before after
same() {
  local field
  (( ${#expected} == ${#actual} )) || fail 'snapshot shape'
  for field in "${(@k)expected}"; do
    [[ $expected[$field] == "$actual[$field]" ]] || fail "snapshot mismatch: $field (${expected[$field]} != ${actual[$field]})"
  done
}
reject zdraw fill stdscr 0 0 1 1 '' X
check zdraw init
{
  check zdraw addwin sample 4 10 1 1
  if [[ $mode == unavailable ]]; then
    (( ! ${zdraw_features[(Ie)region_fill]} )) || fail 'unsupported feature advertised'
    zdraw fill sample 0 0 1 1 '' X
    (( $? == 2 )) || fail 'unsupported fill status'
  elif [[ $mode == allocation_failure || $mode == write_failure || $mode == move_failure ]]; then
    check zdraw bg sample '@#' reverse
    check zdraw attr sample underline green/black
    check zdraw move sample 3 8
    check zdraw snapshot sample expected
    reject zdraw fill sample 0 0 3 4 red/black X
    check zdraw snapshot sample actual
    if [[ $mode == allocation_failure ]]; then
      same
    else
      [[ $actual[0,0,text] == X && $actual[0,3,text] == X &&
         $actual[1,0,text] == '#' && $actual[2,0,text] == '#' &&
         $actual[cursor_row] == 3 && $actual[cursor_column] == 8 ]] || fail 'partial write failure'
    fi
    check zdraw string sample ' '
    check zdraw move sample 3 8
    check zdraw cellinfo sample cell
    [[ $cell[text] == '#' && $cell[color] == green/black &&
       $cell[attributes] == 'reverse underline' ]] || fail 'failure changed window style'
  else
    (( ${zdraw_features[(Ie)region_fill]} )) || fail 'feature missing'
    check zdraw addwin reference 4 10 6 1
    for window in sample reference; do
      check zdraw bg "$window" '@#' reverse
      check zdraw attr "$window" underline green/black
      for row in 0 1 2 3; do
        check zdraw spans "$window" "$row" 0 '' ..........
      done
      check zdraw move "$window" 3 8
    done
    check zdraw fill sample 1 2 2 3 bold,red/black ' '
    for row in 1 2; do
      check zdraw spans reference "$row" 2 bold,red/black '   '
    done
    check zdraw snapshot reference expected
    check zdraw snapshot sample actual
    same
    [[ $actual[1,2,text] == ' ' && $actual[1,2,attributes] == bold &&
       $actual[1,1,text] == . && $actual[1,5,text] == . && $actual[3,2,text] == . ]] || fail 'fill boundaries or literal space'
    check zdraw string sample ' '
    check zdraw move sample 3 8
    check zdraw cellinfo sample cell
    [[ $cell[text] == '#' && $cell[color] == green/black &&
       $cell[attributes] == 'reverse underline' ]] || fail 'fill changed window style'
    check zdraw snapshot sample expected
    check zdraw colorinfo colors
    typeset -i used=$colors[pairs_used]
    for bad in '' -1 +1 1x 999999999999999999 '$((1))' 'evil=1'; do
      reject zdraw fill sample "$bad" 0 1 1 yellow/black X
      reject zdraw fill sample 0 "$bad" 1 1 yellow/black X
      reject zdraw fill sample 0 0 "$bad" 1 yellow/black X
      reject zdraw fill sample 0 0 1 "$bad" yellow/black X
    done
    reject zdraw fill sample 0 0 0 1 yellow/black X
    reject zdraw fill sample 0 0 1 0 yellow/black X
    reject zdraw fill sample 3 0 2 1 yellow/black X
    reject zdraw fill sample 0 9 1 2 yellow/black X
    reject zdraw fill sample 4 0 1 1 yellow/black X
    reject zdraw fill sample 0 10 1 1 yellow/black X
    reject zdraw fill missing 0 0 1 1 yellow/black X
    reject zdraw fill sample 0 0 1 1 bogus X
    reject zdraw fill sample 0 0 1 1 ''
    reject zdraw fill sample 0 0 1 1 '' X extra
    for bad in '' AB $'\n' $'\t' $'\e' $'\0'; do
      reject zdraw fill sample 0 0 1 1 yellow/black "$bad"
    done
    (( ! ${+evil} )) || fail 'numeric argument evaluated'
    check zdraw snapshot sample actual
    same
    check zdraw colorinfo colors
    (( colors[pairs_used] == used )) || fail 'invalid fill allocated colors'
    # Horizontal, vertical and full-window runs include the bottom-right cell.
    check zdraw fill sample 0 0 4 1 '' V
    check zdraw fill sample 3 0 1 10 '' H
    check zdraw fill sample 3 9 1 1 '' Z
    check zdraw snapshot sample actual
    [[ $actual[0,0,text] == V && $actual[2,0,text] == V &&
       $actual[3,8,text] == H && $actual[3,9,text] == Z ]] || fail 'run boundary'
    check zdraw fill sample 0 0 4 10 '' F
    check zdraw snapshot sample actual
    [[ $actual[0,0,text] == F && $actual[3,9,text] == F ]] || fail 'whole-window fill'
    if [[ $mode == wide ]]; then
      check zdraw fill sample 1 1 2 3 underline $'e\u0301'
      check zdraw snapshot sample actual
      [[ $actual[1,1,text] == $'e\u0301' && $actual[2,3,text] == $'e\u0301' &&
         $actual[2,3,characters] == 2 ]] || fail 'complex tile lost marks'
      for bad in 界 $'\u0301' $'e\u0301e' $'e\u0301\u0301\u0301\u0301\u0301\u0301'; do
        reject zdraw fill sample 0 0 1 1 '' "$bad"
      done
      # Intersecting old wide cells must behave exactly like a span write.
      for column in 1 2; do
        for window in sample reference; do
          check zdraw fill "$window" 0 0 4 10 '' .
          check zdraw spans "$window" 0 0 '' A界Z
          check zdraw move "$window" 3 8
        done
        check zdraw fill sample 0 "$column" 1 1 '' X
        check zdraw spans reference 0 "$column" '' X
        check zdraw snapshot reference expected
        check zdraw snapshot sample actual
        same
      done
    else
      zdraw fill sample 0 0 1 1 '' é 2>/dev/null
      (( $? == 2 )) || fail 'narrow Unicode status'
    fi
  fi
} always {
  zdraw end
}
print -r -- 'FILL PASS'
