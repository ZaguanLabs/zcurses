emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A before after source_before source_after cell
same() {
  local key
  for key in "${(@k)before}"; do [[ $before[$key] == "$after[$key]" ]] || fail "changed $key"; done
}
check zdraw init
{
  check zdraw addwin source 3 10 0 0
  check zdraw addwin target 3 10 4 0
  check zdraw fill target 0 0 3 10 '' D
  check zdraw spans source 0 0 '' ' A  B     '
  check zdraw spans source 0 2 reverse ' '
  check zdraw spans source 0 6 red/black ' '
  check zdraw spans source 1 0 '' ' C  E     '
  check zdraw move source 2 8
  check zdraw move target 2 7
  check zdraw snapshot source source_before
  check zdraw snapshot target before
  if [[ $mode == unavailable ]]; then
    (( ! ${zdraw_features[(Ie)transparent_copy]} )) || fail 'unavailable feature'
    zdraw overlay source 0 0 target 0 0 3 10
    (( $? == 2 )) || fail 'unavailable status'
  elif [[ $mode == *_failure || $mode == cell_limit ]]; then
    reject zdraw overlay source 0 0 target 0 0 3 10
    check zdraw snapshot target after
    if [[ $mode == write_failure ]]; then
      [[ $after[0,1,text] == A && $after[1,1,text] == D ]] || fail 'partial write boundary'
    else same; fi
  else
    check zdraw overlay source 0 0 target 0 0 3 10
    check zdraw snapshot target after
    [[ $after[0,0,text] == D && $after[0,1,text] == A && $after[0,3,text] == D &&
       $after[0,4,text] == B && $after[2,9,text] == D ]] || fail 'transparent blanks'
    [[ $after[0,2,text] == ' ' && $after[0,2,attributes] == reverse &&
       $after[0,6,text] == ' ' && $after[0,6,color] == red/black ]] || fail 'styled blanks must be opaque'
    [[ $after[cursor_row] == $before[cursor_row] && $after[cursor_column] == $before[cursor_column] ]] || fail 'target cursor'
    check zdraw snapshot source source_after
    for key in "${(@k)source_before}"; do [[ $source_before[$key] == "$source_after[$key]" ]] || fail 'source mutated'; done
    check zdraw copy source 0 0 target 0 0 1 10
    check zdraw snapshot target after
    [[ $after[0,0,text] == ' ' && $after[0,3,text] == ' ' ]] || fail 'opaque copy changed'
    # Snapshot semantics for aliased siblings and overlapping self-copy.
    check zdraw spans source 0 0 '' 'a b c d e '
    check zdraw addwin alias 1 8 0 2 source
    check zdraw overlay source 0 0 alias 0 0 1 8
    check zdraw snapshot source after
    [[ $after[0,0,text] == a && $after[0,2,text] == a && $after[0,4,text] == b &&
       $after[0,6,text] == c && $after[0,8,text] == d ]] || fail 'alias snapshot semantics'
    check zdraw delwin alias
    check zdraw bg source '@#' reverse
    check zdraw clear source
    check zdraw overlay source 0 0 target 0 0 1 10
    check zdraw snapshot target after
    [[ $after[0,0,text] == '#' && $after[0,0,attributes] == reverse ]] || fail 'background character is opaque'
    check zdraw snapshot target before
    for bad in '' -1 +1 1x 9999999999999999 '$((1))'; do
      reject zdraw overlay source "$bad" 0 target 0 0 1 1
      reject zdraw overlay source 0 0 target 0 0 1 "$bad"
    done
    reject zdraw overlay source 0 0 target 0 0 0 1
    reject zdraw overlay source 0 9 target 0 0 1 2
    reject zdraw overlay source 0 0 target 2 9 2 2
    reject zdraw overlay missing 0 0 target 0 0 1 1
    check zdraw snapshot target after
    same
    if [[ $mode == wide ]]; then
      check zdraw spans source 1 0 '' $'e\u0301界Z'
      check zdraw overlay source 1 0 target 1 0 1 4
      check zdraw move target 1 0
      check zdraw cellinfo target cell
      [[ $cell[text] == $'e\u0301' ]] || fail 'combining copy'
      check zdraw move target 1 2
      check zdraw cellinfo target cell
      [[ $cell[text] == 界 ]] || fail 'wide copy'
      # Exercise clipped wide edges; exact repair remains curses-specific.
      check zdraw overlay source 1 2 target 2 1 1 1
    fi
  fi
} always {
  zdraw end
}
print -r -- 'OVERLAY PASS'
