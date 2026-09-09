#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A expected actual event=(sentinel yes) cell
typeset -a position before after
same() {
  local key
  (( ${#expected} == ${#actual} )) || fail 'snapshot shape'
  for key in "${(@k)expected}"; do
    [[ $expected[$key] == "$actual[$key]" ]] || fail "snapshot mismatch: $key"
  done
}
reject zdraw addpad canvas 10 10
reject zdraw viewport canvas 0 0 0 0 1 1
reject zdraw stage stdscr
reject zdraw present
check zdraw init
{
  if [[ $mode == unavailable* ]]; then
    (( ! ${zdraw_features[(Ie)offscreen_pads]} )) || fail 'unsupported pads advertised'
    zdraw addpad canvas 1 1
    (( $? == 2 )) || fail 'unsupported creation status'
    zdraw viewport canvas 0 0 0 0 1 1
    (( $? == 2 )) || fail 'unsupported viewport status'
    check zdraw stage stdscr
    check zdraw present
  elif [[ $mode == allocation_failure ]]; then
    reject zdraw addpad canvas 1 1
    (( ${#zdraw_windows} == 1 )) || fail 'failed allocation registered pad'
  elif [[ $mode == budgets || $mode == deletion_failure ]]; then
    reject zdraw addpad oversized 5 4
    reject zdraw addpad overdimension 13 1
    check zdraw addpad one 4 4
    check zdraw addpad two 4 4
    reject zdraw addpad full 1 1
    if [[ $mode == deletion_failure ]]; then
      reject zdraw delwin one
      (( ${zdraw_windows[(Ie)one]} )) || fail 'failed deletion lost ownership'
      reject zdraw addpad stillfull 1 1
    else
      check zdraw delwin one
      check zdraw addpad replacement 4 4
    fi
    check zdraw end
    check zdraw init
    check zdraw addpad one 4 4
    check zdraw addpad two 4 4
    check zmodload -u zdraw
    check zmodload zdraw
    check zdraw init
    check zdraw addpad one 4 4
    check zdraw addpad two 4 4
  else
    (( ${zdraw_features[(Ie)offscreen_pads]} && ${zdraw_features[(Ie)staged_refresh]} )) || fail 'missing features'
    # The pad is wider and taller than the 24x80 screen.
    check zdraw addpad canvas 40 100
    check zdraw position canvas position
    [[ "${(j: :)position}" == '0 0 -1 -1 40 100' ]] || fail 'pad position contract'
    check zdraw fill canvas 0 0 40 100 '' .
    check zdraw prepare title bold,red/black PAD_CONTENT
    check zdraw draw canvas 30 85 title
    check zdraw restyle canvas 30 85 1 11 underline,red/black
    check zdraw copy canvas 30 85 canvas 31 85 1 11
    check zdraw move canvas 30 85
    check zdraw cellinfo canvas cell
    [[ $cell[text] == P && $cell[attributes] == underline ]] || fail 'pad drawing or inspection'
    check zdraw move canvas 39 99
    check zdraw fill canvas 39 99 1 1 '' Z
    check zdraw snapshot canvas expected
    [[ $expected[31,85,text] == P && $expected[39,99,text] == Z ]] || fail 'retained pad cells'
    before=("${zdraw_windows[@]}")
    typeset bad slot
    typeset -a arguments
    for bad in '' 0 -1 +1 1x 9999999999999999 '$((1))' 'evil=1'; do
      reject zdraw addpad bad "$bad" 1
      reject zdraw addpad bad 1 "$bad"
    done
    reject zdraw addpad '' 1 1
    reject zdraw addpad canvas 1 1
    reject zdraw addpad stdscr 1 1
    reject zdraw addpad bad 32768 1
    reject zdraw addpad bad 1024 1024
    reject zdraw addpad bad 1
    reject zdraw addpad bad 1 1 extra
    reject zdraw addwin child 1 1 0 0 canvas
    reject zdraw input canvas
    reject zdraw event canvas event
    reject zdraw event canvas event norefresh
    reject zdraw timeout canvas 0
    reject zdraw refresh canvas
    reject zdraw refresh stdscr canvas
    reject zdraw stage canvas
    reject zdraw stage stdscr canvas
    reject zdraw stage stdscr missing
    reject zdraw stage
    reject zdraw present extra
    [[ $event[sentinel] == yes ]] || fail 'pad input assigned event'
    for bad in '' -1 +1 1x 9999999999999999 '$((1))' 'evil=1'; do
      for slot in 2 3 4 5 6 7; do
        arguments=(canvas 0 0 0 0 1 1)
        arguments[$slot]=$bad
        reject zdraw viewport "${arguments[@]}"
      done
    done
    (( ! ${+evil} )) || fail 'numeric input evaluated'
    reject zdraw viewport canvas 0 0 0 0 0 1
    reject zdraw viewport canvas 0 0 0 0 1 0
    reject zdraw viewport canvas 39 0 0 0 2 1
    reject zdraw viewport canvas 0 99 0 0 1 2
    reject zdraw viewport canvas 0 0 23 0 2 1
    reject zdraw viewport canvas 0 0 0 79 1 2
    reject zdraw viewport stdscr 0 0 0 0 1 1
    reject zdraw viewport missing 0 0 0 0 1 1
    reject zdraw viewport canvas 0 0 0 0 1
    reject zdraw viewport canvas 0 0 0 0 1 1 extra
    after=("${zdraw_windows[@]}")
    [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'invalid operation changed handles'
    if [[ $mode == viewport_failure || $mode == touch_failure ]]; then
      reject zdraw viewport canvas 30 85 2 3 2 12
    elif [[ $mode == stage_failure ]]; then
      reject zdraw stage stdscr
    elif [[ $mode == present_failure ]]; then
      check zdraw viewport canvas 30 85 2 3 2 12
      reject zdraw present
    else
      check zdraw stage stdscr
      check zdraw viewport canvas 30 85 2 3 2 12
      check zdraw viewport canvas 39 99 23 79 1 1
      check zdraw present
    fi
    check zdraw snapshot canvas actual
    same
    if [[ $mode == virtual_screen ]]; then
      # Only this test variant lets snapshot read curses' virtual screen when
      # the target is the dummy window named vscreen.
      check zdraw addwin vscreen 1 1 0 0
      check zdraw addwin overlay 2 12 2 3
      check zdraw fill overlay 0 0 2 12 reverse '#'
      check zdraw stage overlay
      check zdraw snapshot vscreen actual
      [[ $actual[2,3,text] == '#' && $actual[2,3,attributes] == reverse ]] || fail 'overlay staging'
      # Unchanged pad rows must cover the overlay again when restaged.
      check zdraw viewport canvas 30 85 2 3 2 12
      check zdraw snapshot vscreen actual
      [[ $actual[2,3,text] == P && $actual[3,3,text] == P &&
         $actual[2,3,attributes] == underline && $actual[2,3,color] == red/black ]] || fail 'pad restaging'
      # One pad can contribute multiple distinct views in a single frame.
      check zdraw viewport canvas 30 85 5 3 1 12
      check zdraw snapshot vscreen actual
      [[ $actual[2,3,text] == P && $actual[5,3,text] == P ]] || fail 'multiple views'
      # A fully validated stage list cannot partially cover a queued pad.
      reject zdraw stage overlay missing
      check zdraw snapshot vscreen actual
      [[ $actual[2,3,text] == P ]] || fail 'invalid stage list partially staged'
      check zdraw stage stdscr
      check zdraw snapshot vscreen actual
      [[ $actual[2,3,text] == ' ' && $actual[5,3,text] == ' ' ]] || fail 'background restaging'
      check zdraw delwin overlay
      check zdraw delwin vscreen
    fi
    if [[ $mode == wide || $mode == virtual_screen ]]; then
      check zdraw spans canvas 0 0 '' $'e\u0301界'
      check zdraw move canvas 0 0
      check zdraw cellinfo canvas cell
      [[ $cell[text] == $'e\u0301' ]] || fail 'pad combining marks'
      check zdraw viewport canvas 0 0 0 0 1 3
      if [[ $mode == virtual_screen ]]; then
        check zdraw addwin vscreen 1 1 0 0
        check zdraw snapshot vscreen actual
        [[ $actual[0,0,text] == $'e\u0301' && $actual[0,1,text] == 界 &&
           $actual[0,2,text] == 界 ]] || fail 'viewport lost complete wide cells'
        check zdraw delwin vscreen
      fi
    fi
    if (( ${zdraw_features[(Ie)resize]} )); then
      check zdraw resize 12 40 nosave
      check zdraw position canvas position
      [[ $position[5] == 40 && $position[6] == 100 ]] || fail 'resize changed pad extent'
      reject zdraw viewport canvas 0 0 12 0 1 1
      check zdraw resize 24 80 nosave
    fi
    check zdraw delwin canvas
    (( ! ${zdraw_windows[(Ie)canvas]} )) || fail 'deleted pad still registered'
    reject zdraw viewport canvas 0 0 0 0 1 1
  fi
} always {
  zdraw end
}
(( ${#zdraw_windows} == 0 )) || fail 'end retained surfaces'
print -r -- 'PADS PASS'
