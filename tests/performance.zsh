#!/usr/bin/env zsh
# Regression contracts for invocation-local cells and session lookup shortcuts.
emulate -R zsh
setopt nounset
module_path=("$1")
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A expected actual info colors
typeset key text
same() {
  [[ ${#expected} == ${#actual} ]] || fail shape
  for key in "${(@k)expected}"; do
    [[ $expected[$key] == "$actual[$key]" ]] || fail "mismatch: $key"
  done
}
check zdraw init
{
  check zdraw addwin sample 3 40 0 0
  check zdraw addwin reference 3 40 4 0
  # Repeated scalars, direct-map collisions (A/U+0141), different attributes,
  # different pairs, and a combining suffix after a cached spacing scalar.
  for text in 'AAAAAAAA' 'AŁAŁAŁAŁ' $'eeeeeéé'; do
    check zdraw clear sample
    check zdraw clear reference
    check zdraw spans sample 0 0 bold,red/black "$text" blue/black "$text" '' "$text"
    check zdraw move reference 0 0
    check zdraw attr reference bold red/black
    check zdraw string reference "$text"
    check zdraw attr reference -bold blue/black
    check zdraw string reference "$text"
    check zdraw attr reference default/default
    check zdraw string reference "$text"
    check zdraw move reference 0 0
    check zdraw snapshot reference expected
    check zdraw snapshot sample actual
    same
  done
  check zdraw colorinfo colors
  typeset -i used=$colors[pairs_used]
  # A prior cache hit must not conceal an invalid discarded combining group.
  reject zdraw spansclip sample 0 0 1 yellow/black $'eeeeeé́́́́́'
  reject zdraw spansclip sample 0 0 1 yellow/black $'AAAAA\e'
  check zdraw snapshot sample actual
  same
  check zdraw colorinfo colors
  (( used == colors[pairs_used] )) || fail 'failed preflight allocated a pair'
  check zdraw textpolicy info
  if [[ $info[grapheme_available] == 1 ]]; then
    typeset policy=$info[grapheme_policy]
    check zdraw textinfo info $'AAAAéZZ' 5 "$policy"
    [[ $info[text] == $'AAAAé' && $info[remainder] == ZZ ]] || fail 'checked ASCII suffix'
    expected=("${(@kv)info}")
    reject zdraw textinfo info $'eeeeeé́́́́́' 1 "$policy"
    actual=("${(@kv)info}")
    same
  fi
  # Prime the lookup, delete, recreate the same name with a different size.
  check zdraw move sample 0 0
  check zdraw delwin sample
  reject zdraw move sample 0 0
  check zdraw addwin sample 2 6 0 0
  check zdraw fill sample 0 0 2 6 blue/black Z
  check zdraw cellinfo sample info
  [[ $info[text] == Z && $info[color] == blue/black ]] || fail 'recreated window'
} always {
  zdraw end
}
# Color IDs and window pointers are new in a second session.
check zdraw init
{
  check zdraw addwin sample 2 6 0 0
  check zdraw fill sample 0 0 2 6 green/black Q
  check zdraw cellinfo sample info
  [[ $info[text] == Q && $info[color] == green/black ]] || fail 'new session cache'
} always {
  zdraw end
}
check zmodload -u zdraw
check zmodload zdraw
reject zdraw move sample 0 0
print -r -- 'PERFORMANCE CONTRACTS PASS'
