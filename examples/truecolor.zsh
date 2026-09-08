#!/usr/bin/env zsh
# Use the matching staged shell and a suitable direct-color TERM; see README.md.
emulate -R zsh
setopt errexit nounset
module_path=("${1:-${0:A:h:h}/.build/modules}")
zmodload zsh/curses
if ! zmodload -F -e zsh/curses +p:zcurses_features ||
   (( ! ${zcurses_features[(Ie)truecolor]} || ! ${zcurses_features[(Ie)styled_spans]} )); then
  print -ru2 -- 'This example requires truecolor and styled-span support.'
  exit 1
fi
typeset -a size gradient
typeset error='' color key
typeset -i index red blue
zcurses init
{
  zcurses position stdscr size
  if ! zcurses truecolor on; then
    error='Use a terminal with 24-bit RGB support and a matching direct-color TERM entry.'
  elif (( size[5] < 10 || size[6] < 54 )); then
    error='This example needs at least 10 rows and 54 columns.'
  else
    zcurses spans stdscr 1 2 'bold,#80c0ff/#181818' 'Truecolor through curses'
    for (( index=0; index<12; index++ )); do
      red=$((index*255/11)) blue=$((255-red))
      printf -v color '#%02x%02x%02x' "$red" 96 "$blue"
      gradient+=("$color/$color" '    ')
    done
    zcurses spans stdscr 3 2 "${gradient[@]}"
    zcurses spans stdscr 5 2 '#f08080/#181818' 'Warm ' '#80e0a0/#181818' 'green ' '#80c0ff/#181818' 'and blue'
    zcurses spans stdscr 7 2 '' 'Press any key to exit.'
    zcurses refresh stdscr
    zcurses input stdscr key
  fi
} always {
  zcurses end
}
if [[ -n $error ]]; then
  print -ru2 -- "$error"
  exit 1
fi
