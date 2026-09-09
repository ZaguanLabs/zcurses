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
cell() {
  check zdraw move sample "$1" "$2"
  check zdraw querychar sample reply
  [[ $reply[1] == "$3" ]] || fail "cell $1,$2: ${(V)reply[1]} != ${(V)3}"
}
check zdraw init
{
  check zdraw addwin sample 4 12 1 1
  if [[ $mode == unavailable ]]; then
    (( ! ${zdraw_features[(Ie)styled_spans]} )) || fail 'unsupported feature advertised'
    zdraw spans sample 0 0 '' text
    (( $? == 2 )) || fail 'unsupported status'
  elif [[ $mode == write_failure ]]; then
    check zdraw bg sample '@#' reverse
    check zdraw attr sample underline red/black
    check zdraw move sample 2 3
    check zdraw position sample before
    reject zdraw spans sample 0 0 bold,blue/black Q
    check zdraw position sample after
    [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'failed write moved cursor'
    check zdraw string sample ' '
    cell 2 3 '#'
    [[ $reply[2] == red/black && ${reply[(Ie)underline]} -gt 0 &&
       ${reply[(Ie)reverse]} -gt 0 ]] || fail 'failed write changed window state'
  elif [[ $mode == allocation_failure ]]; then
    reject zdraw spans sample 0 0 red/black A blue/black B
    cell 0 0 ' '; cell 0 1 ' '
    typeset -A info
    check zdraw colorinfo info
    (( info[pairs_used] == 1 )) || fail 'successful allocation was lost'
    check zdraw spans sample 0 0 red/black C
    cell 0 0 C
  else
    (( ${zdraw_features[(Ie)styled_spans]} )) || fail 'missing feature'
    check zdraw attr sample underline
    check zdraw move sample 2 5
    check zdraw position sample before
    check zdraw spans sample 0 0 bold ab '' ' ' reverse cd
    check zdraw position sample after
    [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'cursor moved'
    cell 0 0 a
    (( ${reply[(Ie)bold]} && ! ${reply[(Ie)underline]} )) || fail "complete bold style: ${(j: :)reply}"
    cell 0 2 ' '
    (( ${#reply} == 2 )) || fail 'empty style inherited attributes'
    cell 0 3 c
    (( ${reply[(Ie)reverse]} && ! ${reply[(Ie)bold]} )) || fail 'style leaked between spans'
    check zdraw move sample 1 0
    check zdraw string sample X
    cell 1 0 X
    (( ${reply[(Ie)underline]} && ! ${reply[(Ie)reverse]} )) || fail 'window style changed'

    # Exact right margin, including the bottom right with scrolling enabled.
    check zdraw scroll sample on
    check zdraw spans sample 3 0 '' 123456789012
    cell 0 0 a; cell 3 11 2
    check zdraw spans sample 0 0 bold '' '' ''
    cell 0 0 a
    typeset -A info
    check zdraw colorinfo info
    typeset -i used=$info[pairs_used]
    typeset bad
    for bad in bogus 'bold,' ',bold' 'bold,,dim' '+bold' '-bold' 'red/black,blue/black' '999999999999/0' '1x/0'; do
      reject zdraw spans sample 0 0 red/black Q "$bad" Z
      cell 0 0 a
    done
    for bad in $'\n' $'\t' $'\e' $'\x7f' $'\0' '1234567890123'; do
      reject zdraw spans sample 0 0 red/black Q '' "$bad"
      cell 0 0 a
    done
    for bad in -1 1x 999999999999999999999 '$((1))' ''; do
      reject zdraw spans sample "$bad" 0 '' Q
      reject zdraw spans sample 0 "$bad" '' Q
    done
    reject zdraw spans sample 4 0 '' Q
    reject zdraw spans sample 0 12 '' Q
    reject zdraw spans sample 0 0 '' Q bold
    reject zdraw spans missing 0 0 '' Q
    check zdraw colorinfo info
    (( info[pairs_used] == used )) || fail 'invalid input allocated colors'

    if [[ $mode == wide ]]; then
      (( ${zdraw_features[(Ie)wide_spans]} )) || fail 'missing wide feature'
      check zdraw spans sample 2 0 bold $'e\u0301' '' '界' reverse Z
      cell 2 0 e; cell 2 1 界; cell 2 3 Z
      check zdraw spans sample 3 10 '' 界
      cell 3 10 界
      for bad in $'\u0301' $'\xff' $'a\u0301\u0301\u0301\u0301\u0301\u0301\u0301\u0301\u0301'; do
        reject zdraw spans sample 0 0 '' Q bold "$bad"
        cell 0 0 a
      done
      reject zdraw spans sample 0 11 '' 界
      unsetopt multibyte
      reject zdraw spans sample 0 0 '' é
      check zdraw spans sample 2 5 '' ascii
      setopt multibyte
    elif [[ $mode == narrow ]]; then
      (( ! ${zdraw_features[(Ie)wide_spans]} )) || fail 'unexpected wide feature'
      zdraw spans sample 0 0 '' é 2>/dev/null
      (( $? == 2 )) || fail 'narrow Unicode status'
      cell 0 0 a
    fi
    if [[ $mode != monochrome ]]; then
      check zdraw spans sample 1 0 bold,red/black RED blue/black BLUE
      cell 1 0 R
      [[ $reply[2] == red/black && ${reply[(Ie)bold]} -gt 0 ]] || fail 'colored bold span'
      cell 1 3 B
      [[ $reply[2] == blue/black && ${#reply} == 2 ]] || fail 'colored plain span'
      check zdraw spans sample 1 8 '' P
      cell 1 8 P
      [[ $reply[2] == default/default ]] || fail 'pair zero style'
    fi
    if [[ $mode != monochrome ]]; then
      # Compare every cell of a batch with equivalent legacy drawing.
      check zdraw addwin reference 4 12 6 1
      check zdraw attr reference bold red/black
      check zdraw string reference abc
      check zdraw attr reference -bold blue/black
      check zdraw string reference ' DEF'
      check zdraw spans sample 2 0 bold,red/black abc blue/black ' DEF'
      typeset -a expected
      typeset -i col
      for (( col=0; col<7; col++ )); do
        check zdraw move reference 0 "$col"
        check zdraw querychar reference expected
        check zdraw move sample 2 "$col"
        check zdraw querychar sample reply
        [[ "${(j: :)expected}" == "${(j: :)reply}" ]] || fail "legacy mismatch at $col"
      done
      check zdraw delwin reference
    fi
    if [[ $mode == wide || $mode == narrow ]]; then
      # Exercise pair IDs beyond the packed eight-bit range, including the
      # saved window style. No old cell may acquire a recycled color pair.
      typeset -i i
      typeset saved_pair
      for (( i=0; i<270; i++ )); do
        saved_pair=$((i%16))/$((i/16))
        check zdraw attr sample "$saved_pair"
      done
      check zdraw colorinfo info
      if [[ $mode == wide ]]; then
        (( info[spans_pair_limit] == info[pair_limit] )) || fail 'wide pair limit'
        check zdraw spans sample 1 0 bold,white/blue W
        cell 1 0 W
        [[ $reply[2] == white/blue ]] || fail 'wide pair truncated'
        check zdraw move sample 1 1
        check zdraw string sample S
        cell 1 1 S
        [[ $reply[2] == $saved_pair && ${reply[(Ie)underline]} -gt 0 ]] || fail 'saved wide style lost'
      else
        (( info[spans_pair_limit] <= 255 )) || fail 'packed pair limit'
        reject zdraw spans sample 1 0 white/blue Q
        cell 1 0 R
      fi
    fi
    # Array writes must not substitute background glyphs or merge attributes.
    check zdraw bg sample '@#' reverse
    check zdraw spans sample 0 0 '' ' '
    cell 0 0 ' '
    (( ${#reply} == 2 )) || fail 'background attributes inherited'
    check zdraw move sample 0 1
    check zdraw string sample ' '
    cell 0 1 '#'
    (( ${reply[(Ie)reverse]} )) || fail 'background was not restored'
    check zdraw refresh sample
  fi
} always {
  zdraw end
}
print -r -- 'SPANS PASS'
