#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -a reply before after
typeset -A info text
cell() {
  check zdraw move sample "$1" "$2"
  check zdraw querychar sample reply
  [[ $reply[1] == "$3" ]] || fail "cell $1,$2: ${(j: :)reply}"
}
check zdraw init
{
  check zdraw addwin sample 4 12 1 1
  if [[ $mode == unavailable ]]; then
    (( ! ${zdraw_features[(Ie)clipped_spans]} )) || fail 'unavailable feature'
    zdraw spansclip sample 0 0 2 '' abc
    (( $? == 2 )) || fail 'unsupported status'
  elif [[ $mode == allocation_failure ]]; then
    # The second pair cannot be initialized, but a fully clipped span must
    # not attempt allocation. A later visible failure must leave cells intact.
    check zdraw spansclip sample 0 0 1 red/black A blue/black B
    cell 0 0 A
    reject zdraw spansclip sample 1 0 2 red/black A blue/black B
    cell 1 0 ' '
    check zdraw colorinfo info
    (( info[pairs_used] == 1 )) || fail 'failed allocation changed budget'
  else
    (( ${zdraw_features[(Ie)clipped_spans]} )) || fail 'missing feature'
    check zdraw attr sample underline green/black
    check zdraw move sample 2 3
    check zdraw position sample before
    check zdraw spansclip sample 0 0 5 bold,red/black abc blue/black DEFG cyan/black hidden
    check zdraw position sample after
    [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'cursor moved'
    check zdraw string sample S
    cell 2 3 S
    [[ $reply[2] == green/black && ${reply[(Ie)underline]} -gt 0 ]] || fail 'window style changed'
    cell 0 0 a
    [[ $reply[2] == red/black && ${reply[(Ie)bold]} -gt 0 && ! ${reply[(Ie)underline]} -gt 0 ]] || fail 'first style'
    cell 0 3 D
    [[ $reply[2] == blue/black && ${#reply} == 2 ]] || fail 'second style'
    cell 0 4 E; cell 0 5 ' '
    check zdraw colorinfo info
    (( info[pairs_used] == 3 )) || fail 'clipped-away style allocated a pair'
    # Zero budget and empty spans still validate, but allocate and draw nothing.
    check zdraw spansclip sample 0 0 0 cyan/black ignored
    check zdraw spansclip sample 0 0 3 cyan/black '' '' ''
    cell 0 0 a
    check zdraw colorinfo info
    (( info[pairs_used] == 3 )) || fail 'empty batch allocated a pair'
    # Window width caps even a larger caller budget; bottom-right never scrolls.
    check zdraw scroll sample on
    check zdraw spansclip sample 3 10 100 '' XYZ
    cell 3 10 X; cell 3 11 Y; cell 0 0 a
    reject zdraw spans sample 0 0 '' 1234567890123
    typeset bad
    for bad in $'\t' $'\n' $'\e' $'\0'; do
      reject zdraw spansclip sample 0 0 1 cyan/black Q '' "$bad"
      cell 0 0 a
    done
    reject zdraw spansclip sample 0 0 1 cyan/black Q bogus hidden
    for bad in -1 '' 1x 99999999999999999999 '$((1))'; do
      reject zdraw spansclip sample 0 0 "$bad" '' abc
    done
    reject zdraw spansclip sample 0 0 1 '' x bold
    reject zdraw spansclip sample 4 0 1 '' x
    reject zdraw spansclip sample 0 12 0 '' x
    check zdraw colorinfo info
    (( info[pairs_used] == 3 )) || fail 'invalid batch allocated a pair'
    if [[ $mode == wide ]]; then
      # One budget across styles; keep marks even when their base fills it.
      check zdraw spansclip sample 1 0 2 bold,red/black $'e\u0301' blue/black 界 '' z
      cell 1 0 e; cell 1 1 ' '
      check zdraw refresh sample
      check zdraw spansclip sample 1 0 3 bold,red/black $'e\u0301' blue/black 界 '' z
      cell 1 1 界; cell 1 3 ' '
      check zdraw spansclip sample 1 10 8 '' 界x
      cell 1 10 界
      # Span boundaries do not split a base from its marks or assign a second
      # style inside one curses complex character, even after truncation.
      reject zdraw spansclip sample 0 0 1 '' Q bold $'\u0301'
      reject zdraw spansclip sample 0 0 1 '' Q '' $'a\u0301\u0301\u0301\u0301\u0301\u0301\u0301\u0301\u0301'
      reject zdraw spansclip sample 0 0 0 '' $'a\xff'
      cell 0 0 a
      check zdraw textinfo text $'e\u0301界z' 3
      [[ $text[width] == 3 && $text[text] == $'e\u0301界' ]] || fail 'measurement/drawing disagreement'
    else
      zdraw spansclip sample 0 0 0 '' é 2>/dev/null
      (( $? == 2 )) || fail 'narrow tail status'
      cell 0 0 a
    fi
    check zdraw refresh sample
  fi
} always {
  zdraw end
}
check zdraw textinfo text after 2
[[ $text[text] == af ]] || fail 'headless query after end'
print -r -- 'CLIPPING PASS'
