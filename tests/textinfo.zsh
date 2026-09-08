#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zsh/curses || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A info=(stale value)
(( ${zcurses_features[(Ie)textinfo]} )) || fail 'missing feature'
check zcurses textinfo info abc 2
[[ $info[text] == ab && $info[remainder] == c && $info[width] == 2 &&
   $info[total_width] == 3 && $info[truncated] == 1 && ${+info[stale]} == 0 ]] || fail 'ASCII clipping'
check zcurses textinfo info abc 0
[[ $info[text] == '' && $info[width] == 0 && $info[remainder] == abc && $info[truncated] == 1 ]] || fail 'zero budget'
check zcurses textinfo info '' 0
[[ $info[text] == '' && $info[remainder] == '' && $info[width] == 0 &&
   $info[total_width] == 0 && $info[truncated] == 0 ]] || fail 'empty text'
check zcurses textinfo info 'abc def'
[[ $info[text] == 'abc def' && $info[width] == 7 && $info[truncated] == 0 ]] || fail 'measurement only'
check zcurses textinfo info abc 0003
[[ $info[text] == abc && $info[truncated] == 0 ]] || fail 'decimal budget'
check zcurses textinfo created literal
[[ ${(t)created} == association && $created[text] == literal ]] || fail 'create association'
caller() {
  local -A local_info
  nested() { zcurses textinfo local_info local 3; }
  check nested
  [[ $local_info[text] == loc && $local_info[remainder] == al ]] || fail 'local association'
}
caller
[[ ${+local_info} == 0 ]] || fail 'local scope leaked'

# Errors leave an existing result unchanged and do not create a missing one.
typeset bad
for bad in $'a\n' $'a\t' $'a\r' $'a\e' $'a\0' $'a\x7f'; do
  info=(sentinel keep)
  reject zcurses textinfo info "$bad" 0
  [[ $info[sentinel] == keep && ${#info} == 1 ]] || fail 'invalid tail assigned output'
  reject zcurses textinfo absent "$bad" 0
  [[ ${+absent} == 0 ]] || fail 'invalid input created output'
done
for bad in '' -1 +1 1x 999999999999999999999 '$((1))' 'evil=1'; do
  reject zcurses textinfo info abc "$bad"
done
(( ! ${+evil} )) || fail 'budget evaluated as shell arithmetic'
reject zcurses textinfo info
reject zcurses textinfo info abc 1 extra
reject zcurses textinfo 'bad name' abc
reject zcurses textinfo 'info[key]' abc
reject zcurses textinfo functions abc
typeset -A frozen=(keep value)
typeset -r frozen
reject zcurses textinfo frozen abc
[[ $frozen[keep] == value ]] || fail 'readonly changed'
typeset scalar=keep
typeset -a array=(keep)
reject zcurses textinfo scalar abc
reject zcurses textinfo array abc
[[ $scalar == keep && $array == keep ]] || fail 'wrong parameter type changed'

if [[ $mode == wide ]]; then
  (( ${zcurses_features[(Ie)wide_text]} )) || fail 'missing wide text feature'
  check zcurses textinfo info $'e\u0301界b' 2
  [[ $info[text] == $'e\u0301' && $info[width] == 1 &&
     $info[remainder] == 界b && $info[total_width] == 4 ]] || fail 'wide boundary or mark'
  check zcurses textinfo info $'e\u0301界b' 3
  [[ $info[text] == $'e\u0301界' && $info[width] == 3 && $info[remainder] == b ]] || fail 'exact wide boundary'
  check zcurses textinfo info '界a' 1
  [[ $info[text] == '' && $info[remainder] == 界a && $info[width] == 0 ]] || fail 'skipped non-fitting wide character'
  check zcurses textinfo info $' \u0301x' 1
  [[ $info[text] == $' \u0301' && $info[remainder] == x ]] || fail 'space with mark'
  check zcurses textinfo info 'ă界' 1
  [[ $info[text] == ă && $info[remainder] == 界 ]] || fail 'metafied UTF-8 preservation'
  # Measurement has no curses complex-character storage limit.
  typeset marked=$'a\u0301\u0301\u0301\u0301\u0301\u0301\u0301\u0301\u0301'
  check zcurses textinfo info "${marked}b" 1
  [[ $info[text] == "$marked" && $info[width] == 1 && $info[remainder] == b ]] || fail 'long mark sequence truncated'
  for bad in $'\u0301a' $'a\xff' $'a\xe2\x82'; do
    reject zcurses textinfo info "$bad" 0
  done
  # Each prefix/remainder partition preserves original bytes, and the retained
  # width agrees with independently measuring that prefix for every budget.
  typeset original=$'ăe\u0301界  Ω\u0301z' prefix remainder
  typeset -i budget kept
  typeset -A measured
  for (( budget=0; budget<=12; budget++ )); do
    check zcurses textinfo info "$original" "$budget"
    prefix=$info[text] remainder=$info[remainder] kept=$info[width]
    [[ $prefix$remainder == "$original" ]] || fail 'byte partition'
    (( kept <= budget )) || fail 'budget exceeded'
    check zcurses textinfo measured "$prefix"
    (( measured[width] == kept )) || fail 'reported width'
  done
  unsetopt multibyte
  reject zcurses textinfo info é
  check zcurses textinfo info ascii 3
  setopt multibyte
else
  (( ! ${zcurses_features[(Ie)wide_text]} )) || fail 'unexpected wide text feature'
  zcurses textinfo info é 0 2>/dev/null
  (( $? == 2 )) || fail 'ASCII fallback status'
fi
# The new query neither starts curses nor consumes caller input.
(( ${#zcurses_windows} == 0 )) || fail 'query initialized curses'
consume() {
  check zcurses textinfo info abc 1
  local line
  read -r line || fail 'input consumed'
  [[ $line == 'input stays data' ]] || fail 'input altered'
}
consume <<<'input stays data'
print -r -- 'TEXTINFO PASS'
