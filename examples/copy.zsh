#!/usr/bin/env zsh
# Scroll retained rows; render only the newly exposed line. q exits.
emulate -R zsh
setopt errexit nounset
module_path=("${0:A:h:h}/.build/modules")
zmodload zdraw
(( ${zdraw_features[(Ie)region_copy]} && ${zdraw_features[(Ie)region_fill]} ))
typeset -a dimensions input_options
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)
typeset -A event
typeset -i rows columns first=1 row reset=1 direction=0
line() {
  emulate -L zsh
  local -i y=$1 number=$2
  local style=''
  (( number % 2 )) && style=reverse
  zdraw fill stdscr "$y" 0 1 "$columns" "$style" ' ' || return
  zdraw spansclip stdscr "$y" 0 "$columns" "$style" "Retained row $number"
}
zdraw init
{
  zdraw timeout stdscr 100
  while true; do
    if (( reset )); then
      zdraw position stdscr dimensions
      rows=$dimensions[5] columns=$dimensions[6]
      zdraw fill stdscr 0 0 "$rows" "$columns" '' ' '
      zdraw spansclip stdscr 0 0 "$columns" bold 'Copy - up/down scroll, q quits'
      for (( row=1; row<rows; row++ )); do
        line "$row" "$(( first + row - 1 ))"
      done
      reset=0
      zdraw refresh stdscr
    elif (( direction && rows > 1 )); then
      if (( rows > 2 )); then
        if (( direction > 0 )); then
          zdraw copy stdscr 2 0 stdscr 1 0 "$(( rows - 2 ))" "$columns"
        else
          zdraw copy stdscr 1 0 stdscr 2 0 "$(( rows - 2 ))" "$columns"
        fi
      fi
      if (( direction > 0 )); then
        line "$(( rows - 1 ))" "$(( first + rows - 2 ))"
      else
        line 1 "$first"
      fi
      zdraw refresh stdscr
    fi
    direction=0
    if zdraw event stdscr event "${input_options[@]}"; then
      case $event[type] in
        character) [[ $event[text] == q ]] && break ;;
        key)
          case $event[key] in
            DOWN) first=$(( first + 1 )); direction=1 ;;
            UP)
              if (( first > 1 )); then
                first=$(( first - 1 )); direction=-1
              fi ;;
          esac ;;
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
