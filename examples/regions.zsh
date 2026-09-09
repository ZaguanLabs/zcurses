#!/usr/bin/env zsh
# Move a filled region with arrows; space changes its tile; q exits.
emulate -R zsh
setopt errexit nounset
module_path=("${0:A:h:h}/.build/modules")
zmodload zdraw
(( ${zdraw_features[(Ie)region_fill]} && ${zdraw_features[(Ie)prepared_rows]} ))
typeset -a dimensions input_options
if (( ${zdraw_features[(Ie)norefresh_events]} )); then
  input_options+=(norefresh)
fi
typeset -A event
typeset -i box_y=2 box_x=2 rows columns dirty=1
typeset tile=' '
zdraw init
{
  zdraw prepare heading bold 'Regions - arrows move, space changes tile, q quits'
  zdraw prepare label bold,reverse 'zdraw region'
  zdraw timeout stdscr 100
  while true; do
    if (( dirty )); then
      zdraw position stdscr dimensions
      rows=$dimensions[5] columns=$dimensions[6]
      zdraw fill stdscr 0 0 "$rows" "$columns" dim .
      zdraw draw stdscr 0 0 heading "$columns"
      if (( rows >= 7 && columns >= 20 )); then
        (( box_y < 2 )) && box_y=2
        (( box_y > rows - 4 )) && box_y=$(( rows - 4 ))
        (( box_x < 0 )) && box_x=0
        (( box_x > columns - 16 )) && box_x=$(( columns - 16 ))
        zdraw fill stdscr "$box_y" "$box_x" 4 16 reverse "$tile"
        zdraw draw stdscr "$(( box_y + 1 ))" "$(( box_x + 1 ))" label
      fi
      zdraw refresh
      dirty=0
    fi
    if zdraw event stdscr event "${input_options[@]}"; then
      case $event[type] in
        character)
          [[ $event[text] == q ]] && break
          if [[ $event[text] == ' ' ]]; then
            [[ $tile == ' ' ]] && tile='#' || tile=' '
            dirty=1
          fi ;;
        key)
          case $event[key] in
            UP) box_y=$(( box_y - 1 )); dirty=1 ;;
            DOWN) box_y=$(( box_y + 1 )); dirty=1 ;;
            LEFT) box_x=$(( box_x - 1 )); dirty=1 ;;
            RIGHT) box_x=$(( box_x + 1 )); dirty=1 ;;
          esac ;;
        resize)
          if (( ${zdraw_features[(Ie)resize]} )); then
            zdraw resize "$event[rows]" "$event[columns]" nosave
          fi
          dirty=1 ;;
      esac
    fi
  done
} always {
  zdraw end
}
