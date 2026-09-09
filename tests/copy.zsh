#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A source expected actual saved colors cell
typeset -a fields=(text attributes attribute_bits color color_source encoding pair characters)
same() {
  local field
  (( ${#expected} == ${#actual} )) || fail 'snapshot shape'
  for field in "${(@k)expected}"; do
    [[ $expected[$field] == "$actual[$field]" ]] || fail "snapshot mismatch: $field ($expected[$field] != $actual[$field])"
  done
}
# Update the expected destination using pre-copy source values. Coordinate
# fields describe readback locations, not properties carried by the copy.
expect_copy() {
  local -i sr=$1 sc=$2 dr=$3 dc=$4 height=$5 width=$6 y x
  local field from to
  for (( y=0; y<height; y++ )); do
    for (( x=0; x<width; x++ )); do
      for field in "${fields[@]}"; do
        from="$((sr+y)),$((sc+x)),$field"
        to="$((dr+y)),$((dc+x)),$field"
        expected[$to]=$source[$from]
      done
    done
  done
}
seed() {
  local window=$1
  check zdraw fill "$window" 0 0 4 10 '' .
  check zdraw spans "$window" 0 0 bold,red/black '0123456789'
  check zdraw spans "$window" 1 0 underline,blue/black 'abcdefghij'
  check zdraw spans "$window" 2 0 '' 'K LM NOPQR'
  check zdraw spans "$window" 3 0 reverse 'stuvwxyz!?'
  check zdraw move "$window" 3 8
}
reject zdraw copy stdscr 0 0 stdscr 0 0 1 1
check zdraw init
{
  check zdraw addwin sample 4 10 1 1
  check zdraw addwin target 4 10 6 1
  seed sample
  check zdraw bg target '@#' reverse
  check zdraw attr target underline green/black
  check zdraw move target 3 8
  check zdraw snapshot sample source
  check zdraw snapshot target expected
  if [[ $mode == unavailable* ]]; then
    (( ! ${zdraw_features[(Ie)region_copy]} )) || fail 'unsupported copy advertised'
    zdraw copy sample 0 0 target 0 0 1 1
    (( $? == 2 )) || fail 'unsupported status'
  elif [[ $mode == allocation_failure || $mode == read_failure || $mode == write_failure || $mode == cell_limit ]]; then
    reject zdraw copy sample 0 0 target 0 0 4 10
    if [[ $mode == write_failure ]]; then
      expect_copy 0 0 0 0 1 10
    fi
    check zdraw snapshot target actual
    same
    expected=("${(@kv)source}")
    check zdraw snapshot sample actual
    same
    if [[ $mode == cell_limit ]]; then
      check zdraw copy sample 0 0 target 3 9 1 1
    fi
  else
    (( ${zdraw_features[(Ie)region_copy]} )) || fail 'copy feature missing'
    # Literal spaces and styles replace even a nonblank destination background.
    check zdraw copy sample 1 1 target 1 2 2 4
    expect_copy 1 1 1 2 2 4
    check zdraw snapshot target actual
    same
    [[ $actual[2,2,text] == ' ' && $actual[2,2,attributes] == '' ]] || fail 'opaque space'
    saved=("${(@kv)expected}")
    expected=("${(@kv)source}")
    check zdraw snapshot sample actual
    same
    expected=("${(@kv)saved}")
    check zdraw colorinfo colors
    typeset -i used=$colors[pairs_used]
    typeset bad slot
    typeset -a arguments
    for bad in '' -1 +1 1x 999999999999999999 '$((1))' 'evil=1'; do
      for slot in 2 3 5 6 7 8; do
        arguments=(sample 0 0 target 0 0 1 1)
        arguments[$slot]=$bad
        reject zdraw copy "${arguments[@]}"
      done
    done
    (( ! ${+evil} )) || fail 'coordinate evaluated'
    reject zdraw copy sample 0 0 target 0 0 0 1
    reject zdraw copy sample 0 0 target 0 0 1 0
    reject zdraw copy sample 3 0 target 0 0 2 1
    reject zdraw copy sample 0 9 target 0 0 1 2
    reject zdraw copy sample 0 0 target 3 0 2 1
    reject zdraw copy sample 0 0 target 0 9 1 2
    reject zdraw copy missing 0 0 target 0 0 1 1
    reject zdraw copy sample 0 0 missing 0 0 1 1
    reject zdraw copy sample 0 0 target 0 0 1
    reject zdraw copy sample 0 0 target 0 0 1 1 overlay
    check zdraw snapshot target actual
    same
    # Neither successful nor rejected copies change the current drawing style.
    check zdraw string target ' '
    check zdraw move target 3 8
    check zdraw cellinfo target cell
    [[ $cell[text] == '#' && $cell[color] == green/black &&
       $cell[attributes] == 'reverse underline' ]] || fail 'copy changed destination style'
    # All overlap directions, exact self-copy, and bottom-right/full boundaries.
    typeset rectangle
    for rectangle in '0 0 1 1 3 9' '1 1 0 0 3 9' '0 0 0 1 4 9' \
                     '0 1 0 0 4 9' '0 0 1 0 3 10' '1 0 0 0 3 10' \
                     '0 0 0 0 4 10' '0 0 3 9 1 1'; do
      seed sample
      arguments=(${=rectangle})
      check zdraw snapshot sample source
      expected=("${(@kv)source}")
      expect_copy "${arguments[@]}"
      check zdraw copy sample "$arguments[1]" "$arguments[2]" sample \
                             "$arguments[3]" "$arguments[4]" "$arguments[5]" "$arguments[6]"
      check zdraw snapshot sample actual
      same
    done
    # Different names may alias the same retained storage.
    seed sample
    check zdraw addwin child 3 9 2 2 sample
    check zdraw snapshot sample source
    expected=("${(@kv)source}")
    expect_copy 0 0 1 1 3 9
    check zdraw copy sample 0 0 child 0 0 3 9
    check zdraw snapshot sample actual
    same
    seed sample
    check zdraw snapshot sample source
    expected=("${(@kv)source}")
    expect_copy 1 1 0 0 3 9
    check zdraw copy child 0 0 sample 0 0 3 9
    check zdraw snapshot sample actual
    same
    check zdraw delwin child
    if [[ $mode == wide ]]; then
      seed sample
      check zdraw spans sample 1 1 bold,red/black $'e\u0301界 '
      check zdraw snapshot sample source
      check zdraw snapshot target expected
      expect_copy 1 1 2 3 1 4
      # Stored cells do not need decoding in the caller's current locale.
      typeset previous_locale=$LC_ALL
      LC_ALL=C
      unsetopt multibyte
      check zdraw copy sample 1 1 target 2 3 1 4
      LC_ALL=$previous_locale
      setopt multibyte
      check zdraw snapshot target actual
      same
      [[ $actual[2,3,text] == $'e\u0301' && $actual[2,4,text] == 界 &&
         $actual[2,5,text] == 界 && $actual[2,6,text] == ' ' ]] || fail 'complex cells'
      # ncurses copies occupied columns verbatim at cut wide boundaries. This
      # is readback evidence, not a portable character-repair guarantee.
      if [[ ${ZDRAW_TEST_NATIVE_EDGES:-0} == 1 ]]; then
        check zdraw snapshot target expected
        expect_copy 1 3 0 0 1 1
        check zdraw copy sample 1 3 target 0 0 1 1
        check zdraw snapshot target actual
        same
        for slot in 1 2; do
          check zdraw spans target 0 0 '' A界Z
          check zdraw snapshot target expected
          expect_copy 0 0 0 "$slot" 1 1
          check zdraw copy sample 0 0 target 0 "$slot" 1 1
          check zdraw snapshot target actual
          same
        done
      fi
    fi
    check zdraw colorinfo colors
    (( colors[pairs_used] == used )) || fail 'copy allocated colors'
  fi
  check zdraw delwin target
  check zdraw delwin sample
} always {
  zdraw end
}
check zdraw init
if [[ $mode != unavailable* && $mode != allocation_failure && $mode != read_failure ]]; then
  check zdraw copy stdscr 0 0 stdscr 0 0 1 1
fi
check zdraw end
print -r -- 'COPY PASS'
