#!/usr/bin/env zsh
# Move an independent window with arrows; +/- resize it; q exits.
emulate -R zsh
setopt errexit nounset
module_path=("${0:A:h:h}/.build/modules")
zmodload zdraw
(( ${zdraw_features[(Ie)window_movement]} && ${zdraw_features[(Ie)window_resize]} &&
   ${zdraw_features[(Ie)region_fill]} && ${zdraw_features[(Ie)clipped_spans]} ))
typeset -a dimensions geometry input_options
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)
typeset -A event
typeset -i rows cols y=2 x=3 height=5 width=28 dirty=1 rebuild=0 visible=0
zdraw init
{
  zdraw timeout stdscr 100
  while true; do
    if (( dirty )); then
      zdraw position stdscr dimensions
      rows=$dimensions[5] cols=$dimensions[6]
      visible=$(( rows >= 5 && cols >= 12 ))
      if (( visible )); then
        (( height < 3 )) && height=3
        (( width < 12 )) && width=12
        (( height > rows - 2 )) && height=$(( rows - 2 ))
        (( width > cols )) && width=$cols
        (( y < 1 )) && y=1
        (( x < 0 )) && x=0
        (( y > rows - height - 1 )) && y=$(( rows - height - 1 ))
        (( x > cols - width )) && x=$(( cols - width ))
        rebuild=0
        if (( ! ${zdraw_windows[(Ie)floating]} )); then
          zdraw addwin floating "$height" "$width" "$y" "$x"
          rebuild=1
        else
          zdraw position floating geometry
          if (( geometry[5] != height || geometry[6] != width )); then
            zdraw resizewin floating "$height" "$width" "$y" "$x"
            rebuild=1
          elif (( geometry[3] != y || geometry[4] != x )); then
            zdraw movewin floating "$y" "$x"
          fi
        fi
        if (( rebuild )); then
          zdraw fill floating 0 0 "$height" "$width" reverse ' '
          zdraw attr floating bold reverse
          zdraw border floating
          zdraw spansclip floating 1 1 "$(( width - 2 ))" bold,reverse 'Retained floating window'
          if (( height > 3 )); then
            zdraw spansclip floating 2 1 "$(( width - 2 ))" reverse 'Moving keeps these cells'
          fi
        fi
      elif (( ${zdraw_windows[(Ie)floating]} )); then
        zdraw delwin floating
      fi
      # Recompose the background to erase the window's previous footprint.
      zdraw fill stdscr 0 0 "$rows" "$cols" dim .
      zdraw spansclip stdscr 0 0 "$cols" bold 'Windows - arrows move, +/- resize, q quits'
      if (( rows > 1 )); then
        zdraw spansclip stdscr "$(( rows - 1 ))" 0 "$cols" '' \
          "Origin $y,$x | size ${height}x${width}"
      fi
      zdraw stage stdscr
      (( visible )) && zdraw stage floating
      zdraw present
      dirty=0
    fi
    if zdraw event stdscr event "${input_options[@]}"; then
      case $event[type] in
        character)
          case $event[text] in
            q) break ;;
            '+') height=$(( height + 1 )); width=$(( width + 2 )); dirty=1 ;;
            '-') height=$(( height - 1 )); width=$(( width - 2 )); dirty=1 ;;
          esac ;;
        key)
          case $event[key] in
            UP) y=$(( y - 1 )); dirty=1 ;;
            DOWN) y=$(( y + 1 )); dirty=1 ;;
            LEFT) x=$(( x - 1 )); dirty=1 ;;
            RIGHT) x=$(( x + 1 )); dirty=1 ;;
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
