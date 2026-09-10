#!/usr/bin/env zsh
# Reflow a paragraph while keeping selection attached to a source byte.
emulate -R zsh
setopt errexit nounset
module_path=("${0:A:h:h}/.build/modules")
zmodload zdraw
(( ${zdraw_features[(Ie)text_wrapping]} && ${zdraw_features[(Ie)clipped_spans]} &&
   ${zdraw_features[(Ie)region_fill]} && ${zdraw_features[(Ie)staged_refresh]} ))
typeset paragraph='A wrapped row is a view of the original text. Change the width and the selected source position stays in view. Applications can use the same byte ranges for search results, diagnostics, selection and navigation. Spaces are preserved exactly, including these  two spaces. This example wraps by columns; words may continue on the next row.'
typeset -A wrapped event probe
if (( ${zdraw_features[(Ie)wide_spans]} && ${zdraw_features[(Ie)wide_text]} )) &&
   zdraw textinfo probe 'Café 界 ă' 2>/dev/null; then
  paragraph+=' Combining suffixes stay with their base: Café. A wide character such as 界 occupies two columns.'
fi
typeset -a dimensions input_options
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)
typeset -i preferred=40 budget rows cols visible row screen_row
typeset -i selected=0 anchor=0 top=0 dirty=1 count=1
zdraw init
{
  zdraw timeout stdscr 100
  while true; do
    if (( dirty )); then
      zdraw position stdscr dimensions
      rows=$dimensions[5] cols=$dimensions[6]
      zdraw fill stdscr 0 0 "$rows" "$cols" '' ' '
      zdraw spansclip stdscr 0 0 "$cols" bold 'Wrapped text - +/- width, arrows select a row, q quits'
      visible=$(( rows > 2 && cols >= 2 ? rows - 2 : 0 ))
      if (( visible )); then
        budget=$(( preferred < cols ? preferred : cols ))
        zdraw textwrap wrapped "$paragraph" "$budget"
        count=$wrapped[line_count]
        # Preserve the source anchor when a width change moves row boundaries.
        for (( row=0; row<count; row++ )); do
          if (( anchor >= wrapped[$row,byte_start] && anchor < wrapped[$row,byte_end] )); then
            selected=$row
            break
          fi
        done
        (( top > selected )) && top=$selected
        (( selected >= top + visible )) && top=$(( selected - visible + 1 ))
        (( top > count - visible )) && top=$(( count > visible ? count - visible : 0 ))
        for (( row=top; row<count && row<top+visible; row++ )); do
          screen_row=$(( row - top + 1 ))
          if (( row == selected )); then
            zdraw spans stdscr "$screen_row" 0 reverse "$wrapped[$row,text]"
          else
            zdraw spans stdscr "$screen_row" 0 '' "$wrapped[$row,text]"
          fi
        done
        zdraw spansclip stdscr "$(( rows - 1 ))" 0 "$cols" reverse \
          "Row $(( selected + 1 ))/$count | bytes [$wrapped[$selected,byte_start],$wrapped[$selected,byte_end]) | width $budget"
      fi
      zdraw stage stdscr
      zdraw present
      dirty=0
    fi
    if zdraw event stdscr event "${input_options[@]}"; then
      case $event[type] in
        character)
          case $event[text] in
            q) break ;;
            +) (( preferred < 160 )) && preferred=$(( preferred + 1 )); dirty=1 ;;
            -) (( preferred > 2 )) && preferred=$(( preferred - 1 )); dirty=1 ;;
          esac ;;
        key)
          if (( visible )); then
            case $event[key] in
              UP) (( selected > 0 )) && selected=$(( selected - 1 )) ;;
              DOWN) (( selected + 1 < count )) && selected=$(( selected + 1 )) ;;
            esac
            anchor=$wrapped[$selected,byte_start] dirty=1
          fi ;;
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
