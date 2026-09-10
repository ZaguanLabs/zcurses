# Run a foreground command with ordinary terminal modes, preserving its status.
zdraw-run() {
  emulate -L zsh
  (( $# )) || return 1
  local -i _zdraw_run_status
  local -A _zdraw_run_info
  zdraw inputinfo _zdraw_run_info || return
  (( ! _zdraw_run_info[suspended] )) || return 1
  zdraw suspend || return
  {
    if "$@"; then _zdraw_run_status=0; else _zdraw_run_status=$?; fi
  } always {
    zdraw resume || return 1
  }
  return "$_zdraw_run_status"
}
