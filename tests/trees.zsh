emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A before after cell resources resources_again
typeset -a geometry names
same() {
  local key
  (( ${#before} == ${#after} )) || fail 'snapshot size'
  for key in "${(@k)before}"; do [[ $before[$key] == "$after[$key]" ]] || fail "changed: $key"; done
}
position() {
  local win=$1 expected=$2
  check zdraw position "$win" geometry
  [[ "${(j: :)geometry}" == "$expected" ]] || fail "geometry $win: ${geometry[*]}"
}
check zdraw init
{
  check zdraw addwin root 6 20 1 2
  check zdraw addwin child 3 8 2 4 root
  check zdraw addwin grand 1 3 3 5 child
  check zdraw addwin sibling 1 4 5 3 root
  check zdraw bg root '@.'
  check zdraw fill root 0 0 6 20 '' R
  check zdraw spans child 0 0 bold,red/black CHILD
  check zdraw spans grand 0 0 reverse XYZ
  check zdraw attr child underline green/black
  check zdraw move child 2 7
  check zdraw timeout child 0
  check zdraw snapshot root before
  names=("${zdraw_windows[@]}")
  if [[ $mode == unavailable ]]; then
    (( ! ${zdraw_features[(Ie)window_trees]} )) || fail 'unavailable feature'
    zdraw treewin root 8 24 3 10
    (( $? == 2 )) || fail 'unavailable status'
  elif [[ $mode == *_failure || $mode == cell_limit || $mode == tree_limit ]]; then
    reject zdraw treewin root 8 24 3 10
    check zdraw snapshot root after
    same
    position root '0 0 1 2 6 20'
  else
    if [[ $mode == retire ]]; then
      reject zdraw treewin root 8 24 3 10
      check zdraw resourceinfo resources
      check zdraw resourceinfo resources_again
      (( resources[retired_tree_windows] > 0 )) || fail 'retired handles missing'
      [[ $resources[retired_tree_windows] == $resources_again[retired_tree_windows] ]] || fail 'inspection cleaned up'
    else
      check zdraw treewin root 8 24 3 10
    fi
    position root '0 0 3 10 8 24'
    position child '2 7 4 12 3 8'
    position grand '0 0 5 13 1 3'
    position sibling '0 0 7 11 1 4'
    check zdraw move root 7 23
    check zdraw cellinfo root cell
    [[ $cell[text] == . ]] || fail 'root expansion background'
    check zdraw move grand 0 0
    check zdraw string grand Q
    check zdraw move root 2 3
    check zdraw cellinfo root cell
    [[ $cell[text] == Q ]] || fail 'sharing lost after tree replacement'
    # Shrink descendants before ancestors, retaining shared backing.
    check zdraw treewin child 2 5 4 12
    check zdraw resourceinfo resources
    [[ $resources[retired_tree_windows] == 0 ]] || fail 'retired handles not collected'
    position child '1 4 4 12 2 5'
    position grand '0 1 5 13 1 3'
    zdraw event child cell norefresh
    (( $? == 1 )) || fail 'timeout lost'
    check zdraw move child 0 0
    check zdraw string child K
    check zdraw move child 0 0
    check zdraw cellinfo child cell
    [[ $cell[text] == K && $cell[color] == green/black && $cell[attributes] == underline ]] || fail 'drawing state lost'
    # Moving a shared view selects parent cells rather than carrying its text.
    check zdraw treewin child 2 5 5 16
    check zdraw move child 0 0
    check zdraw cellinfo child cell
    [[ $cell[text] == R ]] || fail 'child view did not select parent cells'
    check zdraw spans grand 0 0 '' abc
    check zdraw move root 3 7
    check zdraw cellinfo root cell
    [[ $cell[text] == a ]] || fail 'grandchild sharing after view move'
    reject zdraw resizewin root 8 24
    reject zdraw movewin child 1 1
    check zdraw snapshot root before
    for bad in '' -1 +1 '1x' '$((1))' 'evil=1' 999999999999999999; do
      reject zdraw treewin root "$bad" 20 0 0
      reject zdraw treewin child 2 5 "$bad" 0
    done
    reject zdraw treewin root 0 5 0 0
    reject zdraw treewin root 4 10 3 10
    reject zdraw treewin child 1 1 4 12
    reject zdraw treewin child 2 5 0 0
    reject zdraw treewin root 8 24 23 70
    reject zdraw treewin stdscr 10 30 0 0
    check zdraw addwin screenchild 1 1 0 0 stdscr
    reject zdraw treewin screenchild 1 1 0 0
    check zdraw delwin screenchild
    check zdraw addpad pad 2 2
    reject zdraw treewin pad 1 1 0 0
    check zdraw delwin pad
    check zdraw snapshot root after
    same
    if [[ $mode == wide ]]; then
      check zdraw spans root 0 0 '' $'e\u0301界Z'
      check zdraw treewin root 9 25 1 1
      check zdraw move root 0 0
      check zdraw cellinfo root cell
      [[ $cell[text] == $'e\u0301' ]] || fail 'combining root data'
      check zdraw move root 0 2
      check zdraw cellinfo root cell
      [[ $cell[text] == 界 ]] || fail 'wide root data'
    fi
    if (( ${zdraw_features[(Ie)resize]} )); then
      check zdraw resize 10 30 nosave
      check zdraw treewin root 8 24 1 1
      check zdraw resize 24 80 nosave
    fi
  fi
  [[ "${(j: :)names}" == "${(j: :)zdraw_windows}" ]] || fail 'handle registry changed'
  reject zdraw delwin root
  check zdraw delwin grand
  check zdraw delwin child
  check zdraw delwin sibling
  check zdraw delwin root
} always {
  zdraw end
}
check zdraw init
check zmodload -u zdraw
print -r -- 'TREES PASS'
