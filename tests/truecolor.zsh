#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A info saved
typeset -a reply before after
cell() {
  check zdraw move sample "$1" "$2"
  check zdraw querychar sample reply
  [[ $reply[1] == "$3" && $reply[2] == "$4" ]] || fail "cell $1,$2: ${(j: :)reply}"
}
check zdraw colorinfo info
for key in truecolor_supported truecolor_enabled rgb_min rgb_max; do
  [[ $info[$key] == unknown ]] || fail "uninitialized $key"
done
reject zdraw truecolor on
check zdraw init
{
  check zdraw addwin sample 6 30 1 1
  check zdraw colorinfo info
  [[ $info[truecolor_enabled] == 0 ]] || fail 'implicit opt-in'
  reject zdraw truecolor
  reject zdraw truecolor invalid
  reject zdraw truecolor on extra
  reject zdraw attr sample '#112233/#445566'
  reject zdraw bg sample '#112233/#445566'
  reject zdraw spans sample 0 0 '#112233/#445566' X
  reject zdraw prepare disabled '#112233/#445566' X
  check zdraw colorinfo info
  (( info[pairs_used] == 0 )) || fail 'disabled RGB allocated pairs'
  if [[ $mode == unsupported || $mode == unavailable ]]; then
    [[ $info[truecolor_supported] == 0 && $info[rgb_min] == unknown &&
       $info[rgb_max] == unknown ]] || fail 'false capability'
    if [[ $mode == unavailable ]]; then
      (( ! ${zdraw_features[(Ie)truecolor]} )) || fail 'compiled capability'
    fi
    zdraw truecolor on
    (( $? == 2 )) || fail 'unsupported status'
    check zdraw truecolor off
    # The previous color API remains usable without truecolor.
    if [[ $info[has_colors] == 1 && $info[color_started] == 1 ]]; then
      check zdraw attr sample red/black
      check zdraw string sample legacy
      cell 0 0 l red/black
    fi
  else
    (( ${zdraw_features[(Ie)truecolor]} )) || fail 'missing compiled capability'
    [[ $info[truecolor_supported] == 1 && $info[rgb_max] == 16777215 ]] || fail 'direct capability'
    typeset -i minimum=8
    [[ $mode == exact ]] && minimum=0
    (( info[rgb_min] == minimum )) || fail 'RGB reservation'
    check zdraw truecolor on
    check zdraw truecolor on
    check zdraw init
    check zdraw colorinfo info
    [[ $info[truecolor_enabled] == 1 && $info[pairs_used] == 0 ]] || fail 'enable/reinit mutated resources'
    saved=("${(@kv)info}")
    typeset bad
    for bad in '#12345' '#1234567' '#12gg00' '#-12345' '# 12345' '#12345/' '16777215' '32768'; do
      reject zdraw attr sample "$bad/black"
      reject zdraw spans sample 0 0 red/black Q "$bad/black" X
    done
    if (( minimum )); then
      for bad in '#000000' '#000001' '#000007'; do
        reject zdraw attr sample "$bad/black"
        reject zdraw bg sample "red/$bad"
      done
    fi
    check zdraw colorinfo info
    (( info[pairs_used] == 0 )) || fail 'invalid input allocated colors'
    if [[ $mode == allocation_failure ]]; then
      reject zdraw spans sample 0 0 '#112233/#445566' X '#abcdef/#181818' Y
      check zdraw colorinfo info
      (( info[pairs_used] == 1 )) || fail 'allocation failure budget'
      check zdraw move sample 0 0
      check zdraw querychar sample reply
      [[ $reply[1] == ' ' ]] || fail 'allocation failure drew cells'
      check zdraw spans sample 0 0 '#112233/#445566' X
    else
      check zdraw attr sample bold '#112233/#445566'
      check zdraw string sample A
      cell 0 0 A '#112233/#445566'
      (( ${reply[(Ie)bold]} )) || fail 'RGB attributes'
      check zdraw colorinfo info
      (( info[pairs_used] == 1 )) || fail 'initial RGB allocation'
      check zdraw move sample 4 2
      check zdraw position sample before
      check zdraw spans sample 1 0 '#112233/#445566' B 'underline,#ABCDEF/#181818' C
      check zdraw position sample after
      [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'span cursor'
      cell 1 0 B '#112233/#445566'
      (( ! ${reply[(Ie)bold]} )) || fail 'span inherited attributes'
      cell 1 1 C '#ABCDEF/#181818'
      (( ${reply[(Ie)underline]} )) || fail 'span attributes'
      check zdraw spansclip sample 1 2 2 '#112233/#445566' ABCDEF
      cell 1 2 A '#112233/#445566'
      cell 1 3 B '#112233/#445566'
      check zdraw bg sample '#204060/#102030'
      cell 3 3 ' ' '#204060/#102030'
      check zdraw attr sample '#112233/#445566'
      check zdraw border sample
      check zdraw move sample 0 1
      check zdraw querychar sample reply
      [[ $reply[2] == '#112233/#445566' ]] || fail 'border RGB style'
      # Replace the ACS border cell for deterministic terminal output.
      check zdraw spans sample 0 1 '#ffffff/#000008' EDGE
      check zdraw spans sample 1 1 '#112233/#445566' DRAW
      if [[ $mode == exact ]]; then
        check zdraw spans sample 2 1 '#000001/#000000' EXACT
      fi
      if (( info[default_colors] )); then
        check zdraw spans sample 3 1 '#123456/default' DEFAULT
        cell 3 1 D '#123456/default'
      fi
      check zdraw refresh sample
      check zdraw colorinfo info
      typeset -i used=$info[pairs_used]
      check zdraw fill sample 3 10 2 3 '#112233/#445566' R
      cell 3 10 R '#112233/#445566'
      check zdraw restyle sample 3 10 2 3 'bold,#112233/#445566'
      cell 3 10 R '#112233/#445566'
      (( ${reply[(Ie)bold]} )) || fail 'RGB restyle attributes'
      check zdraw prepare retained '#112233/#445566' PREPARED
      check zdraw truecolor off
      # Both first use and a cache hit must obey off.
      reject zdraw attr sample '#112233/#445566'
      reject zdraw bg sample '#204060/#102030'
      reject zdraw spans sample 2 1 '#112233/#445566' Q
      reject zdraw fill sample 2 1 1 1 '#112233/#445566' Q
      reject zdraw restyle sample 2 1 1 1 '#112233/#445566'
      reject zdraw prepare disabled '#112233/#445566' Q
      check zdraw draw sample 4 1 retained
      cell 4 1 P '#112233/#445566'
      check zdraw copy sample 4 1 sample 2 10 1 3
      cell 2 10 P '#112233/#445566'
      check zdraw cellinfo sample saved
      [[ $saved[color] == '#112233/#445566' && $saved[color_source] == cache ]] || fail 'inspect RGB after opt-out'
      check zdraw colorinfo info
      (( info[pairs_used] == used && info[truecolor_enabled] == 0 )) || fail 'disable changed pairs'
      check zdraw move sample 4 1
      check zdraw string sample RETAINED
      cell 4 1 R '#112233/#445566'
      check zdraw truecolor on
      check zdraw attr sample '#112233/#445566'
      check zdraw colorinfo info
      (( info[pairs_used] == used )) || fail 'cache reuse after enabling'
      if [[ $mode == high_pairs ]]; then
        typeset -i i
        for (( i=0; i<270; i++ )); do
          check zdraw attr sample "$i/black"
        done
        check zdraw bg sample '#123456/#234567'
        check zdraw attr sample '#345678/#456789'
        check zdraw spans sample 1 1 '#56789a/#6789ab' HIGH
        cell 1 1 H '#56789a/#6789ab'
        check zdraw fill sample 3 10 2 3 '#56789a/#6789ab' X
        cell 3 10 X '#56789a/#6789ab'
        check zdraw restyle sample 3 10 2 3 'underline,#56789a/#6789ab'
        cell 3 10 X '#56789a/#6789ab'
        (( ${reply[(Ie)underline]} )) || fail 'high-pair restyle attributes'
        check zdraw prepare high '#56789a/#6789ab' PREPARED
        check zdraw addpad rgbpad 2 8
        check zdraw draw rgbpad 0 0 high
        check zdraw move rgbpad 0 0
        check zdraw cellinfo rgbpad saved
        [[ $saved[color] == '#56789a/#6789ab' && $saved[pair] -gt 255 ]] || fail 'pad high RGB pair'
        check zdraw viewport rgbpad 0 0 6 0 1 8
        check zdraw delwin rgbpad
        check zdraw draw sample 3 1 high
        cell 3 1 P '#56789a/#6789ab'
        check zdraw copy sample 3 1 sample 4 10 1 3
        cell 4 10 P '#56789a/#6789ab'
        check zdraw cellinfo sample saved
        [[ $saved[color] == '#56789a/#6789ab' && $saved[pair] -gt 255 ]] || fail 'inspect high RGB pair'
        check zdraw move sample 2 1
        check zdraw string sample SAVED
        cell 2 1 S '#345678/#456789'
        check zdraw refresh sample
      fi
      # Named and decimal spellings keep their existing semantics and cache.
      check zdraw attr sample red/black
      check zdraw move sample 2 1
      check zdraw string sample LEGACY
      cell 2 1 L red/black
      check zdraw attr sample 1/0
      check zdraw move sample 2 1
      check zdraw char sample N
      cell 2 1 N 1/0
    fi
  fi
  check zdraw delwin sample
} always {
  zdraw end
}
check zdraw colorinfo info
for key in truecolor_supported truecolor_enabled rgb_min rgb_max; do
  [[ $info[$key] == unknown ]] || fail "stale $key"
done
check zdraw init
check zdraw colorinfo info
[[ $info[truecolor_enabled] == 0 && $info[pairs_used] == 0 ]] || fail 'new session state'
check zdraw end
print -r -- 'TRUECOLOR PASS'
