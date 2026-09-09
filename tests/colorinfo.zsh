#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
typeset -i short_max=$3
zmodload zdraw || exit 1

fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
typeset -A info saved
typeset key
uninitialized() {
  local key
  check zdraw colorinfo info
  [[ $info[initialized] == 0 ]] || fail 'initialized without a session'
  for key in ${(k)info}; do
    [[ $key == initialized || $info[$key] == unknown ]] || fail "stale $key"
  done
}
uninitialized
check zdraw init
{
  check zdraw colorinfo info
  [[ $info[initialized] == 1 ]] || fail 'missing initialized state'
  if [[ $mode == monochrome || $mode == failed_start ]]; then
    if [[ $mode == monochrome ]]; then
      [[ $info[has_colors] == 0 && $info[can_change_color] == 0 ]] || fail 'monochrome capability'
      # ncurses can successfully initialize a zero-color table on vt100.
      if [[ $info[color_started] == 1 ]]; then
        [[ $info[colors] == 0 && $info[color_pairs] == 0 ]] || fail 'monochrome counts'
      else
        [[ $info[colors] == unknown && $info[color_pairs] == unknown ]] || fail 'uninitialized monochrome counts'
      fi
    else
      [[ $info[has_colors] == 1 ]] || fail 'lost capability on initialization failure'
      [[ $info[color_started] == 0 && $info[colors] == unknown &&
         $info[color_pairs] == unknown ]] || fail 'failed start state'
    fi
    [[ $info[default_colors] == 0 ]] || fail 'default colors unavailable'
    for key in color_limit pair_limit bg_pair_limit query_pair_limit spans_pair_limit pairs_used pairs_free; do
      [[ $info[$key] == 0 ]] || fail "failed start budget: $key"
    done
  else
    [[ $info[has_colors] == 1 && $info[color_started] == 1 ]] || fail 'color session unavailable'
    [[ $info[colors] == $ZDRAW_COLORS && $info[color_pairs] == $ZDRAW_COLOR_PAIRS ]] || fail 'raw counts differ'
    typeset -i color_limit=$ZDRAW_COLORS pair_limit=$((ZDRAW_COLOR_PAIRS-1))
    (( color_limit > short_max+1 )) && color_limit=$((short_max+1))
    (( pair_limit > short_max )) && pair_limit=$short_max
    (( info[color_limit] == color_limit && info[pair_limit] == pair_limit )) || fail 'module limits'
    (( info[pairs_used] == 0 && info[pairs_free] == pair_limit )) || fail 'query allocated pairs'
    [[ $info[can_change_color] == (0|1) ]] || fail 'palette capability state'
    if [[ $mode == defaults_failed ]]; then
      (( ${zdraw_features[(Ie)default_colors]} )) || fail 'compiled support lost'
      [[ $info[default_colors] == 0 ]] || fail 'failed default colors reported as successful'
    elif [[ $mode == no_defaults ]]; then
      (( ! ${zdraw_features[(Ie)default_colors]} )) || fail 'unexpected compiled support'
      [[ $info[default_colors] == 0 ]] || fail 'missing default colors reported as successful'
    else
      [[ $info[default_colors] == (0|1) ]] || fail 'default colors unknown during session'
    fi
    if [[ $mode == narrow ]]; then
      (( info[bg_pair_limit] <= 255 && info[bg_pair_limit] <= pair_limit &&
         info[query_pair_limit] <= 255 && info[query_pair_limit] <= pair_limit )) || fail 'narrow limits'
    else
      (( info[bg_pair_limit] <= pair_limit && info[query_pair_limit] <= pair_limit )) || fail 'operation limits'
    fi
    check zdraw addwin sample 4 12 1 1
    check zdraw attr sample red/black
    check zdraw string sample retained
    check zdraw colorinfo info
    (( info[pairs_used] == 1 && info[pairs_free] == pair_limit-1 )) || fail 'allocation count'
    saved=("${(@kv)info}")
    check zdraw init
    check zdraw attr sample red/black
    check zdraw colorinfo info
    for key in ${(k)saved}; do
      [[ $info[$key] == $saved[$key] ]] || fail "repeated init/query changed $key"
    done
    # Distinct spellings consume separate slots under the existing API.
    check zdraw attr sample 1/0
    check zdraw colorinfo info
    (( info[pairs_used] == 2 && info[pairs_free] == pair_limit-2 )) || fail 'alias pair count'
    zdraw attr sample invalid/black 2>/dev/null && fail 'invalid color accepted'
    check zdraw delwin sample
    check zdraw colorinfo info
    (( info[pairs_used] == 2 )) || fail 'deletion/failed allocation changed budget'
  fi
} always {
  zdraw end
}
uninitialized
check zmodload -u zdraw
check zmodload zdraw
uninitialized
check zdraw init
check zdraw colorinfo info
[[ $info[pairs_used] == 0 ]] || fail 'new session retained allocation count'
check zdraw end
uninitialized
print -r -- 'COLORINFO PASS'
