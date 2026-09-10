#!/usr/bin/env zsh
# Private-terminal probe only: owns drawing/input until its Python driver acks.
emulate -R zsh
setopt nounset
typeset root=${0:A:h:h:h} directory=$1 name text acknowledgement key
typeset -i row=2 code width
module_path=("$root/.build/modules")
zmodload zdraw || exit 1
typeset -A measured unit snapshot
check() { "$@" || exit 1; }
check zdraw init
{
  check zdraw spans stdscr 0 0 bold 'NATIVE CELLS | Unicode 17 corpus | marker follows measured width'
  while IFS=$'\t' read -r name text; do
    measured=() unit=()
    zdraw textinfo measured "$text" 50 grapheme 2>/dev/null
    code=$?
    width=${measured[width]:-0}
    print -r -- "$name"$'\t'"query_status"$'\t'"$code"$'\n'"$name"$'\t'"width"$'\t'"$width" >> "$directory/native.tsv"
    check zdraw spans stdscr "$row" 0 '' "$name"
    if (( ! code )); then
      zdraw spans stdscr "$row" 24 '' "$text" 2>/dev/null
      code=$?
      print -r -- "$name"$'\t'"draw_status"$'\t'"$code" >> "$directory/native.tsv"
      if (( code )); then check zdraw spans stdscr "$row" 24 '' '<draw rejected>'
      else check zdraw spans stdscr "$row" "$((24+width))" '' '|'; fi
    else check zdraw spans stdscr "$row" 24 '' '<query rejected>'; fi
    (( row++ ))
  done < "$directory/corpus.tsv"
  check zdraw snapshot stdscr snapshot
  for key in "${(@ok)snapshot}"; do
    print -r -- "$key"$'\t'"$snapshot[$key]" >> "$directory/snapshot.tsv"
  done
  check zdraw refresh stdscr
  print -r -- native > "$directory/phase"
  read -r acknowledgement < "$directory/ack" || exit 1
} always {
  zdraw end || exit 1
}
