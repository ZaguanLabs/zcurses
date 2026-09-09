#!/usr/bin/env zsh
# Capture the session's color capabilities and budget; print after restoring tty.
emulate -R zsh
setopt errexit nounset
module_path=("${1:-${0:A:h:h}/.build/modules}")
zmodload zdraw
if ! zmodload -F -e zdraw +p:zdraw_features ||
   (( ! ${zdraw_features[(Ie)colorinfo]} )); then
  print -ru2 -- 'This example requires runtime color information.'
  exit 1
fi
typeset -A before active allocated ended
zdraw colorinfo before
zdraw init
{
  zdraw colorinfo active
  if [[ $active[color_started] == 1 ]] &&
     (( active[color_limit] > 0 && active[pairs_free] > 0 )); then
    zdraw attr stdscr 0/0
  fi
  zdraw colorinfo allocated
} always {
  zdraw end
}
zdraw colorinfo ended
printf '%-20s %12s %12s %12s %12s\n' field before-init after-init after-attr after-end
typeset key
for key in initialized has_colors color_started default_colors can_change_color \
           colors color_pairs color_limit pair_limit bg_pair_limit query_pair_limit \
           spans_pair_limit truecolor_supported truecolor_enabled rgb_min rgb_max \
           pairs_used pairs_free; do
  printf '%-20s %12s %12s %12s %12s\n' "$key" "$before[$key]" "$active[$key]" \
    "$allocated[$key]" "$ended[$key]"
done
