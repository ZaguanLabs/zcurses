#!/usr/bin/env zsh
# Independent windows: Space hides/shows, r changes order, arrows move, q exits.
emulate -R zsh
setopt nounset
module_path=("${0:A:h:h}/.build/modules")
zmodload zdraw || exit 1
typeset -A event
typeset -a size input_options
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)
typeset -i visible=1 reverse_order=0 y=4 x=12 rows cols exit_code=0
zdraw init || exit 1
{
  zdraw timeout stdscr 100 || exit 1
  zdraw addwin lower 5 26 2 4 || exit 1
  zdraw addwin upper 5 26 "$y" "$x" || exit 1
  zdraw fill lower 0 0 5 26 reverse ' ' || exit 1
  zdraw spans lower 1 1 reverse,bold 'LOWER / retained' || exit 1
  zdraw fill upper 0 0 5 26 bold '#' || exit 1
  zdraw spans upper 1 1 bold 'UPPER / retained' || exit 1
  while true; do
    zdraw position stdscr size || break
    rows=$size[5] cols=$size[6]
    zdraw fill stdscr 0 0 "$rows" "$cols" dim . || break
    zdraw spansclip stdscr 0 0 "$cols" '' 'Space hide / r order / arrows move / q quit' || break
    # Always restore the background, then all visible surfaces bottom to top.
    zdraw stage stdscr || break
    if (( rows >= 10 && cols >= 40 )); then
      (( y < 1 )) && y=1
      (( x < 0 )) && x=0
      (( y > rows-5 )) && y=$((rows-5))
      (( x > cols-26 )) && x=$((cols-26))
      zdraw resizewin lower 5 26 2 4 || break
      zdraw resizewin upper 5 26 "$y" "$x" || break
      if (( visible && reverse_order )); then zdraw stage upper lower || break
      else
        zdraw stage lower || break
        if (( visible )); then zdraw stage upper || break; fi
      fi
    fi
    zdraw present || break
    zdraw event stdscr event "${input_options[@]}" || continue
    case $event[type]:${event[key]-}:$event[text] in
      character::q|character::$'\e') break ;;
      'character:: ') visible=$((!visible)) ;;
      character::r) reverse_order=$((!reverse_order)) ;;
      key:UP:) (( y-- )) ;; key:DOWN:) (( y++ )) ;;
      key:LEFT:) (( x-- )) ;; key:RIGHT:) (( x++ )) ;;
      resize:*) zdraw resize "$event[rows]" "$event[columns]" nosave || break ;;
    esac
  done
} always {
  zdraw end || exit_code=1
}
exit "$exit_code"
