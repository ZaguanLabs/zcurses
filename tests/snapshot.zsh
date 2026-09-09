#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A captured=(sentinel yes) cell another
typeset -Ar frozen=(sentinel yes)
typeset scalar=sentinel field
typeset -a array=(sentinel) before after windows
reject zdraw snapshot stdscr captured
[[ $captured[sentinel] == yes ]] || fail 'preinit assignment'
(( ${zdraw_features[(Ie)window_snapshots]} )) || fail 'feature missing'
check zdraw init
{
  check zdraw addwin sample 2 6 1 1
  check zdraw spans sample 0 0 bold,red/black AB '' CD
  check zdraw move sample 1 4
  check zdraw position sample before
  windows=("${zdraw_windows[@]}")
  if [[ $mode == *_failure || $mode == *_limit ]]; then
    reject zdraw snapshot sample captured
    [[ $captured[sentinel] == yes && ${#captured} == 1 ]] || fail 'partial failure changed target'
    reject zdraw snapshot sample absent
    (( ! ${+absent} )) || fail 'partial failure created target'
  else
    check zdraw snapshot sample captured
    [[ $captured[format] == zdraw-snapshot-1 && $captured[layout] == readback &&
       $captured[rows] == 2 && $captured[columns] == 6 && $captured[cell_count] == 12 &&
       $captured[cursor_row] == 1 && $captured[cursor_column] == 4 &&
       ${#captured} == 129 && ! -v 'captured[sentinel]' ]] || fail 'snapshot metadata'
    [[ $captured[0,0,text] == A && $captured[0,1,text] == B &&
       $captured[0,0,attributes] == bold && $captured[0,0,color] == red/black &&
       $captured[0,2,text] == C && $captured[0,2,attributes] == '' &&
       $captured[1,5,text] == ' ' ]] || fail 'snapshot cell values'
    check zdraw snapshot sample another
    for field in "${(@k)captured}"; do
      [[ $captured[$field] == "$another[$field]" ]] || fail 'nondeterministic capture'
    done
    for target in frozen scalar array parameters 'captured[x]' 'bad name' ''; do
      reject zdraw snapshot sample "$target"
    done
    [[ $scalar == sentinel && $array == sentinel && $frozen[sentinel] == yes ]] || fail 'invalid target changed'
    reject zdraw snapshot missing captured
    reject zdraw snapshot sample
    reject zdraw snapshot sample captured extra
    [[ $captured[0,0,text] == A ]] || fail 'invalid query replaced target'
    check zdraw snapshot sample created
    [[ $created[0,1,text] == B ]] || fail 'absent target not created'
    local_query() {
      local -A captured
      zdraw snapshot sample captured || return
      [[ $captured[0,0,text] == A ]]
    }
    check local_query
  fi
  check zdraw position sample after
  [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'snapshot moved live cursor'
  [[ "${(j: :)windows}" == "${(j: :)zdraw_windows}" ]] || fail 'snapshot registered a window'
  if [[ $mode != *_failure && $mode != *_limit ]]; then
    # Compare every coordinate with the existing current-cell API.
    typeset -i row col
    for (( row=0; row<2; row++ )); do
      for (( col=0; col<6; col++ )); do
        check zdraw move sample "$row" "$col"
        check zdraw cellinfo sample cell
        for field in "${(@k)cell}"; do
          [[ $captured[$row,$col,$field] == "$cell[$field]" ]] || fail "cell mismatch $row,$col,$field"
        done
      done
    done
    if [[ $mode == wide ]]; then
      check zdraw prepare label underline $'e\u0301' reverse 界
      check zdraw draw sample 0 0 label
      check zdraw snapshot sample captured
      [[ $captured[0,0,text] == $'e\u0301' && $captured[0,0,characters] == 2 &&
         $captured[0,1,text] == 界 && $captured[0,2,text] == 界 ]] || fail 'wide snapshot text'
      # A subwindow may begin inside a wide cell; capture its actual readback.
      check zdraw addwin child 1 3 1 3 sample
      check zdraw snapshot child another
      check zdraw move child 0 0
      check zdraw cellinfo child cell
      [[ $another[0,0,text] == "$cell[text]" && $another[columns] == 3 ]] || fail 'subwindow snapshot'
      check zdraw delwin child
      check zdraw move sample 1 0
      conversion_failure() {
        local LC_ALL=C
        local -A captured=(sentinel yes)
        reject zdraw snapshot sample captured
        [[ $captured[sentinel] == yes ]] || fail 'conversion failure assigned output'
      }
      check conversion_failure
    fi
    check zdraw bg sample '@#' reverse
    check zdraw attr sample underline green/black
    check zdraw move sample 1 0
    check zdraw snapshot sample another
    check zdraw string sample ' '
    check zdraw move sample 1 0
    check zdraw cellinfo sample cell
    [[ $cell[text] == '#' && $cell[color] == green/black &&
       $cell[attributes] == 'reverse underline' ]] || fail 'snapshot changed drawing style'
    # Captured data survives subsequent drawing and deletion of the source.
    [[ $another[0,0,text] == "$captured[0,0,text]" ]] || fail 'capture changed text'
    check zdraw clear sample
    check zdraw delwin sample
    [[ $captured[0,0,text] != ' ' ]] || fail 'capture referenced freed cells'
  fi
} always {
  zdraw end
}
if [[ $mode != *_failure && $mode != *_limit ]]; then
  [[ $captured[format] == zdraw-snapshot-1 ]] || fail 'end destroyed capture'
  check zmodload -u zdraw
  [[ $captured[0,0,text] != ' ' ]] || fail 'unload destroyed capture'
fi
print -r -- 'SNAPSHOT PASS'
