#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A info=(sentinel yes)
typeset -a before after legacy
typeset -Ar frozen=(sentinel yes)
typeset scalar=sentinel
typeset -a array=(sentinel)
reject zdraw cellinfo stdscr info
[[ $info[sentinel] == yes ]] || fail 'uninitialized query changed target'
(( ${zdraw_features[(Ie)cell_inspection]} )) || fail 'feature missing'
check zdraw init
{
  check zdraw addwin sample 3 12 1 1
  if [[ $mode == monochrome || $mode == uncached ]]; then
    check zdraw spans sample 0 0 bold A
  else
    check zdraw spans sample 0 0 bold,underline,red/black A
  fi
  check zdraw move sample 0 0
  check zdraw position sample before
  if [[ $mode == monochrome || $mode == uncached ]]; then
    check zdraw cellinfo sample info
    [[ $info[text] == A && $info[pair] == 0 ]] || fail 'default cell readback'
    if [[ $mode == uncached ]]; then
      [[ $info[color] == unknown && $info[color_source] == unknown ]] || fail 'uncached color'
    else
      # Some libraries initialize a default pair even without terminal colors.
      [[ ( $info[color_source] == cache && $info[color] == default/default ) ||
         ( $info[color_source] == unknown && $info[color] == unknown ) ]] || fail 'default color evidence'
    fi
  elif [[ $mode == *_failure ]]; then
    reject zdraw cellinfo sample info
    reject zdraw cellinfo sample absent
    [[ $info[sentinel] == yes && ! -v absent ]] || fail 'read failure assigned output'
  else
    check zdraw cellinfo sample info
    [[ $info[text] == A && $info[color] == red/black && $info[color_source] == cache &&
       $info[pair] -gt 0 && $info[characters] == 1 && $info[row] == 0 && $info[column] == 0 &&
       $info[attributes] == 'bold underline' && $info[attribute_bits] -gt 0 &&
       ! -v 'info[sentinel]' ]] || fail "cell record: ${(kv)info}"
    [[ $mode == narrow ]] && expected=byte || expected=multibyte
    [[ $info[encoding] == $expected ]] || fail 'encoding'
    for target in frozen scalar array parameters 'info[x]' 'bad name' ''; do
      reject zdraw cellinfo sample "$target"
    done
    [[ $scalar == sentinel && $array == sentinel && $frozen[sentinel] == yes ]] || fail 'target mutated'
    reject zdraw cellinfo missing info
    reject zdraw cellinfo sample
    reject zdraw cellinfo sample info extra
    [[ $info[text] == A ]] || fail 'failed preflight changed target'
    check zdraw cellinfo sample created
    [[ $created[text] == A ]] || fail 'create target'
    local_query() {
      local -A info
      zdraw cellinfo sample info || return
      [[ $info[text] == A ]]
    }
    check local_query
    [[ $info[text] == A ]] || fail 'local leaked'
    check zdraw position sample after
    [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'cursor moved'
    if [[ $mode != narrow ]]; then
      (( ${zdraw_features[(Ie)wide_cell_inspection]} )) || fail 'wide feature missing'
      check zdraw spans sample 0 1 reverse $'ă\u0301\u0308' '' 界
      check zdraw move sample 0 1
      check zdraw cellinfo sample info
      [[ $info[text] == $'ă\u0301\u0308' && $info[characters] == 3 &&
         $info[attributes] == reverse ]] || fail 'complex cell truncated'
      check zdraw querychar sample legacy
      [[ $legacy[1] == ă ]] || fail 'legacy first-character contract changed'
      for col in 2 3; do
        check zdraw move sample 0 "$col"
        check zdraw cellinfo sample info
        [[ $info[text] == 界 && $info[column] == $col ]] || fail 'wide occupied column'
      done
      check zdraw move sample 0 1
      change_locale() {
        local LC_ALL=C
        local -A info=(sentinel yes)
        reject zdraw cellinfo sample info
        [[ $info[sentinel] == yes ]] || fail 'conversion failure assigned output'
      }
      check change_locale
      check zdraw cellinfo sample info
      [[ $info[text] == $'ă\u0301\u0308' ]] || fail 'locale failure damaged cell'
      unsetopt multibyte
      check zdraw cellinfo sample info
      [[ $info[text] == 'ắ̈' && $info[characters] == 3 ]] || fail 'option truncated readback'
      setopt multibyte
    else
      (( ! ${zdraw_features[(Ie)wide_cell_inspection]} )) || fail 'wide feature advertised'
      check zdraw border sample
      check zdraw move sample 0 1
      check zdraw cellinfo sample info
      [[ $info[attributes] == *altcharset* ]] || fail 'missing alternate character flag'
    fi
    # Querying a cell does not alter attributes/background for later drawing.
    check zdraw bg sample '@#' reverse
    check zdraw attr sample underline green/black
    check zdraw move sample 1 1
    check zdraw cellinfo sample info
    check zdraw string sample ' '
    check zdraw move sample 1 1
    check zdraw cellinfo sample info
    [[ $info[text] == '#' && $info[color] == green/black &&
       $info[attributes] == 'reverse underline' ]] || fail 'window style changed'
    check zdraw clear sample
    check zdraw move sample 0 0
    check zdraw cellinfo sample info
    [[ $info[text] == '#' ]] || fail 'background readback'
  fi
  check zdraw position sample after
  if [[ $mode == *_failure ]]; then
    [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'failed read moved cursor'
  fi
} always {
  zdraw end
}
reject zdraw cellinfo stdscr info
print -r -- 'CELLINFO PASS'
