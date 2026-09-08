#!/usr/bin/env zsh
# Run through spans.py so the staged shell has a controlled PTY.
emulate -R zsh
setopt errexit nounset
module_path=("$1")
typeset backend=$2 scenario=$3 report_fd=$5
typeset -i frames=$4 frame row segment
zmodload zsh/curses
(( ${zcurses_features[(Ie)styled_spans]} ))
typeset -a texts=(12345678 abcdefgh 12345678 abcdefgh 12345678 abcdefgh 12345678 abcdefgh)
typeset -a attributes=(bold -bold bold -bold bold -bold bold -bold)
typeset -a colors=(red/black blue/black red/black blue/black red/black blue/black red/black blue/black)
typeset -a batch
for (( segment=1; segment<=8; segment++ )); do
  if [[ $attributes[segment] == bold ]]; then
    batch+=("bold,$colors[segment]" "$texts[segment]")
  else
    batch+=("$colors[segment]" "$texts[segment]")
  fi
done
legacy() {
  local -i row segment
  for (( row=0; row<20; row++ )); do
    zcurses move sample "$row" 0
    for (( segment=1; segment<=8; segment++ )); do
      zcurses attr sample "$attributes[segment]" "$colors[segment]"
      zcurses string sample "$texts[segment]"
    done
    zcurses attr sample -bold default/default
    zcurses move sample 0 0
  done
}
spans() {
  local -i row
  for (( row=0; row<20; row++ )); do
    zcurses spans sample "$row" 0 "${batch[@]}"
  done
}
typeset -F 9 SECONDS elapsed
zcurses init
{
  zcurses addwin sample 20 70 0 0
  # Allocate before timing. In particular, make pair 0 reusable by attr.
  zcurses attr sample red/black blue/black default/default
  for (( frame=0; frame<25; frame++ )); do
    "$backend"
  done
  zcurses refresh sample
  SECONDS=0
  for (( frame=0; frame<frames; frame++ )); do
    # Change one column of each segment so refresh has real work every frame.
    if (( frame % 2 )); then
      texts[1]=X2345678 batch[2]=X2345678
    else
      texts[1]=12345678 batch[2]=12345678
    fi
    "$backend"
    if [[ $scenario == refresh ]]; then
      zcurses refresh sample
    fi
  done
  elapsed=$SECONDS
} always {
  zcurses end
}
print -r -u "$report_fd" -- "$elapsed"
