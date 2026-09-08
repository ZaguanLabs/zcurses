#!/usr/bin/env zsh
# Run with the shell built alongside the module; see README.md.
emulate -R zsh
setopt errexit nounset
module_path=("${1:-${0:A:h:h}/.build/modules}")
zmodload zsh/curses
if ! zmodload -F -e zsh/curses +p:zcurses_features ||
   (( ! ${zcurses_features[(Ie)custom_borders]} )); then
  print -ru2 -- 'This example requires custom border support.'
  exit 1
fi
typeset -a size
zcurses geometry size
if (( size[1] < 19 || size[2] < 50 )); then
  print -ru2 -- 'This example needs at least 19 rows and 50 columns.'
  exit 1
fi
zcurses init
{
  typeset -a glyphs
  typeset label name key
  typeset -i index
  for index in 1 2 3; do
    name=border$index
    zcurses addwin "$name" 5 48 "$((1 + (index-1)*6))" 1
    # Color is optional; borders also work on monochrome terminals.
    zcurses attr "$name" cyan/black 2>/dev/null || true
    case $index in
      1) glyphs=('|' '|' '-' '-' '+' '+' '+' '+'); label='ASCII borders' ;;
      2) glyphs=('│' '│' '─' '─' '╭' '╮' '╰' '╯'); label='Rounded borders' ;;
      3) glyphs=('║' '║' '═' '═' '╔' '╗' '╚' '╝'); label='Double borders' ;;
    esac
    if (( index == 1 || ${zcurses_features[(Ie)wide_borders]} )); then
      zcurses border "$name" "${glyphs[@]}"
    else
      zcurses border "$name"
      label='Curses defaults (wide borders unavailable)'
    fi
    zcurses move "$name" 2 2
    zcurses attr "$name" bold
    zcurses string "$name" "$label"
  done
  zcurses move stdscr 18 2
  zcurses string stdscr 'Press any key to exit.'
  zcurses refresh stdscr border1 border2 border3
  zcurses input stdscr key
} always {
  zcurses end
}
