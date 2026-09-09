#!/usr/bin/env zsh
# Move a highlight over retained text; redraw the labels only after resizing.
emulate -R zsh
setopt errexit nounset
module_path=("${0:A:h:h}/.build/modules")
zmodload zdraw
(( ${zdraw_features[(Ie)region_restyle]} && ${zdraw_features[(Ie)clipped_spans]} ))
typeset -a dimensions input_options labels=(
  'Structured input events' 'Prepared styled rows' 'Complete cell snapshots'
  'Rectangle fills' 'Retained region copies' 'Text-preserving restyling'
)
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)
typeset -A event
typeset -i rows columns visible selected=1 previous=1 reset=1 dirty=0 row
zdraw init
{
  zdraw timeout stdscr 100
  while true; do
    if (( reset )); then
      zdraw position stdscr dimensions
      rows=$dimensions[5] columns=$dimensions[6]
      visible=$(( rows > 2 ? rows - 2 : 0 ))
      (( visible > ${#labels} )) && visible=${#labels}
      (( selected > visible )) && selected=$(( visible > 0 ? visible : 1 ))
      zdraw clear stdscr
      zdraw spansclip stdscr 0 0 "$columns" bold 'Restyle - retained text, moving highlight'
      if (( rows > 1 )); then
        zdraw spansclip stdscr 1 0 "$columns" '' 'Up/down move; q quits'
      fi
      for (( row=1; row<=visible; row++ )); do
        zdraw spansclip stdscr "$(( row + 1 ))" 0 "$columns" '' "$labels[$row]"
      done
      reset=0
      dirty=1
    fi
    if (( dirty )); then
      if (( visible )); then
        zdraw restyle stdscr "$(( selected + 1 ))" 0 1 "$columns" reverse,bold
      fi
      zdraw refresh stdscr
      dirty=0
    fi
    if zdraw event stdscr event "${input_options[@]}"; then
      case $event[type] in
        character) [[ $event[text] == q ]] && break ;;
        key)
          previous=$selected
          case $event[key] in
            UP) (( selected > 1 )) && selected=$(( selected - 1 )) ;;
            DOWN) (( selected < visible )) && selected=$(( selected + 1 )) ;;
          esac
          if (( previous != selected )); then
            zdraw restyle stdscr "$(( previous + 1 ))" 0 1 "$columns" ''
            dirty=1
          fi ;;
        resize)
          if (( ${zdraw_features[(Ie)resize]} )); then
            zdraw resize "$event[rows]" "$event[columns]" nosave
          fi
          reset=1 ;;
      esac
    fi
  done
} always {
  zdraw end
}
