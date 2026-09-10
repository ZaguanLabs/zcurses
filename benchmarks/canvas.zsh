#!/usr/bin/env zsh
# Called by canvas.py in a controlled PTY with a matching shell/module.
emulate -R zsh
setopt nounset
typeset bench_root=${0:A:h:h}
source "$bench_root/lib/zdraw-canvas.zsh" || exit 1
[[ $# == 8 && $2 == (baseline|raster|cached|rebuild) && $3 == (ascii|braille) ]] || exit 1
typeset arg
for arg in "${@:4}"; do _zdraw_ui_uint "$arg" || exit 1; done
module_path=("$1")
zmodload zdraw || exit 1
typeset backend=$2 palette=$3 report_fd=$7 acknowledge_fd=$8
typeset -i frames=$((10#$4)) rows=$((10#$5)) columns=$((10#$6)) i frame
(( frames > 0 && frames <= 1000 )) || exit 1
typeset -A zdraw_ui_canvas zdraw_ui_canvas_raster zdraw_ui_theme
typeset -a wave=(0 20 38 55 71 83 92 98 100 98 92 83 71 55 38 20 0 -20 -38 -55 -71 -83 -92 -98 -100 -98 -92 -83 -71 -55 -38 -20 0)
check() { "$@" || exit 1; }
check zdraw-canvas-init 0 -100 32 100
for (( i=2; i<=${#wave}; i++ )); do check zdraw-canvas-add line "$((i-2))" "$wave[$((i-1))]" "$((i-1))" "$wave[$i]"; done
check zdraw-ui-theme dark 256
function bench-frame {
  emulate -L zsh
  case $backend in
    raster) zdraw-canvas-raster "$rows" "$columns" ;;
    cached) zdraw-canvas-draw sample 0 0 normal "palette=$palette" "fg=$((80+frame%2))" ;;
    rebuild)
      zdraw-canvas-raster "$rows" "$columns" || return
      zdraw-canvas-draw sample 0 0 normal "palette=$palette" "fg=$((80+frame%2))" ;;
    baseline) return 0 ;;
  esac
}
typeset -F 9 SECONDS elapsed
check zdraw init
{
  check zdraw addwin sample "$rows" "$columns" 0 0
  if [[ $backend != baseline ]]; then check zdraw-canvas-raster "$rows" "$columns"; fi
  for (( frame=0; frame<3; frame++ )); do check bench-frame; done
  SECONDS=0
  for (( frame=0; frame<frames; frame++ )); do check bench-frame; done
  elapsed=$SECONDS
} always {
  zdraw end || exit 1
}
# Resource counts describe logical storage/work, not allocator byte estimates.
print -r -u "$report_fd" -- "$elapsed ${zdraw_ui_canvas_raster[pixels]:-0} ${zdraw_ui_canvas_raster[cells]:-0} ${zdraw_ui_canvas_raster[writes]:-0}"

# Keep the shell alive so the driver can read its post-exec high-water memory.
typeset acknowledgement
read -r -u "$acknowledge_fd" acknowledgement || exit 1
