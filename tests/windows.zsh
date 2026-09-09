#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A expected actual cell
typeset -a before after names arguments
same() {
  local key
  (( ${#expected} == ${#actual} )) || fail 'snapshot shape'
  for key in "${(@k)expected}"; do
    [[ $expected[$key] == "$actual[$key]" ]] || fail "snapshot mismatch: $key ($expected[$key] != $actual[$key])"
  done
}
# An independent cell oracle for ASCII resizing: background plus retained
# overlap. The cursor is clamped independently from the implementation.
expect_size() {
  local -i rows=$1 cols=$2 y x keep_rows keep_cols
  local -a geometry
  check zdraw position sample geometry
  y=$(( geometry[1] < rows ? geometry[1] : rows - 1 ))
  x=$(( geometry[2] < cols ? geometry[2] : cols - 1 ))
  keep_rows=$(( geometry[5] < rows ? geometry[5] : rows ))
  keep_cols=$(( geometry[6] < cols ? geometry[6] : cols ))
  check zdraw addwin reference "$rows" "$cols" 0 0
  check zdraw bg reference '@#' reverse
  check zdraw copy sample 0 0 reference 0 0 "$keep_rows" "$keep_cols"
  check zdraw move reference "$y" "$x"
  check zdraw snapshot reference expected
  check zdraw delwin reference
}
reject zdraw movewin stdscr 0 0
reject zdraw resizewin stdscr 1 1
check zdraw init
{
  check zdraw addwin sample 4 10 1 1
  check zdraw bg sample '@#' reverse
  check zdraw attr sample underline green/black
  check zdraw spans sample 0 0 bold,red/black ABCDEFGHIJ
  check zdraw spans sample 1 0 blue/black 0123456789
  check zdraw move sample 3 8
  check zdraw timeout sample 0
  check zdraw snapshot sample expected
  check zdraw position sample before
  names=("${zdraw_windows[@]}")
  if [[ $mode == unavailable_move ]]; then
    (( ! ${zdraw_features[(Ie)window_movement]} && ! ${zdraw_features[(Ie)window_resize]} )) || fail 'unsupported movement advertised'
    zdraw movewin sample 2 3
    (( $? == 2 )) || fail 'unsupported movement status'
    zdraw resizewin sample 2 3
    (( $? == 2 )) || fail 'unsupported resize status'
  elif [[ $mode == unavailable_resize || $mode == unavailable_attrs ]]; then
    (( ! ${zdraw_features[(Ie)window_resize]} )) || fail 'unsupported resize advertised'
    zdraw resizewin sample 2 3
    (( $? == 2 )) || fail 'unsupported resize status'
    check zdraw movewin sample 2 3
  elif [[ $mode == *_failure || $mode == copy_limit ]]; then
    reject zdraw resizewin sample 2 4 4 6
    check zdraw snapshot sample actual
    same
    check zdraw position sample after
    [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'failed resize changed geometry'
    [[ "${(j: :)names}" == "${(j: :)zdraw_windows}" ]] || fail 'failed resize changed registry'
    if [[ $mode == copy_limit ]]; then
      reject zdraw resizewin sample 3 3
      reject zdraw resizewin sample 1 1
      check zdraw addwin tiny 1 4 0 0
      check zdraw resizewin tiny 1 8
      check zdraw delwin tiny
    fi
  else
    (( ${zdraw_features[(Ie)window_movement]} && ${zdraw_features[(Ie)window_resize]} )) || fail 'features missing'
    check zdraw movewin sample 4 6
    check zdraw snapshot sample actual
    same
    check zdraw position sample after
    [[ "${(j: :)after}" == '3 8 4 6 4 10' ]] || fail 'window origin or cursor'
    typeset bad slot
    for bad in '' -1 +1 1x 9999999999999999 '$((1))' 'evil=1'; do
      reject zdraw movewin sample "$bad" 0
      reject zdraw movewin sample 0 "$bad"
      for slot in 2 3 4 5; do
        arguments=(sample 2 3 0 0)
        arguments[$slot]=$bad
        reject zdraw resizewin "${arguments[@]}"
      done
    done
    (( ! ${+evil} )) || fail 'coordinates evaluated'
    reject zdraw movewin sample 21 0
    reject zdraw movewin sample 0 71
    reject zdraw movewin missing 0 0
    reject zdraw movewin sample 0
    reject zdraw movewin sample 0 0 extra
    reject zdraw resizewin sample 0 1
    reject zdraw resizewin sample 1 0
    reject zdraw resizewin sample 21 10
    reject zdraw resizewin sample 4 75
    reject zdraw resizewin sample 1 1 24 0
    reject zdraw resizewin sample 1 1 0 80
    reject zdraw resizewin sample 32768 1
    reject zdraw resizewin missing 1 1
    reject zdraw resizewin sample 1
    reject zdraw resizewin sample 1 1 0
    reject zdraw resizewin sample 1 1 0 0 extra
    reject zdraw movewin stdscr 0 0
    reject zdraw resizewin stdscr 1 1
    check zdraw addpad canvas 2 3
    reject zdraw movewin canvas 0 0
    reject zdraw resizewin canvas 1 1
    check zdraw delwin canvas
    check zdraw addwin child 1 2 5 7 sample
    reject zdraw movewin child 0 0
    reject zdraw resizewin child 1 1
    reject zdraw movewin sample 0 0
    reject zdraw resizewin sample 1 1
    check zdraw delwin child
    check zdraw snapshot sample actual
    same
    check zdraw position sample before
    [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'invalid geometry changed window'
    expect_size 6 12
    check zdraw resizewin sample 6 12
    check zdraw snapshot sample actual
    same
    [[ $actual[5,11,text] == '#' && $actual[5,11,attributes] == reverse ]] || fail 'expanded background'
    expect_size 2 4
    check zdraw resizewin sample 2 4 7 9
    check zdraw snapshot sample actual
    same
    check zdraw position sample after
    [[ "${(j: :)after}" == '1 3 7 9 2 4' ]] || fail 'shrink clamp and reposition'
    expect_size 4 10
    check zdraw resizewin sample 4 10 1 1
    check zdraw snapshot sample actual
    same
    [[ $actual[0,4,text] == '#' && $actual[2,0,text] == '#' ]] || fail 'discarded cells reappeared'
    # The actual curses timeout must survive replacement, not only bookkeeping.
    zdraw input sample
    (( $? == 1 )) || fail 'resized window timeout'
    check zdraw scroll sample on
    check zdraw resizewin sample 3 5
    check zdraw move sample 2 0
    check zdraw string sample 12345
    check zdraw snapshot sample actual
    [[ $actual[1,0,text] == 1 && $actual[2,0,text] == '#' ]] || fail 'scroll mode lost'
    check zdraw scroll sample off
    if [[ $mode == wide ]]; then
      check zdraw resizewin sample 3 8
      check zdraw spans sample 0 0 '' $'e\u0301界Z'
      check zdraw resizewin sample 4 12
      check zdraw move sample 0 0
      check zdraw cellinfo sample cell
      [[ $cell[text] == $'e\u0301' ]] || fail 'combining mark lost'
      check zdraw move sample 0 2
      check zdraw cellinfo sample cell
      [[ $cell[text] == 界 ]] || fail 'wide occupied column lost'
      # ncurses repairs a clipped wide base with the background at the new edge.
      if [[ ${ZDRAW_TEST_NATIVE_EDGES:-0} == 1 ]]; then
        check zdraw resizewin sample 3 2
        check zdraw move sample 0 1
        check zdraw cellinfo sample cell
        [[ $cell[text] == '#' ]] || fail 'native clipped-wide background'
      fi
    fi
    if (( ${zdraw_features[(Ie)resize]} )); then
      check zdraw resizewin sample 3 5 20 70
      check zdraw resize 10 30 nosave
      check zdraw resizewin sample 3 5 1 2
      check zdraw position sample after
      [[ $after[3] == 1 && $after[4] == 2 && $after[5] == 3 && $after[6] == 5 ]] || fail 'terminal-shrink recovery'
      check zdraw resize 24 80 nosave
    fi
  fi
  # A space must still use the original current style and background.
  check zdraw move sample 0 0
  check zdraw string sample ' '
  check zdraw move sample 0 0
  check zdraw cellinfo sample cell
  [[ $cell[text] == '#' && $cell[color] == green/black &&
     $cell[attributes] == 'reverse underline' ]] || fail 'live style lost'
  check zdraw delwin sample
} always {
  zdraw end
}
check zdraw init
if (( ${zdraw_features[(Ie)window_resize]} )) && [[ $mode != *_failure ]]; then
  check zdraw addwin sample 1 1 0 0
  check zdraw resizewin sample 1 2
fi
check zmodload -u zdraw
check zmodload zdraw
print -r -- 'WINDOWS PASS'
