#!/usr/bin/env zsh
# Capture the session's color capabilities and budget; print after restoring tty.
emulate -R zsh
setopt errexit nounset
module_path=("${1:-${0:A:h:h}/.build/modules}")
zmodload zsh/curses
if ! zmodload -F -e zsh/curses +p:zcurses_features ||
   (( ! ${zcurses_features[(Ie)colorinfo]} )); then
  print -ru2 -- 'This example requires runtime color information.'
  exit 1
fi
typeset -A before active allocated ended
zcurses colorinfo before
zcurses init
{
  zcurses colorinfo active
  if [[ $active[color_started] == 1 ]] &&
     (( active[color_limit] > 0 && active[pairs_free] > 0 )); then
    zcurses attr stdscr 0/0
  fi
  zcurses colorinfo allocated
} always {
  zcurses end
}
zcurses colorinfo ended
printf '%-20s %12s %12s %12s %12s\n' field before-init after-init after-attr after-end
typeset key
for key in initialized has_colors color_started default_colors can_change_color \
           colors color_pairs color_limit pair_limit bg_pair_limit query_pair_limit \
           pairs_used pairs_free; do
  printf '%-20s %12s %12s %12s %12s\n' "$key" "$before[$key]" "$active[$key]" \
    "$allocated[$key]" "$ended[$key]"
done
