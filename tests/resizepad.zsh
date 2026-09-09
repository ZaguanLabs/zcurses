#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A expected actual cell event=(sentinel yes)
typeset -a before after names
same() {
  local key
  (( ${#expected} == ${#actual} )) || fail 'snapshot shape'
  for key in "${(@k)expected}"; do
    [[ $expected[$key] == "$actual[$key]" ]] || fail "snapshot mismatch: $key"
  done
}
# Build the expected ASCII surface independently from the resize implementation.
expect_size() {
  local -i rows=$1 cols=$2 y x keep_rows keep_cols
  local -a geometry
  check zdraw position sample geometry
  y=$(( geometry[1] < rows ? geometry[1] : rows - 1 ))
  x=$(( geometry[2] < cols ? geometry[2] : cols - 1 ))
  keep_rows=$(( geometry[5] < rows ? geometry[5] : rows ))
  keep_cols=$(( geometry[6] < cols ? geometry[6] : cols ))
  check zdraw addpad reference "$rows" "$cols"
  check zdraw bg reference '@#' reverse
  check zdraw copy sample 0 0 reference 0 0 "$keep_rows" "$keep_cols"
  check zdraw move reference "$y" "$x"
  check zdraw snapshot reference expected
  check zdraw delwin reference
}
reject zdraw resizepad sample 1 1
check zdraw init
{
  if [[ $mode == budgets ]]; then
    check zdraw addpad one 4 4
    check zdraw addpad two 4 4
    # At the full live budget a same-area resize credits the old allocation.
    check zdraw resizepad one 2 8
    reject zdraw resizepad one 5 4
    reject zdraw resizepad one 13 1
    reject zdraw addpad full 1 1
    check zdraw resizepad one 2 4
    check zdraw addpad three 2 4
    reject zdraw resizepad one 4 4
    check zdraw position one after
    [[ $after[5] == 2 && $after[6] == 4 ]] || fail 'quota failure changed dimensions'
    check zdraw delwin three
    check zdraw resizepad one 4 4
    reject zdraw addpad full 1 1
    check zdraw delwin one
    check zdraw addpad replacement 4 4
    check zdraw end
    check zdraw init
    check zdraw addpad one 4 4
    check zdraw addpad two 4 4
    check zdraw resizepad one 2 4
    check zmodload -u zdraw
    check zmodload zdraw
    check zdraw init
    check zdraw addpad one 4 4
    check zdraw addpad two 4 4
  else
    check zdraw addpad sample 4 10
    check zdraw bg sample '@#' reverse
    check zdraw attr sample underline green/black
    check zdraw spans sample 0 0 bold,red/black ABCDEFGHIJ
    check zdraw spans sample 1 0 blue/black 0123456789
    check zdraw move sample 3 8
    check zdraw snapshot sample expected
    check zdraw position sample before
    names=("${zdraw_windows[@]}")
    if [[ $mode == unavailable* ]]; then
      (( ! ${zdraw_features[(Ie)pad_resize]} )) || fail 'unsupported resize advertised'
      zdraw resizepad sample 2 4
      (( $? == 2 )) || fail 'unsupported resize status'
    elif [[ $mode == *_failure ]]; then
      reject zdraw resizepad sample 2 4
      # A failed shrink must retain its original 40 cells of live accounting.
      check zdraw addpad filler 4 10
      reject zdraw addpad overflow 1 1
      check zdraw delwin filler
    else
      (( ${zdraw_features[(Ie)pad_resize]} )) || fail 'missing feature'
      typeset bad
      for bad in '' 0 -1 +1 1x 9999999999999999 '$((1))' 'evil=1'; do
        reject zdraw resizepad sample "$bad" 1
        reject zdraw resizepad sample 1 "$bad"
      done
      (( ! ${+evil} )) || fail 'dimensions evaluated'
      reject zdraw resizepad sample 32768 1
      reject zdraw resizepad sample 1024 1024
      reject zdraw resizepad missing 1 1
      reject zdraw resizepad sample 1
      reject zdraw resizepad sample 1 1 extra
      reject zdraw resizepad stdscr 1 1
      check zdraw addwin ordinary 2 3 0 0
      reject zdraw resizepad ordinary 1 1
      check zdraw delwin ordinary
    fi
    check zdraw snapshot sample actual
    same
    check zdraw position sample after
    [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'failed resize changed geometry'
    [[ "${(j: :)names}" == "${(j: :)zdraw_windows}" ]] || fail 'failed resize changed registry'
    if [[ $mode == wide || $mode == narrow ]]; then
      expect_size 6 12
      check zdraw resizepad sample 6 12
      check zdraw snapshot sample actual
      same
      [[ $actual[5,11,text] == '#' && $actual[5,11,attributes] == reverse ]] || fail 'expanded background'
      expect_size 2 4
      check zdraw resizepad sample 2 4
      check zdraw snapshot sample actual
      same
      check zdraw position sample after
      [[ "${(j: :)after}" == '1 3 -1 -1 2 4' ]] || fail 'shrink clamp or pad identity'
      expect_size 4 10
      check zdraw resizepad sample 4 10
      check zdraw snapshot sample actual
      same
      [[ $actual[0,4,text] == '#' && $actual[2,0,text] == '#' ]] || fail 'discarded cells reappeared'
      check zdraw scroll sample on
      check zdraw resizepad sample 3 5
      check zdraw move sample 2 0
      check zdraw string sample 12345
      check zdraw snapshot sample actual
      [[ $actual[1,0,text] == 1 && $actual[2,0,text] == '#' ]] || fail 'scroll mode lost'
      check zdraw scroll sample off
      if [[ $mode == wide ]]; then
        check zdraw resizepad sample 3 8
        check zdraw spans sample 0 0 '' $'e\u0301界Z'
        check zdraw resizepad sample 4 12
        check zdraw move sample 0 0
        check zdraw cellinfo sample cell
        [[ $cell[text] == $'e\u0301' ]] || fail 'combining mark lost'
        check zdraw move sample 0 2
        check zdraw cellinfo sample cell
        [[ $cell[text] == 界 ]] || fail 'wide occupied column lost'
        if [[ ${ZDRAW_TEST_NATIVE_EDGES:-0} == 1 ]]; then
          check zdraw resizepad sample 3 2
          check zdraw move sample 0 1
          check zdraw cellinfo sample cell
          [[ $cell[text] == '#' ]] || fail 'native clipped-wide background'
        fi
      fi
      # Retained areas larger than both screen and public copy limit can resize.
      check zdraw resizepad sample 300 300
      check zdraw spans sample 299 290 bold LAST
      check zdraw resizepad sample 301 301
      check zdraw move sample 299 290
      check zdraw cellinfo sample cell
      [[ $cell[text] == L ]] || fail 'large retained overlap'
      check zdraw move sample 300 300
      check zdraw cellinfo sample cell
      [[ $cell[text] == '#' ]] || fail 'large growth background'
      check zdraw viewport sample 299 290 0 0 1 10
      reject zdraw viewport sample 300 300 0 0 2 2
      check zdraw present
      reject zdraw event sample event
      reject zdraw timeout sample 0
      reject zdraw refresh sample
      reject zdraw stage sample
      reject zdraw addwin child 1 1 0 0 sample
      [[ $event[sentinel] == yes ]] || fail 'resized pad gained input ownership'
    fi
    check zdraw move sample 0 0
    check zdraw string sample ' '
    check zdraw move sample 0 0
    check zdraw cellinfo sample cell
    [[ $cell[text] == '#' && $cell[color] == green/black &&
       $cell[attributes] == 'reverse underline' ]] || fail 'live style lost'
    check zdraw delwin sample
  fi
} always {
  zdraw end
}
(( ${#zdraw_windows} == 0 )) || fail 'end retained pads'
print -r -- 'RESIZEPAD PASS'
