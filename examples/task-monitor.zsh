#!/usr/bin/env zsh
# Simulated work: replace monitor-step with application-owned progress updates.
emulate -R zsh
setopt nounset
typeset monitor_root=${0:A:h:h}
module_path=("$monitor_root/.build/modules")
zmodload zdraw || exit 1
source "$monitor_root/lib/zdraw-panel.zsh" || exit 1
source "$monitor_root/lib/zdraw-layout.zsh" || exit 1
source "$monitor_root/lib/zdraw-table.zsh" || exit 1
source "$monitor_root/lib/zdraw-tabs.zsh" || exit 1
source "$monitor_root/lib/zdraw-meter.zsh" || exit 1
source "$monitor_root/lib/zdraw-badge.zsh" || exit 1
source "$monitor_root/lib/zdraw-help.zsh" || exit 1
source "$monitor_root/lib/zdraw-sparkline.zsh" || exit 1
source "$monitor_root/lib/zdraw-bars.zsh" || exit 1
typeset -A zdraw_ui_theme zdraw_ui_table event colors
typeset -a reply dimensions input_options tasks=('Index sources' 'Run checks' 'Prepare release')
typeset -a progress=(0 0 0) rates=(3 2 1) gains=(0 0 0) chart_history=(0)
typeset theme_name=dark profile=mono color_profile=mono run_state=Running chart_palette=auto
typeset -i rows columns tab=1 paused=0 tick=0 completed=0 visible=0 dirty=1 exit_code=0
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)

