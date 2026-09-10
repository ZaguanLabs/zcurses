#!/usr/bin/env zsh
# Shared views and retained overlays; all stacking and clipping policy stays here.
emulate -R zsh
setopt nounset
typeset overlay_root=${0:A:h:h}
[[ $# == 0 || ( $# == 1 && $1 == --sync ) ]] || { print -ru2 -- 'usage: overlays.zsh [--sync]'; exit 1; }
module_path=("$overlay_root/.build/modules")
zmodload zdraw || exit 1
typeset -a dimensions geometry input_options example_protocol_queue
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)
(( ${zdraw_features[(Ie)window_trees]} && ${zdraw_features[(Ie)transparent_copy]} )) || exit 2
[[ ${1:-} == --sync ]] && example_protocol_queue=(synchronized_output)
typeset example_protocol_current='' protocol_note=''
typeset -i example_keyboard_active=0
source "$overlay_root/examples/input-protocols.zsh" || exit 1
typeset -A event colors
typeset base_style=reverse top_style=bold note='Independent backing / shared child view'
typeset -i rows cols y=5 x=16 height=5 width=24 shown=1 transparent=1 reversed=0 moved=0 view=0 ready=0 dirty=1 exit_code=0
function overlay-compose {
  emulate -L zsh
  local win=$1 operation=$4
  local -i dy=$2 dx=$3 sr=0 sc=0 h w
  local -a box
  zdraw position "$win" box || return
  h=$box[5] w=$box[6]
  if (( dy < 0 )); then sr=$((-dy)); h=$((h+dy)); dy=0; fi
  if (( dx < 0 )); then sc=$((-dx)); w=$((w+dx)); dx=0; fi
  (( h > rows-dy )) && h=$((rows-dy))
  (( w > cols-dx )) && w=$((cols-dx))
  (( h > 0 && w > 0 )) || return 0
  zdraw "$operation" "$win" "$sr" "$sc" stdscr "$dy" "$dx" "$h" "$w"
}
function overlay-render {
  emulate -L zsh
  local -i by=$((1+moved)) bx=$((2+3*moved))
  local operation=copy
  (( transparent )) && operation=overlay
  zdraw position stdscr dimensions || return
  rows=$dimensions[5] cols=$dimensions[6]
  zdraw fill stdscr 0 0 "$rows" "$cols" dim . || return
  zdraw spansclip stdscr 0 0 "$cols" bold 'SURFACES / compose what is visible' || return
  if (( rows >= 12 && cols >= 42 )); then
    if (( !ready )); then
      zdraw addwin backing 7 32 "$by" "$bx" || return
      zdraw addwin shared 1 18 "$((by+3))" "$((bx+2))" backing || return
      zdraw addwin floating "$height" "$width" 0 0 || return
      ready=1
    fi
    zdraw treewin backing 7 32 "$by" "$bx" || return
    zdraw treewin shared 1 18 "$((by+3+view))" "$((bx+2))" || return
    zdraw resizewin floating "$height" "$width" 0 0 || return
    zdraw fill backing 0 0 7 32 "$base_style" ' ' || return
    zdraw spans backing 1 2 "$base_style" 'BACKING / shared cells' || return
    zdraw spans shared 0 0 "$base_style,bold" 'Child writes here' || return
    zdraw fill floating 0 0 "$height" "$width" '' ' ' || return
    zdraw spansclip floating 0 0 "$width" "$top_style" 'FLOATING / styled spaces' || return
    zdraw fill floating 1 0 1 "$width" "$top_style" ' ' || return
    zdraw spansclip floating 2 0 "$width" bold 'Plain spaces below are holes' || return
    if (( reversed )); then
      if (( shown )); then overlay-compose floating "$y" "$x" "$operation" || return; fi
      overlay-compose backing "$by" "$bx" copy || return
    else
      overlay-compose backing "$by" "$bx" copy || return
      if (( shown )); then overlay-compose floating "$y" "$x" "$operation" || return; fi
    fi
  else
    if (( ready )); then
      zdraw delwin shared && zdraw delwin backing && zdraw delwin floating || return
      ready=0
    fi
    if (( rows > 1 )); then zdraw spansclip stdscr 1 0 "$cols" '' 'Resize to 12x42 to explore' || return; fi
  fi
  if (( rows >= 3 )); then
    zdraw spansclip stdscr "$((rows-2))" 0 "$cols" dim "$note${protocol_note:+ / $protocol_note}" || return
    zdraw spansclip stdscr "$((rows-1))" 0 "$cols" '' 'Arrows move +/- size Space hide r order t holes c clip w tree v view f fail q quit' || return
  fi
  zdraw stage stdscr && zdraw present
}
zdraw init || exit 1
{
  zdraw colorinfo colors || exit 1
  if [[ $colors[colors] == <-> && $colors[colors] -ge 8 && -z ${NO_COLOR:-} ]]; then
    base_style=black/cyan top_style=black/yellow
  fi
  zdraw timeout stdscr 100 || exit 1
  example-protocol-next
  while true; do
    if (( dirty )); then overlay-render || { exit_code=1; break; }; dirty=0; fi
    zdraw event stdscr event "${input_options[@]}" || continue
    if example-protocol-event; then dirty=1; continue; fi
    case $event[type] in
      character)
        case $event[text] in
          q|$'\e') break ;;
          ' ') shown=$((!shown)) ;; r) reversed=$((!reversed)) ;; t) transparent=$((!transparent)) ;;
          c) y=-1 x=-8 ;; w) moved=$((!moved)) ;; v) view=$((!view)) ;;
          '+') (( height < 8 )) && (( height++ )); (( width < 36 )) && (( width+=2 )) ;;
          '-') (( height > 3 )) && (( height-- )); (( width > 20 )) && (( width-=2 )) ;;
          f)
            if (( ready )); then
              if zdraw treewin backing 1 1 0 0 2>/dev/null; then note='Unexpected geometry acceptance'
              else note='Rejected invalid geometry; live tree retained'; fi
            fi ;;
          *) continue ;;
        esac ;;
      key)
        case $event[key] in
          UP) (( y > -height )) && (( y-- )) ;; DOWN) (( y < rows )) && (( y++ )) ;;
          LEFT) (( x > -width )) && (( x-- )) ;; RIGHT) (( x < cols )) && (( x++ )) ;;
          *) continue ;;
        esac ;;
      resize) zdraw resize "$event[rows]" "$event[columns]" nosave || { exit_code=1; break; } ;;
      *) continue ;;
    esac
    dirty=1
  done
} always {
  zdraw end || exit_code=1
}
exit "$exit_code"
