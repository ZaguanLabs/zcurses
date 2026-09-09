#!/usr/bin/env zsh
# Run through fill.py to use the matching shell and a controlled PTY.
emulate -R zsh
setopt errexit nounset
module_path=("$1")
typeset backend=$2 scenario=$3 report_fd=$5 empty=''
typeset -i frames=$4 frame active=1
typeset -a tiles=(X Y) texts
texts=("${(l:64::X:)empty}" "${(l:64::Y:)empty}")
zmodload zdraw
(( ${zdraw_features[(Ie)region_fill]} && ${zdraw_features[(Ie)prepared_rows]} ))
rows() {
  local -i row
  for (( row=0; row<20; row++ )); do
    zdraw spans sample "$row" 0 bold,red/black "$texts[active]"
  done
}
prepared() {
  local -i row
  for (( row=0; row<20; row++ )); do
    zdraw draw sample "$row" 0 "tile$active"
  done
}
fill() { zdraw fill sample 0 0 20 64 bold,red/black "$tiles[active]"; }
typeset -F 9 SECONDS elapsed
zdraw init
{
  zdraw addwin sample 20 64 0 0
  # Make setup/color allocation identical; row preparation is outside timing.
  zdraw prepare tile1 bold,red/black "$texts[1]"
  zdraw prepare tile2 bold,red/black "$texts[2]"
  for (( frame=0; frame<25; frame++ )); do
    active=$(( 1 + frame % 2 ))
    "$backend"
  done
  zdraw refresh sample
  SECONDS=0
  for (( frame=0; frame<frames; frame++ )); do
    active=$(( 1 + frame % 2 ))
    "$backend"
    if [[ $scenario == refresh ]]; then
      zdraw refresh sample
    fi
  done
  elapsed=$SECONDS
} always {
  zdraw end
}
print -r -u "$report_fd" -- "$elapsed"
