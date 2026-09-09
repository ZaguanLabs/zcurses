#!/usr/bin/env zsh
# Inspect retained cells without presenting them. Run with the matching shell.
emulate -R zsh
setopt errexit nounset
module_path=("${0:A:h:h}/.build/modules")
zmodload zdraw
(( ${zdraw_features[(Ie)cell_inspection]} && ${zdraw_features[(Ie)prepared_rows]} ))
typeset -A cell probe
typeset -a records
# This literal remains parseable even in the C locale.
typeset text=abc
if (( ${zdraw_features[(Ie)wide_spans]} && ${zdraw_features[(Ie)wide_cell_inspection]} )); then
  if zdraw textinfo probe 'é界' 2>/dev/null; then
    text='é界'
  fi
fi
zdraw init
{
  zdraw addwin sample 1 4 0 0
  zdraw prepare label bold,underline "$text"
  zdraw draw sample 0 0 label
  for column in 0 1 2 3; do
    zdraw move sample 0 "$column"
    zdraw cellinfo sample cell
    records+=("$cell[row],$cell[column] text=${(qqqq)cell[text]} attributes=${(qqqq)cell[attributes]} color=${(qqqq)cell[color]}")
  done
} always {
  zdraw end
}
print -rl -- "${records[@]}"
