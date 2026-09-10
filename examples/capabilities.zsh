#!/usr/bin/env zsh
# Passive by default. Press p to explicitly query each of three terminal modes.
emulate -R zsh
setopt nounset
module_path=("${0:A:h:h}/.build/modules" "${module_path[@]}")
zmodload zdraw || exit 1
typeset -A cap event
typeset -a size modes=(streaming_paste focus_events synchronized_output) overrides
typeset -i next=1 row columns running=1 override=0
typeset name line note='Passive inspection: no queries sent.'
zdraw init || exit 1
{
  zdraw timeout stdscr 100 || exit 1
  while (( running )); do
    zdraw geometry size || exit 1
    zdraw resize "$size[1]" "$size[2]" || exit 1
    columns=$size[2]
    zdraw capabilities cap "${overrides[@]}" || exit 1
    zdraw clear stdscr || exit 1
    zdraw spansclip stdscr 0 0 "$columns" bold 'zdraw | capability evidence' || exit 1
    if (( size[1] >= 16 )); then
      zdraw spansclip stdscr 2 0 "$columns" underline 'Capability             Support  Evidence   Compiled Enabled  Query' || exit 1
      row=3
      for name in ${(s: :)cap[names]}; do
        printf -v line '%-22s %-8s %-10s %-8s %-8s %s' "$name" "$cap[$name,support]" "$cap[$name,source]" "$cap[$name,compiled]" "$cap[$name,enabled]" "$cap[$name,query]"
        zdraw spansclip stdscr "$row" 0 "$columns" '' "$line" || exit 1
        (( row++ ))
      done
      zdraw spansclip stdscr 12 0 "$columns" '' "$note" || exit 1
      zdraw spansclip stdscr 14 0 "$columns" dim 'p: query next mode | o: cycle sync override | q/Esc: quit' || exit 1
    elif (( size[1] >= 2 )); then
      zdraw spansclip stdscr 1 0 "$columns" '' 'Resize to 16 rows to inspect. q: quit' || exit 1
    fi
    zdraw refresh stdscr || exit 1
    zdraw event stdscr event poll norefresh || { zdraw event stdscr event norefresh || continue; }
    if [[ $event[type] == capability ]]; then
      note="$event[name]: $event[phase] (report $event[report])"
    elif [[ $event[type] == character ]]; then
      case $event[text] in
        q|$'\e') running=0 ;;
        p)
          if (( next <= 3 )); then
            if zdraw query on && zdraw query request "$modes[$next]" 1500; then
              note="Query sent: $modes[$next]"
              (( next++ ))
            else note='Request unavailable, already attempted, or another request is pending.'; fi
          else note='All modes attempted. Each mode can be queried once per session.'; fi ;;
        o)
          override=$(((override+1)%4))
          case $override in
            0) overrides=() ;;
            1) overrides=(synchronized_output=yes) ;;
            2) overrides=(synchronized_output=no) ;;
            3) overrides=(synchronized_output=unknown) ;;
          esac
          note='Override affects this displayed record only; it never enables terminal modes.' ;;
      esac
    fi
  done
} always {
  zdraw end
}
