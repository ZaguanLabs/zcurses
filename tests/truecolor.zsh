#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
zmodload zsh/curses || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A info saved
typeset -a reply before after
cell() {
  check zcurses move sample "$1" "$2"
  check zcurses querychar sample reply
  [[ $reply[1] == "$3" && $reply[2] == "$4" ]] || fail "cell $1,$2: ${(j: :)reply}"
}
check zcurses colorinfo info
for key in truecolor_supported truecolor_enabled rgb_min rgb_max; do
  [[ $info[$key] == unknown ]] || fail "uninitialized $key"
done
reject zcurses truecolor on
check zcurses init
{
  check zcurses addwin sample 6 30 1 1
  check zcurses colorinfo info
  [[ $info[truecolor_enabled] == 0 ]] || fail 'implicit opt-in'
  reject zcurses truecolor
  reject zcurses truecolor invalid
  reject zcurses truecolor on extra
  reject zcurses attr sample '#112233/#445566'
  reject zcurses bg sample '#112233/#445566'
  reject zcurses spans sample 0 0 '#112233/#445566' X
  check zcurses colorinfo info
  (( info[pairs_used] == 0 )) || fail 'disabled RGB allocated pairs'
  if [[ $mode == unsupported || $mode == unavailable ]]; then
    [[ $info[truecolor_supported] == 0 && $info[rgb_min] == unknown &&
       $info[rgb_max] == unknown ]] || fail 'false capability'
    if [[ $mode == unavailable ]]; then
      (( ! ${zcurses_features[(Ie)truecolor]} )) || fail 'compiled capability'
    fi
    zcurses truecolor on
    (( $? == 2 )) || fail 'unsupported status'
    check zcurses truecolor off
    # The previous color API remains usable without truecolor.
    if [[ $info[has_colors] == 1 && $info[color_started] == 1 ]]; then
      check zcurses attr sample red/black
      check zcurses string sample legacy
      cell 0 0 l red/black
    fi
  else
    (( ${zcurses_features[(Ie)truecolor]} )) || fail 'missing compiled capability'
    [[ $info[truecolor_supported] == 1 && $info[rgb_max] == 16777215 ]] || fail 'direct capability'
    typeset -i minimum=8
    [[ $mode == exact ]] && minimum=0
    (( info[rgb_min] == minimum )) || fail 'RGB reservation'
    check zcurses truecolor on
    check zcurses truecolor on
    check zcurses init
    check zcurses colorinfo info
    [[ $info[truecolor_enabled] == 1 && $info[pairs_used] == 0 ]] || fail 'enable/reinit mutated resources'
    saved=("${(@kv)info}")
    typeset bad
    for bad in '#12345' '#1234567' '#12gg00' '#-12345' '# 12345' '#12345/' '16777215' '32768'; do
      reject zcurses attr sample "$bad/black"
      reject zcurses spans sample 0 0 red/black Q "$bad/black" X
    done
    if (( minimum )); then
      for bad in '#000000' '#000001' '#000007'; do
        reject zcurses attr sample "$bad/black"
        reject zcurses bg sample "red/$bad"
      done
    fi
    check zcurses colorinfo info
    (( info[pairs_used] == 0 )) || fail 'invalid input allocated colors'
    if [[ $mode == allocation_failure ]]; then
      reject zcurses spans sample 0 0 '#112233/#445566' X '#abcdef/#181818' Y
      check zcurses colorinfo info
      (( info[pairs_used] == 1 )) || fail 'allocation failure budget'
      check zcurses move sample 0 0
      check zcurses querychar sample reply
      [[ $reply[1] == ' ' ]] || fail 'allocation failure drew cells'
      check zcurses spans sample 0 0 '#112233/#445566' X
    else
      check zcurses attr sample bold '#112233/#445566'
      check zcurses string sample A
      cell 0 0 A '#112233/#445566'
      (( ${reply[(Ie)bold]} )) || fail 'RGB attributes'
      check zcurses colorinfo info
      (( info[pairs_used] == 1 )) || fail 'initial RGB allocation'
      check zcurses move sample 4 2
      check zcurses position sample before
      check zcurses spans sample 1 0 '#112233/#445566' B 'underline,#ABCDEF/#181818' C
      check zcurses position sample after
      [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'span cursor'
      cell 1 0 B '#112233/#445566'
      (( ! ${reply[(Ie)bold]} )) || fail 'span inherited attributes'
      cell 1 1 C '#ABCDEF/#181818'
      (( ${reply[(Ie)underline]} )) || fail 'span attributes'
      check zcurses spansclip sample 1 2 2 '#112233/#445566' ABCDEF
      cell 1 2 A '#112233/#445566'
      cell 1 3 B '#112233/#445566'
      check zcurses bg sample '#204060/#102030'
      cell 3 3 ' ' '#204060/#102030'
      check zcurses attr sample '#112233/#445566'
      check zcurses border sample
      check zcurses move sample 0 1
      check zcurses querychar sample reply
      [[ $reply[2] == '#112233/#445566' ]] || fail 'border RGB style'
      # Replace the ACS border cell for deterministic terminal output.
      check zcurses spans sample 0 1 '#ffffff/#000008' EDGE
      check zcurses spans sample 1 1 '#112233/#445566' DRAW
      if [[ $mode == exact ]]; then
        check zcurses spans sample 2 1 '#000001/#000000' EXACT
      fi
      if (( info[default_colors] )); then
        check zcurses spans sample 3 1 '#123456/default' DEFAULT
        cell 3 1 D '#123456/default'
      fi
      check zcurses refresh sample
      check zcurses colorinfo info
      typeset -i used=$info[pairs_used]
      check zcurses truecolor off
      # Both first use and a cache hit must obey off.
      reject zcurses attr sample '#112233/#445566'
      reject zcurses bg sample '#204060/#102030'
      reject zcurses spans sample 2 1 '#112233/#445566' Q
      check zcurses colorinfo info
      (( info[pairs_used] == used && info[truecolor_enabled] == 0 )) || fail 'disable changed pairs'
      check zcurses move sample 4 1
      check zcurses string sample RETAINED
      cell 4 1 R '#112233/#445566'
      check zcurses truecolor on
      check zcurses attr sample '#112233/#445566'
      check zcurses colorinfo info
      (( info[pairs_used] == used )) || fail 'cache reuse after enabling'
      if [[ $mode == high_pairs ]]; then
        typeset -i i
        for (( i=0; i<270; i++ )); do
          check zcurses attr sample "$i/black"
        done
        check zcurses bg sample '#123456/#234567'
        check zcurses attr sample '#345678/#456789'
        check zcurses spans sample 1 1 '#56789a/#6789ab' HIGH
        cell 1 1 H '#56789a/#6789ab'
        check zcurses move sample 2 1
        check zcurses string sample SAVED
        cell 2 1 S '#345678/#456789'
        check zcurses refresh sample
      fi
      # Named and decimal spellings keep their existing semantics and cache.
      check zcurses attr sample red/black
      check zcurses move sample 2 1
      check zcurses string sample LEGACY
      cell 2 1 L red/black
      check zcurses attr sample 1/0
      check zcurses move sample 2 1
      check zcurses char sample N
      cell 2 1 N 1/0
    fi
  fi
  check zcurses delwin sample
} always {
  zcurses end
}
check zcurses colorinfo info
for key in truecolor_supported truecolor_enabled rgb_min rgb_max; do
  [[ $info[$key] == unknown ]] || fail "stale $key"
done
check zcurses init
check zcurses colorinfo info
[[ $info[truecolor_enabled] == 0 && $info[pairs_used] == 0 ]] || fail 'new session state'
check zcurses end
print -r -- 'TRUECOLOR PASS'
