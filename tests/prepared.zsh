#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A info colors
typeset -a actual expected before after
reject zdraw prepare early '' hello
check zdraw init
{
  check zdraw addwin sample 4 12 1 1
  check zdraw addwin reference 4 12 6 1
  if [[ $mode == unavailable ]]; then
    (( ! ${zdraw_features[(Ie)prepared_rows]} )) || fail 'feature advertised'
    zdraw prepare absent '' text
    (( $? == 2 )) || fail 'unsupported prepare status'
    zdraw draw sample 0 0 absent
    (( $? == 2 )) || fail 'unsupported draw status'
    zdraw rowinfo absent info
    (( $? == 2 )) || fail 'unsupported query status'
    zdraw unprepare absent
    (( $? == 2 )) || fail 'unsupported release status'
  elif [[ $mode == allocation_failure ]]; then
    reject zdraw prepare failed red/black A blue/black B
    reject zdraw rowinfo failed info
    check zdraw colorinfo colors
    (( colors[pairs_used] == 1 )) || fail 'allocation accounting'
    check zdraw prepare valid red/black C
    check zdraw draw sample 0 0 valid
  elif [[ $mode == limit ]]; then
    typeset -i n=0
    while zdraw prepare "row$n" '' 1234567890 2>/dev/null; do
      (( n++ ))
      (( n < 100 )) || fail 'missing storage bound'
    done
    (( n > 0 )) || fail 'no row fits'
    check zdraw rowinfo row0 info
    (( info[session_bytes] <= info[session_limit] )) || fail 'budget exceeded'
    check zdraw unprepare row0
    check zdraw prepare replacement '' 1234567890
    check zdraw rowinfo replacement info
    (( info[session_bytes] <= info[session_limit] )) || fail 'reclaimed budget exceeded'
  else
    (( ${zdraw_features[(Ie)prepared_rows]} )) || fail 'missing feature'
    typeset -a batch=(bold,red/black ab '' ' ' blue/black CD)
    check zdraw prepare label "${batch[@]}"
    check zdraw rowinfo label info
    (( info[width] == 5 && info[cells] == 5 && info[bytes] > 0 &&
       info[session_bytes] == info[bytes] )) || fail 'row information'
    typeset -i original_bytes=$info[bytes]
    check zdraw prepare blank bold ''
    check zdraw rowinfo blank info
    (( info[width] == 0 && info[cells] == 0 )) || fail 'empty row information'
    check zdraw unprepare blank
    check zdraw rowinfo label info
    (( info[session_bytes] == original_bytes )) || fail 'release accounting'
    [[ $mode == write_failure ]] || check zdraw spans reference 0 0 "${batch[@]}"
    batch[2]=MUTATED
    reject zdraw prepare label '' replacement
    check zdraw bg sample '@#' reverse
    check zdraw attr sample underline green/black
    check zdraw move sample 2 3
    check zdraw position sample before
    if [[ $mode == write_failure ]]; then
      reject zdraw draw sample 0 0 label
      check zdraw rowinfo label info
      [[ $info[draws] == 0 ]] || fail 'failed draw counted'
    else
      check zdraw draw sample 0 0 label
    fi
    check zdraw position sample after
    [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'draw moved cursor'
    check zdraw string sample ' '
    check zdraw move sample 2 3
    check zdraw querychar sample actual
    [[ $actual[1] == '#' && $actual[2] == green/black &&
       ${actual[(Ie)underline]} -gt 0 && ${actual[(Ie)reverse]} -gt 0 ]] || fail 'window state changed'
    if [[ $mode != write_failure ]]; then
      typeset -i col
      for (( col=0; col<5; col++ )); do
        check zdraw move sample 0 "$col"
        check zdraw querychar sample actual
        check zdraw move reference 0 "$col"
        check zdraw querychar reference expected
        [[ "${(j: :)actual}" == "${(j: :)expected}" ]] || fail "cell mismatch: $col"
      done
      reject zdraw draw sample 0 10 label
      check zdraw draw sample 0 10 label 5
      check zdraw move sample 0 11
      check zdraw querychar sample actual
      [[ $actual[1] == b ]] || fail 'right edge clipping'
      check zdraw draw sample 0 0 label 0
      check zdraw move sample 0 0
      check zdraw querychar sample actual
      [[ $actual[1] == a ]] || fail 'zero budget changed cells'
      check zdraw unprepare label
      reject zdraw draw sample 0 0 label
      check zdraw querychar sample actual
      [[ $actual[1] == a ]] || fail 'release changed cells'
      check zdraw prepare label '' reusable
      check zdraw draw reference 1 0 label
    fi
    check zdraw colorinfo colors
    typeset -i used=$colors[pairs_used]
    typeset bad
    for bad in $'\n' $'\t' $'\e' $'\0' $'\xff'; do
      reject zdraw prepare invalid red/black A '' "$bad"
    done
    reject zdraw prepare invalid red/black A bogus Z
    reject zdraw prepare invalid red/black A bold
    reject zdraw prepare 'bad[name]' '' A
    reject zdraw prepare '' '' A
    reject zdraw rowinfo invalid info
    check zdraw colorinfo colors
    (( colors[pairs_used] == used )) || fail 'invalid preparation allocated colors'
    for bad in -1 1x 999999999999999999999 '$((1))' ''; do
      reject zdraw draw sample "$bad" 0 label
      reject zdraw draw sample 0 "$bad" label
      reject zdraw draw sample 0 0 label "$bad"
    done
    reject zdraw draw missing 0 0 label
    reject zdraw draw sample 4 0 label
    reject zdraw draw sample 0 12 label 0
    typeset scalar=sentinel
    typeset -a array=(sentinel)
    typeset -Ar frozen=(sentinel yes)
    reject zdraw rowinfo label scalar
    reject zdraw rowinfo label array
    reject zdraw rowinfo label frozen
    reject zdraw rowinfo label 'info[x]'
    reject zdraw rowinfo label parameters
    [[ $scalar == sentinel && $array == sentinel && $frozen[sentinel] == yes ]] || fail 'invalid target changed'
    check zdraw rowinfo label created
    (( created[width] > 0 )) || fail 'missing target not created'
    local_query() {
      local -A created
      zdraw rowinfo label created || return
      (( created[width] > 0 ))
    }
    check local_query
    unsetopt multibyte
    reject zdraw draw sample 0 0 label
    setopt multibyte
    changed_locale() {
      local LC_ALL=C
      reject zdraw draw sample 0 0 label
    }
    check changed_locale
    if [[ $mode == wide ]]; then
      check zdraw prepare unicode bold $'e\u0301' '' 界 reverse Z
      check zdraw rowinfo unicode info
      (( info[width] == 4 && info[cells] == 3 )) || fail 'wide geometry'
      check zdraw draw sample 3 0 unicode 2
      check zdraw move sample 3 0
      check zdraw querychar sample actual
      [[ $actual[1] == e ]] || fail 'combining base missing'
      check zdraw cellinfo sample info
      [[ $info[text] == $'e\u0301' && $info[characters] == 2 ]] || fail 'prepared combining mark lost'
      check zdraw move sample 3 1
      check zdraw querychar sample actual
      [[ $actual[1] == '#' ]] || fail 'split wide character'
      check zdraw draw reference 3 8 unicode
      # Selecting either column of a wide cell must highlight the whole cell.
      check zdraw textpos info $'e\u0301界Z' column 2
      check zdraw spans sample 1 0 '' "$info[prefix]" reverse "$info[text]" '' "$info[remainder]"
      for col in 1 2; do
        check zdraw move sample 1 "$col"
        check zdraw querychar sample actual
        [[ $actual[1] == 界 && ${actual[(Ie)reverse]} -gt 0 ]] || fail 'wide hit highlight'
      done
      check zdraw move sample 1 3
      check zdraw querychar sample actual
      [[ $actual[1] == Z && ${actual[(Ie)reverse]} == 0 ]] || fail 'hit highlight leaked'
      for bad in $'\u0301' $'a\u0301\u0301\u0301\u0301\u0301\u0301\u0301\u0301'; do
        reject zdraw prepare invalid '' "$bad"
      done
    elif [[ $mode == narrow ]]; then
      zdraw prepare invalid '' é 2>/dev/null
      (( $? == 2 )) || fail 'unsupported Unicode status'
    fi
  fi
} always {
  zdraw end
}
check zdraw init
{
  check zdraw addwin sample 1 12 1 1
  reject zdraw draw sample 0 0 label
  if [[ $mode != unavailable ]]; then
    check zdraw prepare fresh '' x
    check zdraw rowinfo fresh info
    (( info[bytes] == info[session_bytes] )) || fail 'end leaked rows'
    # Unloading an initialized module must release its prepared objects too.
    check zmodload -u zdraw
    check zmodload zdraw
    check zdraw init
    reject zdraw rowinfo fresh info
    check zdraw prepare again '' x
    check zdraw rowinfo again info
    (( info[bytes] == info[session_bytes] )) || fail 'unload leaked rows'
  fi
} always {
  zdraw end
}
print -r -- 'PREPARED PASS'
