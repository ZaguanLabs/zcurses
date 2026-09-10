#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A info=(stale yes) clipped measured hit
typeset bad original remaining joined key
typeset padding=''
typeset -i i budget byte_offset column_offset
(( ${zdraw_features[(Ie)text_wrapping]} )) || fail 'missing feature'
check zdraw textwrap info 'abcd efghi' 4
[[ $info[format] == zdraw-textwrap-1 && $info[columns] == 4 &&
   $info[line_count] == 3 && $info[total_bytes] == 10 && $info[total_width] == 10 &&
   $info[0,text] == abcd && $info[1,text] == ' efg' && $info[2,text] == hi &&
   $info[1,byte_start] == 4 && $info[1,byte_end] == 8 &&
   $info[1,column_start] == 4 && $info[1,column_end] == 8 &&
   $info[2,width] == 2 && ${#info} == 25 && ! -v 'info[stale]' ]] || fail 'ASCII ranges'
check zdraw textwrap created '' 1
[[ $created[line_count] == 1 && $created[0,text] == '' &&
   $created[0,byte_start] == 0 && $created[0,byte_end] == 0 &&
   $created[0,width] == 0 && $created[total_width] == 0 && ${#created} == 13 ]] || fail 'empty line'
check zdraw textwrap info abcdef 0003
[[ $info[line_count] == 2 && $info[1,text] == def ]] || fail 'spurious trailing row'
local_query() {
  local -A info
  zdraw textwrap info abc 2 || return
  [[ $info[0,text] == ab && $info[1,text] == c ]]
}
check local_query
[[ $info[1,text] == def ]] || fail 'local assignment leaked'
typeset -Ar frozen=(sentinel yes)
typeset scalar=sentinel
typeset -a array=(sentinel)
for target in frozen scalar array parameters 'info[x]' 'bad name' ''; do
  reject zdraw textwrap "$target" abc 2
done
[[ $scalar == sentinel && $array == sentinel && $frozen[sentinel] == yes ]] || fail 'invalid target changed'
for bad in '' 0 -1 +1 1x 99999999999999999999 '$((1))' 'evil=1'; do
  reject zdraw textwrap info abc "$bad"
done
(( ! ${+evil} )) || fail 'budget evaluated'
reject zdraw textwrap info abc
reject zdraw textwrap info abc 2 extra
for bad in $'abcdef\n' $'abcdef\t' $'abcdef\r' $'abcdef\e' $'abcdef\0' $'abcdef\x7f'; do
  info=(sentinel yes)
  reject zdraw textwrap info "$bad" 3
  [[ $info[sentinel] == yes && ${#info} == 1 ]] || fail 'invalid suffix published partial rows'
  reject zdraw textwrap absent "$bad" 3
  (( ! ${+absent} )) || fail 'invalid suffix created output'
done
if [[ $mode == limits ]]; then
  check zdraw textwrap info abcdefghi 3
  [[ $info[line_count] == 3 && $info[line_limit] == 3 && $info[byte_limit] == 16 ]] || fail 'line boundary'
  reject zdraw textwrap info abcdefghij 3
  [[ $info[line_count] == 3 && $info[2,text] == ghi ]] || fail 'line limit changed output'
  check zdraw textwrap info 0123456789abcdef 16
  reject zdraw textwrap info 0123456789abcdefg 17
  [[ $info[0,text] == 0123456789abcdef ]] || fail 'byte limit changed output'
  # Raw encoded bytes, including Zsh's internal Meta escaping, count once.
  original=${(pl:8::ă:)padding}
  check zdraw textwrap info "$original" 8
  [[ $info[total_bytes] == 16 && $info[0,byte_end] == 16 ]] || fail 'metafied byte boundary'
  reject zdraw textwrap info "${original}x" 9
  [[ $info[0,text] == "$original" ]] || fail 'multibyte limit changed output'
else
  # Compare each row with the existing independent clipping query and map its
  # boundaries back through textpos. Rejoining preserves every original byte.
  typeset -a samples=('one  two three ' ' abcdef' 'a' '')
  if [[ $mode == wide ]]; then
    samples+=($'ăe\u0301界b' $'a界b界' $'a\u200db' $'a\u0301\u0301\u0301\u0301\u0301\u0301b')
  fi
  byte_length() { local LC_ALL=C; REPLY=${#1}; }
  typeset REPLY
  for original in "${samples[@]}"; do
    for budget in 2 3 4 8 100; do
      check zdraw textwrap info "$original" "$budget"
      remaining=$original joined='' byte_offset=0 column_offset=0
      for (( i=0; i<info[line_count]; i++ )); do
        check zdraw textinfo clipped "$remaining" "$budget"
        [[ $info[$i,text] == "$clipped[text]" && $info[$i,width] == "$clipped[width]" ]] || fail 'greedy clipping equivalence'
        [[ $info[$i,byte_start] == $byte_offset && $info[$i,column_start] == $column_offset ]] || fail 'noncontiguous ranges'
        byte_length "$info[$i,text]"
        byte_offset=$(( byte_offset + REPLY ))
        column_offset=$(( column_offset + clipped[width] ))
        [[ $info[$i,byte_end] == $byte_offset && $info[$i,column_end] == $column_offset ]] || fail 'end ranges'
        check zdraw textpos hit "$original" byte "$byte_offset"
        (( hit[byte_start] == byte_offset && hit[column_start] == column_offset )) || fail 'wrap split a clipping unit'
        joined+=$info[$i,text]
        remaining=$clipped[remainder]
      done
      [[ $joined == "$original" && $remaining == '' &&
         $info[total_bytes] == $byte_offset && $info[total_width] == $column_offset ]] || fail 'source reconstruction'
    done
  done
  if [[ $mode == wide ]]; then
    check zdraw textwrap info $'e\u0301b' 1
    [[ $info[line_count] == 2 && $info[0,text] == $'e\u0301' && $info[0,byte_end] == 3 ]] || fail 'full-row combining suffix'
    for bad in $'\u0301a' $'a\xff' $'a\xe2\x82' 'a界'; do
      info=(sentinel yes)
      reject zdraw textwrap info "$bad" 1
      [[ $info[sentinel] == yes && ${#info} == 1 ]] || fail 'invalid or oversized unit changed output'
    done
    changed_locale() {
      local LC_ALL=C
      reject zdraw textwrap info é 2
      check zdraw textwrap info ascii 2
    }
    check changed_locale
    unsetopt multibyte
    reject zdraw textwrap info é 2
    check zdraw textwrap info ascii 2
    setopt multibyte
    # Exercise the real caps without command-line argument length limits.
    original=${(pl:4096::x:)padding}
    check zdraw textwrap info "$original" 1
    [[ $info[line_count] == 4096 && $info[4095,byte_end] == 4096 ]] || fail 'native line boundary'
    reject zdraw textwrap info "${original}x" 1
    original=${(pl:1048576::x:)padding}
    check zdraw textwrap info "$original" 1048576
    [[ $info[line_count] == 1 && $info[total_bytes] == 1048576 ]] || fail 'native byte boundary'
    reject zdraw textwrap info "${original}x" 1048577
  else
    zdraw textwrap info é 2 2>/dev/null
    (( $? == 2 )) || fail 'ASCII fallback status'
  fi
fi
(( ${#zdraw_windows} == 0 )) || fail 'query initialized curses'
consume() {
  check zdraw textwrap info abc 2
  local line
  read -r line || fail 'input consumed'
  [[ $line == 'input stays data' ]] || fail 'input altered'
}
consume <<<'input stays data'
check zmodload -u zdraw
check zmodload zdraw
check zdraw textwrap info abc 2
[[ $info[1,text] == c ]] || fail 'reload query'
print -r -- 'TEXTWRAP PASS'
