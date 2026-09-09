#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A info=(stale value) measured other
typeset bad coordinate
(( ${zdraw_features[(Ie)text_positions]} )) || fail 'missing feature'
check zdraw textpos info abc column 1
[[ $info[prefix] == a && $info[text] == b && $info[remainder] == c &&
   $info[byte_start] == 1 && $info[byte_end] == 2 && $info[column_start] == 1 &&
   $info[column_end] == 2 && $info[total_bytes] == 3 && $info[total_width] == 3 &&
   $info[at_end] == 0 && ! -v 'info[stale]' ]] || fail 'ASCII position'
check zdraw textpos created abc byte 0002
[[ $created[text] == c ]] || fail 'create association'
for coordinate in byte column; do
  check zdraw textpos info abc "$coordinate" 3
  [[ $info[prefix] == abc && $info[text] == '' && $info[remainder] == '' &&
     $info[byte_start] == 3 && $info[byte_end] == 3 && $info[column_start] == 3 &&
     $info[column_end] == 3 && $info[at_end] == 1 ]] || fail 'end boundary'
  check zdraw textpos info '' "$coordinate" 0
  [[ $info[text] == '' && $info[at_end] == 1 && $info[total_bytes] == 0 &&
     $info[total_width] == 0 ]] || fail 'empty boundary'
  reject zdraw textpos info abc "$coordinate" 4
  reject zdraw textpos info '' "$coordinate" 1
done
local_query() {
  local -A info
  zdraw textpos info ab column 0 || return
  [[ $info[text] == a ]]
}
check local_query
[[ $info[total_bytes] == 0 ]] || fail 'local assignment leaked'
typeset -Ar frozen=(sentinel yes)
typeset scalar=sentinel
typeset -a array=(sentinel)
for target in frozen scalar array parameters 'info[x]' 'bad name' ''; do
  reject zdraw textpos "$target" abc column 0
done
[[ $scalar == sentinel && $array == sentinel && $frozen[sentinel] == yes ]] || fail 'target mutated'
for bad in '' -1 +1 1x 99999999999999999999 '$((1))' 'evil=1'; do
  reject zdraw textpos info abc column "$bad"
done
(( ! ${+evil} )) || fail 'offset evaluated'
reject zdraw textpos info abc bogus 0
reject zdraw textpos info abc column
reject zdraw textpos info abc column 0 extra
for bad in $'a\n' $'a\t' $'a\e' $'a\0' $'a\x7f'; do
  info=(sentinel yes)
  reject zdraw textpos info "$bad" column 0
  [[ $info[sentinel] == yes && ${#info} == 1 ]] || fail 'invalid suffix changed target'
  reject zdraw textpos absent "$bad" byte 0
  (( ! ${+absent} )) || fail 'invalid suffix created target'
done
if [[ $mode == wide ]]; then
  typeset original=$'ăe\u0301界b'
  # Raw UTF-8 ranges: ă=[0,2), e+accent=[2,5), 界=[5,8), b=[8,9).
  for offset in 2 3 4; do
    check zdraw textpos info "$original" byte "$offset"
    [[ $info[text] == $'e\u0301' && $info[byte_start] == 2 && $info[byte_end] == 5 &&
       $info[column_start] == 1 && $info[column_end] == 2 ]] || fail 'combining byte range'
  done
  for offset in 2 3; do
    check zdraw textpos info "$original" column "$offset"
    [[ $info[text] == 界 && $info[byte_start] == 5 && $info[byte_end] == 8 &&
       $info[column_start] == 2 && $info[column_end] == 4 ]] || fail 'wide hit range'
  done
  check zdraw textpos info "$original" byte 1
  [[ $info[text] == ă && $info[byte_end] == 2 ]] || fail 'metafied byte counting'
  byte_length() { local LC_ALL=C; REPLY=${#1}; }
  typeset REPLY
  typeset -i offset count
  for coordinate in column byte; do
    [[ $coordinate == column ]] && count=5 || count=9
    for (( offset=0; offset<=count; offset++ )); do
      check zdraw textpos info "$original" "$coordinate" "$offset"
      [[ $info[prefix]$info[text]$info[remainder] == "$original" ]] || fail 'byte partition'
      check zdraw textinfo measured "$info[prefix]"
      (( measured[width] == info[column_start] )) || fail 'prefix width'
      check zdraw textinfo measured "$info[prefix]$info[text]"
      (( measured[width] == info[column_end] )) || fail 'end width'
      byte_length "$info[prefix]"
      (( REPLY == info[byte_start] )) || fail 'prefix byte length'
      byte_length "$info[prefix]$info[text]"
      (( REPLY == info[byte_end] )) || fail 'end byte length'
      check zdraw textpos other "$original" byte "$info[byte_start]"
      [[ ${(kv)info} == ${(kv)other} ]] || fail 'byte round trip'
      check zdraw textpos other "$original" column "$info[column_start]"
      [[ ${(kv)info} == ${(kv)other} ]] || fail 'column round trip'
    done
  done
  # This query measures text, independent of curses' combining storage limit.
  typeset marked=$'a\u0301\u0301\u0301\u0301\u0301\u0301\u0301\u0301'
  check zdraw textpos info "${marked}b" column 0
  [[ $info[text] == "$marked" && $info[byte_end] == 17 ]] || fail 'long mark group'
  # A joiner stays with its preceding base; no grapheme/emoji shaping is claimed.
  check zdraw textpos info $'a\u200db' byte 2
  [[ $info[text] == $'a\u200d' && $info[column_end] == 1 ]] || fail 'zero-width joiner rule'
  for bad in $'\u0301a' $'a\xff' $'a\xe2\x82'; do
    reject zdraw textpos info "$bad" column 0
  done
  changed_locale() {
    local LC_ALL=C
    reject zdraw textpos info é column 0
    check zdraw textpos info ascii column 1
  }
  check changed_locale
  unsetopt multibyte
  reject zdraw textpos info é column 0
  check zdraw textpos info ascii byte 1
  setopt multibyte
else
  zdraw textpos info é column 0 2>/dev/null
  (( $? == 2 )) || fail 'ASCII fallback status'
fi
(( ${#zdraw_windows} == 0 )) || fail 'query initialized curses'
consume() {
  check zdraw textpos info abc column 1
  local line
  read -r line || fail 'input consumed'
  [[ $line == 'input stays data' ]] || fail 'input altered'
}
consume <<<'input stays data'
print -r -- 'TEXTPOS PASS'
