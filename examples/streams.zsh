#!/usr/bin/env zsh
# One curses input owner, a colored worker pipe, bounded paste and foreground handoff.
emulate -R zsh
setopt errexit nounset
typeset root=${0:A:h:h}
module_path=("$root/.build/modules")
zmodload zdraw
zmodload zsh/zselect
zmodload zsh/system
source "$root/lib/zdraw-sgr.zsh"
source "$root/lib/zdraw-run.zsh"
(( ${zdraw_features[(Ie)streaming_paste]} && ${zdraw_features[(Ie)suspend_resume]} &&
   ${zdraw_features[(Ie)norefresh_events]} && ${zdraw_features[(Ie)input_delay]} ))
typeset -A event ready input_state zdraw_sgr_state colors
typeset -a reply geometry descriptors
typeset -i worker=-1 dirty=1 quitting=0 row=0 column=0 paste_bytes=0 count
typeset -i rows cols visible viewcols top read_status
typeset chunk worker_state=running paste_state=idle
foreground() {
  emulate -L zsh
  local line
  print -r -- 'Foreground command: ordinary terminal modes. Press Enter to return.'
  read -r line
}
draw_records() {
  emulate -L zsh
  local -i i
  local kind style text
  local -A measured
  for (( i=1; i<=${#reply}; i+=3 )); do
    kind=$reply[$i] style=$reply[$(( i + 1 ))] text=$reply[$(( i + 2 ))]
    case $kind in
      text)
        (( colors[has_colors] )) || style=''
        if (( column < 160 )); then
          zdraw textinfo measured "$text" "$(( 160 - column ))" || return
          zdraw spansclip log "$row" "$column" "$(( 160 - column ))" "$style" "$text" || return
          column=$(( column + measured[width] ))
        fi ;;
      newline)
        column=0 row=$(( row + 1 ))
        if (( row == 200 )); then zdraw scroll log 1 || return; row=199; fi ;;
      tab) column=$(( (column / 8 + 1) * 8 )) ;;
      carriage_return) column=0 ;;
    esac
  done
  dirty=1
}
zdraw init
{
  zdraw addpad log 200 160
  zdraw colorinfo colors
  zdraw paste on
  zdraw inputdelay 25
  zdraw inputinfo input_state
  (( input_state[fd] >= 0 ))
  # The worker starts a fresh matching shell with no curses module loaded.
  exec {worker}< <(exec "$root/.build/zsh/Src/zsh" -dfc '
    module_path=("$1"); zmodload zsh/zselect || exit
    for i in {1..20}; do
      printf "\033[32;40mworker %02d\033[0m  colored output received through a pipe\n" "$i" || exit
      zselect -t 10 || true
    done' worker "$root/.build/modules")
  while (( ! quitting )); do
    # Drain a bounded batch so continuous keyboard input cannot starve the pipe.
    for (( count=0; count<32; count++ )); do
      zdraw event stdscr event poll norefresh || break
      case $event[type] in
        character)
          if [[ $event[text] == q || $event[text] == $'\3' ]]; then quitting=1
          elif [[ $event[text] == '!' ]]; then zdraw-run foreground || true; dirty=1
          fi ;;
        paste)
          [[ $event[phase] == begin ]] && paste_bytes=0
          paste_bytes=$(( paste_bytes + event[bytes] ))
          paste_state=$event[phase] dirty=1 ;;
        resize)
          zdraw resize "$event[rows]" "$event[columns]" nosave
          dirty=1 ;;
      esac
    done
    if (( dirty )); then
      zdraw position stdscr geometry
      rows=$geometry[5] cols=$geometry[6]
      visible=$(( rows > 2 ? rows - 2 : 0 ))
      (( visible > 200 )) && visible=200
      viewcols=$(( cols < 160 ? cols : 160 ))
      top=$(( row + 1 > visible ? row + 1 - visible : 0 ))
      zdraw fill stdscr 0 0 "$rows" "$cols" '' ' '
      zdraw spansclip stdscr 0 0 "$cols" bold 'Streams - paste text, ! foreground, q quits'
      if (( rows > 1 )); then
        zdraw spansclip stdscr "$(( rows - 1 ))" 0 "$cols" reverse \
          "Worker $worker_state | paste $paste_state: $paste_bytes bytes"
      fi
      zdraw stage stdscr
      (( visible )) && zdraw viewport log "$top" 0 1 0 "$visible" "$viewcols"
      zdraw present
      dirty=0
    fi
    (( quitting )) && break
    descriptors=("$input_state[fd]")
    (( worker >= 0 )) && descriptors+=("$worker")
    if zselect -t 2 -A ready -r "${descriptors[@]}"; then
      if (( worker >= 0 )) && [[ ${ready[$worker]:-} == *r* ]]; then
        if sysread -i "$worker" -s 4096 -t 0 chunk; then
          zdraw-sgr-feed "$chunk"
          draw_records
        else
          read_status=$?
          if (( read_status == 5 )); then
            zdraw-sgr-feed '' final
            draw_records
            exec {worker}<&-
            worker=-1 worker_state=done dirty=1
          elif (( read_status != 4 )); then
            return "$read_status"
          fi
        fi
      fi
    fi
  done
} always {
  if (( worker >= 0 )); then exec {worker}<&-; fi
  zdraw end
}
