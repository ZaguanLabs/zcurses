#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2
typeset -i short_max=$3
zmodload zsh/curses || exit 1

fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
cell() {
  local -a reply
  check zcurses move sample "$1" "$2"
  check zcurses querychar sample reply
  [[ $reply[1] == "$3" ]] || fail "cell $1,$2: ${(V)reply[1]} != ${(V)3}"
}

check zcurses init
{
  check zcurses addwin sample 5 12 1 1
  if [[ $mode == exhaustion ]]; then
    typeset -i limit=$(( ZCURSES_COLOR_PAIRS - 1 )) i f b
    (( limit > short_max )) && limit=$short_max
    (( limit > 0 && ZCURSES_COLORS * ZCURSES_COLORS >= limit )) || fail 'insufficient palette for exhaustion fixture'
    typeset pair last_pair
    for (( i=0; i<limit; i++ )); do
      f=$(( i / ZCURSES_COLORS )) b=$(( i % ZCURSES_COLORS ))
      pair=$f/$b
      check zcurses attr sample "$pair"
      if (( i == 0 )); then
        check zcurses string sample A
      fi
    done
    last_pair=$pair
    # A new spelling requires a new pair; failure must not corrupt old cells
    # or prevent reuse of an already allocated pair.
    reject zcurses attr sample 0000/0000
    check zcurses attr sample "$last_pair"
    check zcurses move sample 0 0
    typeset -a reply
    check zcurses querychar sample reply
    [[ $reply[1] == A && $reply[2] == 0/0 ]] || fail 'exhaustion changed a retained cell'
  else
    check zcurses attr sample bold green/black
    check zcurses move sample 2 2
    check zcurses string sample inside
    check zcurses move sample 2 3
    typeset -a before after reply
    check zcurses position sample before
    check zcurses border sample L R T B 1 2 3 4
    check zcurses position sample after
    [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'border moved cursor'
    cell 0 0 1; cell 0 11 2; cell 4 0 3; cell 4 11 4
    cell 1 0 L; cell 1 11 R; cell 0 1 T; cell 4 1 B
    cell 2 2 i
    check zcurses move sample 0 0
    check zcurses querychar sample reply
    [[ $reply[2] == green/black && ${reply[(Ie)bold]} -gt 0 ]] || fail 'border attributes'
    check zcurses move sample 3 3
    check zcurses string sample X
    check zcurses move sample 3 3
    check zcurses querychar sample reply
    [[ $reply[2] == green/black && ${reply[(Ie)bold]} -gt 0 ]] || fail 'border changed window attributes'

    # Invalid arguments must leave the whole perimeter unchanged. Put the bad
    # glyph last to catch implementations that draw as they validate.
    typeset bad
    for bad in ab $'\n' $'\t' $'\e' $'\x7f'; do
      reject zcurses border sample a b c d e f g "$bad"
      cell 0 0 1; cell 0 11 2; cell 4 0 3; cell 4 11 4
    done
    reject zcurses border sample a
    reject zcurses border sample a b c d e f g
    reject zcurses border sample a b c d e f g h i
    reject zcurses border missing a b c d e f g h

    # Empty glyphs select the library's defaults; spaces remain blank cells.
    check zcurses border sample
    check zcurses move sample 0 0
    check zcurses querychar sample before
    check zcurses border sample '' '' '' '' '' '' '' ''
    check zcurses querychar sample after
    # Narrow ACS may read back as its mapped ASCII code, while wide curses
    # stores the corresponding Unicode character. Both are library defaults.
    if [[ $mode == wide ]]; then
      [[ $after[1] == '┌' ]] || fail 'wide empty glyph default'
    else
      [[ "${(j: :)before}" == "${(j: :)after}" ]] || fail 'empty glyph default'
    fi
    check zcurses border sample ' ' ' ' ' ' ' ' ' ' ' ' ' ' ' '
    cell 0 0 ' '; cell 0 1 ' '; cell 4 11 ' '
    check zcurses bg sample @.
    check zcurses border sample ' ' ' ' ' ' ' ' ' ' ' ' ' ' ' '
    cell 0 0 .; cell 4 11 .
    check zcurses bg sample '@ '

    check zcurses addwin tiny 1 4 7 1
    reject zcurses border tiny a b c d e f g h
    check zcurses delwin tiny
    check zcurses addwin tiny 4 1 7 1
    reject zcurses border tiny a b c d e f g h
    check zcurses delwin tiny
    check zcurses addwin tiny 2 2 7 1
    check zcurses border tiny a b c d e f g h
    check zcurses delwin tiny

    if [[ $mode == wide ]]; then
      (( ${zcurses_features[(Ie)wide_borders]} )) || fail 'missing wide borders'
      check zcurses border sample '│' '│' '─' '─' '╭' '╮' '╰' '╯'
      cell 0 0 '╭'; cell 0 11 '╮'; cell 4 0 '╰'; cell 4 11 '╯'
      cell 1 0 '│'; cell 0 1 '─'
      for bad in $'\u0301' $'e\u0301' '界' $'\xff' $'\xc3'; do
        reject zcurses border sample a b c d e f g "$bad"
        cell 0 0 '╭'; cell 4 11 '╯'
      done
      # These UTF-8 characters contain bytes that Zsh internally metafies.
      typeset glyph
      for glyph in '┌' 'é' '界' A; do
        check zcurses move sample 2 1
        check zcurses char sample "$glyph"
        cell 2 1 "$glyph"
      done
      reject zcurses char sample ''
      reject zcurses char sample $'\0'
      reject zcurses char sample $'\xff'
      check zcurses move sample 2 1
      check zcurses char sample AB
      cell 2 1 A
      check zcurses move sample 2 1
      check zcurses string sample $'e\u0301\u0327'
      # querychar retains its first-character result, while the buffer must
      # accommodate the whole complex character and its terminator.
      cell 2 1 e
    else
      (( ! ${zcurses_features[(Ie)wide_borders]} )) || fail 'unexpected wide borders'
      zcurses border sample a b c d e f g '╯' 2>/dev/null
      (( $? == 2 )) || fail 'missing unsupported-wide status'
    fi

    typeset invalid
    for invalid in 1x/0 0/1x 999999999999999999999999/0 0/99999999999999999999999 /0 0/ 0/0/0 -1/0 "$ZCURSES_COLORS/0" "$((short_max+1))/0"; do
      reject zcurses attr sample "$invalid"
    done
    check zcurses attr sample "$((ZCURSES_COLORS-1))/0"
    check zcurses attr sample default/default
    check zcurses refresh sample
  fi
  check zcurses delwin sample
} always {
  zcurses end
}
check zcurses init
check zcurses attr stdscr red/black
check zcurses end
print -r -- 'DRAWING PASS'