function monitor-step {
  emulate -L zsh
  local -i i previous average=0
  completed=0
  for (( i=1; i<=${#tasks}; i++ )); do
    previous=$progress[$i]
    (( progress[i] += rates[i] ))
    (( progress[i] > 100 )) && progress[$i]=100
    gains[$i]=$((progress[i]-previous))
    (( average += progress[i] ))
    (( progress[i] == 100 )) && (( completed++ ))
  done
  chart_history+=("$((average/${#tasks}))")
  (( ${#chart_history} > 96 )) && chart_history=("${chart_history[@]: -96}")
  (( tick++ ))
  return 0
}

function monitor-render {
  emulate -L zsh
  local -A zdraw_ui_style zdraw_ui_layout zdraw_ui_chart
  local -a frame body footer content cells zdraw_ui_headers zdraw_ui_tracks zdraw_ui_alignments
  local -i i y title_width average=0 label_width chart_width chart_rows
  local title task_state
  zdraw position stdscr dimensions || return
  rows=$dimensions[5] columns=$dimensions[6]
  zdraw-ui-theme "$theme_name" "$profile" || return
  zdraw-ui-style normal fg=text bg=canvas || return
  zdraw fill stdscr 0 0 "$rows" "$columns" "$zdraw_ui_style[style]" ' ' || return
  zdraw-layout-center 0 0 "$rows" "$columns" "$rows" 112 || return
  frame=("${reply[@]}") title_width=$reply[4]
  run_state=Running
  (( paused )) && run_state=Paused
  (( completed == ${#tasks} )) && run_state=Complete
  (( title_width >= 44 )) && (( title_width -= 14 ))
  zdraw-label stdscr 0 "$frame[2]" "$title_width" 'TASKS / steady progress' normal bg=canvas fg=accent bold || return
  if (( frame[4] >= 44 )); then
    zdraw-badge stdscr 0 "$((frame[2]+frame[4]-12))" 12 "$run_state" normal || return
  fi
  visible=0
  if (( rows < 8 || columns < 24 )); then
    zdraw-label stdscr "$(( rows > 1 ? 1 : 0 ))" 0 "$columns" 'q quit; resize to explore' normal bg=canvas || return
    zdraw refresh stdscr
    return
  fi
  zdraw-tabs stdscr 1 "$frame[2]" "$frame[4]" "$tab" focus -- Overview Queue History || return
  zdraw-layout-split "${frame[@]}" rows 0 fixed=3 flex=1 fixed=2 || return
  zdraw-layout-rect 2 || return
  body=("${reply[@]}")
  zdraw-layout-rect 3 || return
  footer=("${reply[@]}")
  title="Overview / $run_state"
  (( tab == 2 )) && title="Queue / $run_state"
  (( tab == 3 )) && title="History / $run_state"
  zdraw-panel stdscr "${body[@]}" " $title " focus border=rounded px=1 title:fg=accent || return
  content=("${reply[@]}")
  if (( content[3] && content[4] )); then
    if (( tab == 1 )); then
      for i in "${progress[@]}"; do (( average += i )); done
      (( average /= ${#tasks} ))
      zdraw-label stdscr "$content[1]" "$content[2]" "$content[4]" "Overall: $completed/${#tasks} complete" normal bold || return
      if (( content[3] > 1 )); then
        zdraw-meter stdscr "$((content[1]+1))" "$content[2]" "$content[4]" "$average" 100 normal || return
      fi
      for (( i=1, y=3; i<=${#tasks} && y<content[3]; i++, y+=3 )); do
        zdraw-label stdscr "$((content[1]+y))" "$content[2]" "$content[4]" "$tasks[$i]" normal || return
        if (( y+1 < content[3] )); then
          zdraw-meter stdscr "$((content[1]+y+1))" "$content[2]" "$content[4]" "$progress[$i]" 100 normal || return
        fi
      done
    elif (( tab == 3 )); then
      zdraw-label stdscr "$content[1]" "$content[2]" "$content[4]" "Overall: $chart_history[-1]% / step $tick" normal bold || return
      if (( content[3] >= 2 )); then
        zdraw-chart-series fixed 0 100 -- "${chart_history[@]}" || return
        zdraw-sparkline stdscr "$((content[1]+1))" "$content[2]" "$content[4]" normal "palette=$chart_palette" || return
      fi
      if (( content[3] >= 3 )); then
        zdraw-label stdscr "$((content[1]+2))" "$content[2]" "$content[4]" '0..100% / latest samples / max 96 steps' normal fg=muted || return
      fi
      if (( content[3] >= 6 )); then
        zdraw-label stdscr "$((content[1]+4))" "$content[2]" "$content[4]" 'Gain: percentage points/step / scale 0..3' normal fg=muted || return
        label_width=$((content[4] >= 40 ? 22 : 8))
        chart_width=$((content[4]-label_width))
        chart_rows=$((content[3]-5 < ${#tasks} ? content[3]-5 : ${#tasks}))
        if (( chart_width > 0 )); then
          zdraw-chart-series fixed 0 3 -- "${gains[@]}" || return
          zdraw-bars stdscr "$((content[1]+5))" "$((content[2]+label_width))" "$chart_rows" "$chart_width" normal "palette=$chart_palette" || return
          for (( i=1; i<=chart_rows; i++ )); do
            title="$tasks[$i] / $gains[$i]"
            (( label_width == 8 )) && title="#$i: $gains[$i]"
            zdraw-label stdscr "$((content[1]+4+i))" "$content[2]" "$label_width" "$title" normal || return
          done
        fi
      fi
    else
      visible=$((content[3]-1))
      zdraw-table-update "${#tasks}" "$visible" keep || return
      zdraw_ui_headers=(Task Done) zdraw_ui_tracks=(flex=1 fixed=5) zdraw_ui_alignments=(left right)
      if (( content[4] >= 36 )); then
        zdraw_ui_headers+=(State) zdraw_ui_tracks+=(fixed=8) zdraw_ui_alignments+=(left)
      fi
      for (( i=1; i<=${#tasks}; i++ )); do
        task_state=$run_state
        (( progress[i] == 100 )) && task_state=Done
        cells+=("$tasks[$i]" "$progress[$i]%")
        (( ${#zdraw_ui_headers} == 3 )) && cells+=("$task_state")
      done
      zdraw-table stdscr "${content[@]}" focus -- "${cells[@]}" || return
    fi
  fi
  zdraw-label stdscr "$footer[1]" "$footer[2]" "$footer[4]" "Simulated work / $run_state / step $tick" normal fg=muted bg=canvas || return
  zdraw-help stdscr "$((footer[1]+1))" "$footer[2]" "$footer[4]" normal -- q quit Space pause Tab view n step r reset t theme g glyphs m mono || return
  zdraw refresh stdscr
}

zdraw init || exit 1
{
  zdraw colorinfo colors || exit 1
  if [[ $colors[colors] == <-> && -z ${NO_COLOR:-} ]]; then
    (( colors[colors] >= 8 )) && profile=16
    (( colors[colors] >= 256 )) && profile=256
  fi
  color_profile=$profile
  zdraw timeout stdscr 250 || exit 1
  zdraw-table-update "${#tasks}" 0 keep || exit 1
  while true; do
    if (( dirty )); then
      monitor-render || { exit_code=1; break; }
      dirty=0
    fi
    if zdraw event stdscr event "${input_options[@]}"; then
      typeset action=keep
      case $event[type] in
        character)
          case $event[text] in
            q|$'\e') break ;;
            ' '|p) paused=$((!paused)) ;;
            $'\t') tab=$((tab%3+1)) ;;
            1|2|3) tab=$event[text] ;;
            n) monitor-step ;;
            r) progress=(0 0 0); gains=(0 0 0); chart_history=(0); tick=0; completed=0 ;;
            t) if [[ $theme_name == dark ]]; then theme_name=light; else theme_name=dark; fi ;;
            g) if [[ $chart_palette == auto ]]; then chart_palette=ascii; else chart_palette=auto; fi ;;
            m) if [[ $profile == mono ]]; then profile=$color_profile; else profile=mono; fi ;;
            j) action=down ;; k) action=up ;;
            *) continue ;;
          esac ;;
        key)
          case $event[key] in
            LEFT) tab=$(((tab+1)%3+1)) ;; RIGHT) tab=$((tab%3+1)) ;; UP) action=up ;; DOWN) action=down ;;
            *) continue ;;
          esac ;;
        resize)
          if (( ${zdraw_features[(Ie)resize]} )); then
            zdraw resize "$event[rows]" "$event[columns]" nosave || { exit_code=1; break; }
          fi ;;
        *) continue ;;
      esac
      if (( tab == 2 )); then zdraw-table-update "${#tasks}" "$visible" "$action" || { exit_code=1; break; }; fi
      dirty=1
    elif (( !paused && completed < ${#tasks} )); then
      monitor-step
      dirty=1
    fi
  done
} always {
  zdraw end || exit_code=1
}
exit "$exit_code"
