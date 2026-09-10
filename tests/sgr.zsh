emulate -R zsh
setopt nounset
module_path=("$1")
zmodload zdraw || exit 1
source "${0:A:h:h}/lib/zdraw-sgr.zsh"
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" && fail "unexpected success: $*"; return 0; }
typeset -A zdraw_sgr_state
typeset -a reply expected combined
typeset input=$'plain\e[1;31mRED\e[22;39m normal\n\e[38;5;202;48;2;1;2;3mX\e[0m\tZ\r'
check zdraw-sgr-feed "$input" final
expected=(text '' plain text bold,1/default RED text '' ' normal' newline '' ''
          text '202/#010203' X tab '' '' text '' Z carriage_return '' '')
[[ "${(j:|:)reply}" == "${(j:|:)expected}" && ${#zdraw_sgr_state} == 0 ]] || fail 'styles and controls'
typeset -i split
typeset first second
for (( split=0; split<=${#input}; split++ )); do
  first=${input[1,$split]} second=${input[$(( split + 1 )),-1]}
  (( split )) || first=''
  (( split < ${#input} )) || second=''
  combined=()
  check zdraw-sgr-feed "$first"
  combined+=("${reply[@]}")
  check zdraw-sgr-feed "$second" final
  combined+=("${reply[@]}")
  [[ "${(j:|:)combined}" == "${(j:|:)expected}" ]] || fail "split $split"
done
# OSC, DCS, APC, CSI cursor/erase commands and controls never reach text.
input=$'A\e]52;c;clipboard\aB\ePprivate\e\\C\e_secret\e\\D\e[2J\e[999mE\0\a\bF'
check zdraw-sgr-feed "$input" final
typeset plain=''
for (( split=1; split<=${#reply}; split+=3 )); do plain+=$reply[$(( split + 2 ))]; done
[[ $plain == ABCDEF ]] || fail 'control filtering'
check zdraw-sgr-feed $'x\e]secret'
check zdraw-sgr-feed $'more\e'
check zdraw-sgr-feed $'\\y' final
[[ "${(j:|:)reply}" == 'text||y' ]] || fail 'split ST'
# Rejected chunks publish neither partial output nor new parser state.
check zdraw-sgr-feed 'retained'
reply=(sentinel)
reject zdraw-sgr-feed $'\ninvalid\xff' final
[[ $zdraw_sgr_state[text] == retained && $reply == sentinel ]] || fail 'failure isolation'
check zdraw-sgr-feed $' good\n' final
[[ $reply[3] == 'retained good' ]] || fail 'retry'
typeset pad='' huge
huge=${(pl:65536::x:)pad}
check zdraw-sgr-feed "$huge"
reply=(sentinel)
reject zdraw-sgr-feed x
[[ ${#zdraw_sgr_state[text]} == 65536 && $reply == sentinel ]] || fail 'text bound'
check zdraw-sgr-feed '' final
reject zdraw-sgr-feed "${huge}x"
check zdraw-sgr-feed $'\e[1;38;9;31mX' final
[[ $reply[2] == '' ]] || fail 'malformed extended SGR changed style'
check zdraw-sgr-feed $'\e[31;mX' final
[[ $reply[2] == '' ]] || fail 'empty SGR parameter'
typeset too_many=${(pl:2049::\n:)pad}
reply=(sentinel)
reject zdraw-sgr-feed "$too_many" final
[[ $reply == sentinel && ${#zdraw_sgr_state} == 0 ]] || fail 'record bound'
input=$'ăe\u0301界'
byte_parts() { local LC_ALL=C; first=${input[1,$1]}; second=${input[$(( $1 + 1 )),-1]}; }
for split in 1 2 3 4 5 6 7; do
  byte_parts "$split"
  check zdraw-sgr-feed "$first"
  check zdraw-sgr-feed "$second" final
  [[ $reply[3] == "$input" ]] || fail 'UTF-8 split'
done
(( ${#zdraw_windows} == 0 )) || fail 'decoder initialized terminal'
print -r -- 'SGR PASS'
