#!/usr/bin/env zsh
# Compare retained drawing without presenting it, then print readable changes.
emulate -R zsh
setopt errexit nounset
module_path=("${0:A:h:h}/.build/modules")
zmodload zdraw
(( ${zdraw_features[(Ie)window_snapshots]} && ${zdraw_features[(Ie)styled_spans]} ))
typeset -A before after
typeset field
zdraw init
{
  zdraw addwin sample 2 8 0 0
  zdraw spans sample 0 0 bold ABC
  zdraw snapshot sample before
  zdraw spans sample 0 1 reverse Z
  zdraw snapshot sample after
} always {
  zdraw end
}
# Keep diagnostics such as session-specific pair IDs out of this comparison.
# Quoting prevents a stored control value from becoming terminal output.
for field in "${(@ok)after}"; do
  case $field in
    *,text|*,attributes|*,color)
      if [[ $before[$field] != "$after[$field]" ]]; then
        print -r -- "$field: ${(qqqq)before[$field]} -> ${(qqqq)after[$field]}"
      fi ;;
  esac
done
