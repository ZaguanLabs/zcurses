#!/usr/bin/env zsh
# Pan a retained document, grow/truncate it, and toggle a window overlay.
emulate -R zsh
setopt errexit nounset
module_path=("${0:A:h:h}/.build/modules")
zmodload zdraw
(( ${zdraw_features[(Ie)pad_resize]} && ${zdraw_features[(Ie)region_fill]} &&
   ${zdraw_features[(Ie)clipped_spans]} && ${zdraw_features[(Ie)staged_refresh]} ))
typeset -a dimensions input_options
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)
typeset -A event
typeset -i rows cols viewrows viewcols top=0 left=0 dirty=1 popup=0 new_rows
# These are application data limits; the module reports its own limits in docs.
typeset -i document_rows=200 document_cols=120
populate_rows() {
  emulate -L zsh
  local -i row
  local label style
  for (( row=$1; row<$2; row++ )); do
    style=''
    (( row % 2 )) && style=dim
    printf -v label '%04d | Retained document row | column 32: source data | column 57: notes and details | Pan right to explore the wider surface' "$(( row + 1 ))"
    zdraw spansclip document "$row" 0 "$document_cols" "$style" "$label" || return
  done
}
zdraw init
{
  zdraw addpad document "$document_rows" "$document_cols"
  populate_rows 0 "$document_rows"
  zdraw timeout stdscr 100
  while true; do
    if (( dirty )); then
      zdraw position stdscr dimensions
      rows=$dimensions[5] cols=$dimensions[6]
      viewrows=$(( rows > 2 ? rows - 2 : 0 ))
      (( viewrows > document_rows )) && viewrows=$document_rows
      viewcols=$(( cols < document_cols ? cols : document_cols ))
      (( top < 0 )) && top=0
      (( left < 0 )) && left=0
      (( top > document_rows - viewrows )) && top=$(( document_rows - viewrows ))
      (( left > document_cols - viewcols )) && left=$(( document_cols - viewcols ))
      if (( ${zdraw_windows[(Ie)overlay]} )); then
        zdraw delwin overlay
      fi
      zdraw fill stdscr 0 0 "$rows" "$cols" '' ' '
      zdraw spansclip stdscr 0 0 "$cols" bold 'Viewports - arrows pan, +/- rows, space overlays, q quits'
      if (( rows > 1 )); then
        zdraw spansclip stdscr "$(( rows - 1 ))" 0 "$cols" reverse \
          "Origin $top,$left | surface ${document_rows}x${document_cols} | view ${viewrows}x${viewcols}"
      fi
      zdraw stage stdscr
      if (( viewrows )); then
        zdraw viewport document "$top" "$left" 1 0 "$viewrows" "$viewcols"
      fi
      if (( popup && rows >= 7 && cols >= 28 )); then
        zdraw addwin overlay 3 26 "$(( (rows - 3) / 2 ))" "$(( (cols - 26) / 2 ))"
        zdraw border overlay
        zdraw spans overlay 1 1 bold 'Overlay (space closes)'
        zdraw stage overlay
      fi
      zdraw present
      dirty=0
    fi
    if zdraw event stdscr event "${input_options[@]}"; then
      case $event[type] in
        character)
          [[ $event[text] == q ]] && break
          if [[ $event[text] == ' ' ]]; then
            popup=$(( ! popup )); dirty=1
          elif [[ $event[text] == + && $document_rows -lt 400 ]]; then
            new_rows=$(( document_rows + 20 ))
            zdraw resizepad document "$new_rows" "$document_cols"
            # Populate only newly allocated rows; retained drawing is untouched.
            populate_rows "$document_rows" "$new_rows"
            document_rows=$new_rows
            top=$document_rows dirty=1
          elif [[ $event[text] == - && $document_rows -gt 20 ]]; then
            document_rows=$(( document_rows - 20 ))
            zdraw resizepad document "$document_rows" "$document_cols"
            dirty=1
          fi ;;
        key)
          case $event[key] in
            UP) top=$(( top - 1 )); dirty=1 ;;
            DOWN) top=$(( top + 1 )); dirty=1 ;;
            LEFT) left=$(( left - 4 )); dirty=1 ;;
            RIGHT) left=$(( left + 4 )); dirty=1 ;;
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
