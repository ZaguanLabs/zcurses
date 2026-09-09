#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A expected actual style plain cell colors
same() {
  local field
  (( ${#expected} == ${#actual} )) || fail 'snapshot shape'
  for field in "${(@k)expected}"; do
    [[ $expected[$field] == "$actual[$field]" ]] || fail "snapshot mismatch: $field ($expected[$field] != $actual[$field])"
  done
}
expect_style() {
  local -i row=$1 col=$2 rows=$3 cols=$4 y x
  local field
  for (( y=row; y<row+rows; y++ )); do
    for (( x=col; x<col+cols; x++ )); do
      for field in attributes attribute_bits color color_source pair; do
        expected[$y,$x,$field]=$style[$field]
      done
    done
  done
}
reject zdraw restyle stdscr 0 0 1 1 bold
check zdraw init
{
  check zdraw addwin sample 4 10 1 1
  check zdraw addwin reference 2 10 6 1
  check zdraw bg sample '@#' reverse
  check zdraw attr sample underline green/black
  check zdraw string sample ABCDEFGHI
  check zdraw move sample 1 0
  check zdraw string sample 123456789
  check zdraw move sample 3 8
  check zdraw cellinfo reference plain
  check zdraw attr reference bold red/black
  check zdraw char reference X
  check zdraw move reference 0 0
  check zdraw cellinfo reference style
  check zdraw snapshot sample expected
  if [[ $mode == unavailable ]]; then
    (( ! ${zdraw_features[(Ie)region_restyle]} )) || fail 'unsupported restyle advertised'
    zdraw restyle sample 0 0 1 1 bold
    (( $? == 2 )) || fail 'unsupported status'
  elif [[ $mode == packed_pairs ]]; then
    # Simulate the older ABI guard without relying on a second installed
    # curses library. Numeric spellings allocate distinct cached pairs.
    typeset -i index
    for (( index=0; index<256; index++ )); do
      check zdraw attr reference "$index/black"
    done
    reject zdraw restyle sample 0 0 1 1 yellow/black
    check zdraw snapshot sample actual
    same
    check zdraw colorinfo colors
    (( colors[pairs_used] > 255 )) || fail 'packed-pair fixture did not reach limit'
    # Ordinary pairs still work after rejecting the unrepresentable one.
    check zdraw restyle sample 0 0 1 1 bold,red/black
    expect_style 0 0 1 1
    check zdraw snapshot sample actual
    same
  elif [[ $mode == allocation_failure ]]; then
    reject zdraw restyle sample 0 0 3 4 yellow/black
    check zdraw snapshot sample actual
    same
    check zdraw colorinfo colors
    (( colors[pairs_used] == 2 )) || fail 'failed allocation used pair'
  elif [[ $mode == write_failure || $mode == move_failure ]]; then
    reject zdraw restyle sample 0 0 3 4 bold,red/black
    expect_style 0 0 1 4
    check zdraw snapshot sample actual
    same
  else
    (( ${zdraw_features[(Ie)region_restyle]} )) || fail 'missing feature'
    check zdraw restyle sample 1 2 2 4 bold,red/black
    expect_style 1 2 2 4
    check zdraw snapshot sample actual
    same
    check zdraw colorinfo colors
    typeset -i used=$colors[pairs_used]
    typeset bad slot
    typeset -a arguments
    for bad in '' -1 +1 1x 999999999999999999 '$((1))' 'evil=1'; do
      for slot in 2 3 4 5; do
        arguments=(sample 0 0 1 1 yellow/black)
        arguments[$slot]=$bad
        reject zdraw restyle "${arguments[@]}"
      done
    done
    (( ! ${+evil} )) || fail 'coordinate evaluated'
    reject zdraw restyle sample 0 0 0 1 yellow/black
    reject zdraw restyle sample 0 0 1 0 yellow/black
    reject zdraw restyle sample 3 0 2 1 yellow/black
    reject zdraw restyle sample 0 9 1 2 yellow/black
    reject zdraw restyle sample 4 0 1 1 yellow/black
    reject zdraw restyle sample 0 10 1 1 yellow/black
    reject zdraw restyle missing 0 0 1 1 yellow/black
    reject zdraw restyle sample 0 0 1 1
    reject zdraw restyle sample 0 0 1 1 bold extra
    for bad in bogus +bold -bold 'bold,' ',bold' 'red/black,blue/black' 'yellow/black,bogus'; do
      reject zdraw restyle sample 0 0 1 1 "$bad"
    done
    check zdraw snapshot sample actual
    same
    check zdraw colorinfo colors
    (( colors[pairs_used] == used )) || fail 'invalid restyle allocated colors'
    # Empty style resets both attributes and color to pair zero.
    style=("${(@kv)plain}")
    check zdraw restyle sample 0 0 4 10 ''
    expect_style 0 0 4 10
    check zdraw snapshot sample actual
    same
    # Shared storage and bottom-right cells, with independent live cursors.
    check zdraw addwin child 2 4 3 7 sample
    check zdraw move child 1 2
    check zdraw cellinfo reference style
    check zdraw restyle child 0 0 2 4 bold,red/black
    expect_style 2 6 2 4
    check zdraw snapshot sample actual
    same
    check zdraw position child arguments
    [[ $arguments[1] == 1 && $arguments[2] == 2 ]] || fail 'child cursor'
    check zdraw delwin child
    if [[ $mode == wide ]]; then
      check zdraw move sample 0 1
      check zdraw string sample $'e\u0301界 '
      check zdraw move sample 3 8
      check zdraw snapshot sample expected
      # Restyling uses stored cells, independently of text decoding settings.
      typeset previous_locale=$LC_ALL
      LC_ALL=C
      unsetopt multibyte
      check zdraw restyle sample 0 1 1 4 bold,red/black
      LC_ALL=$previous_locale
      setopt multibyte
      expect_style 0 1 1 4
      check zdraw snapshot sample actual
      same
      [[ $actual[0,1,text] == $'e\u0301' && $actual[0,2,text] == 界 &&
         $actual[0,3,text] == 界 ]] || fail 'restyle lost complex text'
      if [[ ${ZDRAW_TEST_NATIVE_EDGES:-0} == 1 ]]; then
        style=("${(@kv)plain}")
        check zdraw restyle sample 0 3 1 1 ''
        expect_style 0 3 1 1
        check zdraw snapshot sample actual
        same
      fi
    fi
    # Absolute replacement also removes the alternate-character-set marker.
    check zdraw border sample
    check zdraw move sample 3 8
    check zdraw snapshot sample expected
    style=("${(@kv)plain}")
    check zdraw restyle sample 0 0 4 10 ''
    expect_style 0 0 4 10
    check zdraw snapshot sample actual
    same
  fi
  # All paths retain the live window's background and current drawing style.
  check zdraw string sample ' '
  check zdraw move sample 3 8
  check zdraw cellinfo sample cell
  [[ $cell[text] == '#' && $cell[color] == green/black &&
     $cell[attributes] == 'reverse underline' ]] || fail 'restyle changed drawing state'
  check zdraw delwin reference
  check zdraw delwin sample
} always {
  zdraw end
}
check zdraw init
if [[ $mode != unavailable ]]; then
  check zdraw restyle stdscr 0 0 1 1 ''
fi
check zdraw end
print -r -- 'RESTYLE PASS'
