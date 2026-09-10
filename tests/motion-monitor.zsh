#!/usr/bin/env zsh
# Observe the actual example at presentation barriers; no test-only scheduling.
emulate -R zsh
typeset report_fd=$1 control_fd=$2 motion_option=$3
typeset motion_delay=0
function zdraw {
  [[ $1 == event ]] && print -r -u "$report_fd" -- "wait $motion_delay"
  builtin zdraw "$@" || return
  case $1 in
    timeout) motion_delay=$3 ;;
    present)
      print -r -u "$report_fd" -- "motion $rows $columns $paused $tick $motion_mode $monitor_activity[phase] $monitor_activity[frame] $monitor_activity[visible] $monitor_settle[phase] $monitor_settle[frame] $monitor_settle[visible] $zdraw_ui_table[selected] $tab"
      local ack
      read -r -u "$control_fd" ack || return
      [[ $ack == interrupt ]] && kill -TERM $$ ;;
    end)
      print -r -u "$report_fd" -- "done $monitor_activity[phase] $monitor_settle[phase]" ;;
  esac
  return 0
}
print -r -u "$report_fd" -- baseline
read -r -u "$control_fd" ack || exit 1
source "${0:A:h:h}/examples/task-monitor.zsh" "$motion_option"
