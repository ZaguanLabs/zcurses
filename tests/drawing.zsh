#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
typeset -i short_max=$3
zmodload zdraw || exit 1

fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
cell() {
  local -a reply
  check zdraw move sample "$1" "$2"
  check zdraw querychar sample reply
  [[ $reply[1] == "$3" ]] || fail "cell $1,$2: ${(V)reply[1]} != ${(V)3}"
}

check zdraw init
{
  check zdraw addwin sample 5 12 1 1
  if [[ $mode == exhaustion ]]; then
    typeset -A colorinfo
    check zdraw colorinfo colorinfo
    typeset -i limit=$(( ZDRAW_COLOR_PAIRS - 1 )) i f b
    (( limit > short_max )) && limit=$short_max
    (( colorinfo[pair_limit] == limit && colorinfo[pairs_used] == 0 &&
       colorinfo[pairs_free] == limit )) || fail 'initial pair budget'
    (( limit > 0 && ZDRAW_COLORS * ZDRAW_COLORS >= limit )) || fail 'insufficient palette for exhaustion fixture'
    typeset pair last_pair
    for (( i=0; i<limit; i++ )); do
      f=$(( i / ZDRAW_COLORS )) b=$(( i % ZDRAW_COLORS ))
      pair=$f/$b
      check zdraw attr sample "$pair"
      if (( i == 0 )); then
        check zdraw string sample A
      fi
    done
    last_pair=$pair
    # A new spelling requires a new pair; failure must not corrupt old cells
    # or prevent reuse of an already allocated pair.
    reject zdraw attr sample 0000/0000
    check zdraw colorinfo colorinfo
    (( colorinfo[pairs_free] == 0 && colorinfo[pairs_used] == limit )) || fail 'exhausted pair budget'
    check zdraw attr sample "$last_pair"
    check zdraw move sample 0 0
    typeset -a reply
    check zdraw querychar sample reply
    [[ $reply[1] == A && $reply[2] == 0/0 ]] || fail 'exhaustion changed a retained cell'
  else
    check zdraw attr sample bold green/black
    check zdraw move sample 2 2
    check zdraw string sample inside
    check zdraw move sample 2 3
    typeset -a before after reply
    check zdraw position sample before
    check zdraw border sample L R T B 1 2 3 4
    check zdraw position sample after
    [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'border moved cursor'
    cell 0 0 1; cell 0 11 2; cell 4 0 3; cell 4 11 4
    cell 1 0 L; cell 1 11 R; cell 0 1 T; cell 4 1 B
    cell 2 2 i
    check zdraw move sample 0 0
    check zdraw querychar sample reply
    [[ $reply[2] == green/black && ${reply[(Ie)bold]} -gt 0 ]] || fail 'border attributes'
    check zdraw move sample 3 3
    check zdraw string sample X
    check zdraw move sample 3 3
    check zdraw querychar sample reply
    [[ $reply[2] == green/black && ${reply[(Ie)bold]} -gt 0 ]] || fail 'border changed window attributes'

    # Invalid arguments must leave the whole perimeter unchanged. Put the bad
    # glyph last to catch implementations that draw as they validate.
    typeset bad
    for bad in ab $'\n' $'\t' $'\e' $'\x7f'; do
      reject zdraw border sample a b c d e f g "$bad"
      cell 0 0 1; cell 0 11 2; cell 4 0 3; cell 4 11 4
    done
    reject zdraw border sample a
    reject zdraw border sample a b c d e f g
    reject zdraw border sample a b c d e f g h i
    reject zdraw border missing a b c d e f g h

    # Empty glyphs select the library's defaults; spaces remain blank cells.
    check zdraw border sample
    check zdraw move sample 0 0
    check zdraw querychar sample before
    check zdraw border sample '' '' '' '' '' '' '' ''
    check zdraw querychar sample after
    # Narrow ACS may read back as its mapped ASCII code, while wide curses
    # stores the corresponding Unicode character. Both are library defaults.
    if [[ $mode == wide ]]; then
      [[ $after[1] == '┌' ]] || fail 'wide empty glyph default'
    else
      [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'empty glyph default'
    fi
    check zdraw border sample ' ' ' ' ' ' ' ' ' ' ' ' ' ' ' '
    cell 0 0 ' '; cell 0 1 ' '; cell 4 11 ' '
    check zdraw bg sample @.
    check zdraw border sample ' ' ' ' ' ' ' ' ' ' ' ' ' ' ' '
    cell 0 0 .; cell 4 11 .
    check zdraw bg sample '@ '

    check zdraw addwin tiny 1 4 7 1
    reject zdraw border tiny a b c d e f g h
    check zdraw delwin tiny
    check zdraw addwin tiny 4 1 7 1
    reject zdraw border tiny a b c d e f g h
    check zdraw delwin tiny
    check zdraw addwin tiny 2 2 7 1
    check zdraw border tiny a b c d e f g h
    check zdraw delwin tiny

    if [[ $mode == wide ]]; then
      (( ${zdraw_features[(Ie)wide_borders]} )) || fail 'missing wide borders'
      check zdraw border sample '│' '│' '─' '─' '╭' '╮' '╰' '╯'
      cell 0 0 '╭'; cell 0 11 '╮'; cell 4 0 '╰'; cell 4 11 '╯'
      cell 1 0 '│'; cell 0 1 '─'
      for bad in $'\u0301' $'e\u0301' '界' $'\xff' $'\xc3'; do
        reject zdraw border sample a b c d e f g "$bad"
        cell 0 0 '╭'; cell 4 11 '╯'
      done
      # These UTF-8 characters contain bytes that Zsh internally metafies.
      typeset glyph
      for glyph in '┌' 'é' '界' A; do
        check zdraw move sample 2 1
        check zdraw char sample "$glyph"
        cell 2 1 "$glyph"
      done
      reject zdraw char sample ''
      reject zdraw char sample $'\0'
      reject zdraw char sample $'\xff'
      check zdraw move sample 2 1
      check zdraw char sample AB
      cell 2 1 A
      check zdraw move sample 2 1
      check zdraw string sample $'e\u0301\u0327'
      # querychar retains its first-character result, while the buffer must
      # accommodate the whole complex character and its terminator.
      cell 2 1 e
    else
      (( ! ${zdraw_features[(Ie)wide_borders]} )) || fail 'unexpected wide borders'
      zdraw border sample a b c d e f g '╯' 2>/dev/null
      (( $? == 2 )) || fail 'missing unsupported-wide status'
    fi

    typeset invalid
    for invalid in 1x/0 0/1x 999999999999999999999999/0 0/99999999999999999999999 /0 0/ 0/0/0 -1/0 "$ZDRAW_COLORS/0" "$((short_max+1))/0"; do
      reject zdraw attr sample "$invalid"
    done
    check zdraw attr sample "$((ZDRAW_COLORS-1))/0"
    check zdraw attr sample default/default
    check zdraw refresh sample
  fi
  check zdraw delwin sample
} always {
  zdraw end
}
check zdraw init
check zdraw attr stdscr red/black
check zdraw end
print -r -- 'DRAWING PASS'
