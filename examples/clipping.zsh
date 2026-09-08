#!/usr/bin/env zsh
# Headless example: no curses init, controlling terminal, or screen update.
emulate -R zsh
setopt errexit nounset
module_path=("${1:-${0:A:h:h}/.build/modules}")
zmodload zsh/curses
if ! zmodload -F -e zsh/curses +p:zcurses_features ||
   (( ! ${zcurses_features[(Ie)textinfo]} )); then
  print -ru2 -- 'This example requires textinfo support.'
  exit 1
fi
typeset -A info
typeset text=$'A e\u0301 界 BC'
if ! zcurses textinfo info "$text" 2>/dev/null; then
  text='A simple ASCII example'
fi
print -r -- "Input: $text"
print -r -- 'Budget  Width  Prefix | Remainder (shell-quoted)'
typeset -i budget
for budget in 0 1 2 3 4 5 6 8 12; do
  zcurses textinfo info "$text" "$budget"
  printf '%-8d%-7d%q | %q\n' "$budget" "$info[width]" "$info[text]" "$info[remainder]"
done
