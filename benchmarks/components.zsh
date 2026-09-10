#!/usr/bin/env zsh
# Driven by components.py with a matching module/shell and a controlled PTY.
emulate -R zsh
setopt nounset
typeset bench_root=${0:A:h:h}
[[ $# == 7 && $2 == (chart|canvas|form|document|surfaces|spans|prepared) && $3 == (repeated|changing) && $4 == (small|large) ]] || exit 1
source "$bench_root/lib/zdraw-canvas.zsh" || exit 1
source "$bench_root/lib/zdraw-bars.zsh" || exit 1
source "$bench_root/lib/zdraw-form.zsh" || exit 1
source "$bench_root/lib/zdraw-document.zsh" || exit 1
_zdraw_ui_uint "$5" && _zdraw_ui_uint "$6" && _zdraw_ui_uint "$7" || exit 1
module_path=("$1")
zmodload zdraw || exit 1
typeset workload=$2 pattern=$3 size=$4 report_fd=$6 ack_fd=$7 key acknowledgement
typeset -i frames=$((10#$5)) rows=8 columns=32 count=4 i frame phase=0
(( frames > 0 && frames <= 1000 )) || exit 1
[[ $size == large ]] && rows=16 columns=64 count=12
typeset -A zdraw_ui_canvas zdraw_ui_canvas_raster zdraw_ui_chart zdraw_ui_form zdraw_ui_document zdraw_ui_theme snap resources
typeset -a samples blocks fields
typeset -F 9 SECONDS started work=0 stage=0 present=0
check() { "$@" || { print -ru2 -- "failed: $*"; exit 1; }; }
check zdraw-ui-theme dark 256
for (( i=1; i<=columns; i++ )); do samples+=("$((i%21-10))"); done
for (( i=1; i<=count; i++ )); do
  fields+=("Field $i" 'Editable value' required)
  blocks+=("block$i" paragraph 'A document paragraph with words, wrapping and stable source byte anchors. Repeatable measurements describe this work at a known viewport size.')
done
check zdraw-chart-series fixed -10 10 -- "${samples[@]}"
check zdraw-canvas-init 0 -10 63 10
for (( i=2; i<=columns; i++ )); do check zdraw-canvas-add line "$((i-2))" "$samples[$((i-1))]" "$((i-1))" "$samples[$i]"; done
check zdraw-canvas-raster "$rows" "$columns"
check zdraw-form-init "${fields[@]}"
check zdraw-document-init "$columns" "${blocks[@]}"
function bench-work {
  emulate -L zsh
  local -i line
  case $workload in
    chart)
      if [[ $pattern == changing ]]; then
        samples[1]=$((phase ? 8 : -8))
        zdraw-chart-series fixed -10 10 -- "${samples[@]}" || return
      fi
      zdraw-bars sample 0 0 "$rows" "$columns" normal palette=ascii ;;
    canvas)
      if [[ $pattern == changing ]]; then
        zdraw_ui_canvas[1,y0]=$((phase ? 8 : -8))
        zdraw-canvas-raster "$rows" "$columns" || return
      fi
      zdraw-canvas-draw sample 0 0 normal palette=braille ;;
    form)
      if [[ $pattern == changing ]]; then
        zdraw-form-action edit home || return
        zdraw-form-action edit delete || return
        zdraw-form-action edit insert "$phase" || return
      fi
      zdraw-form sample 0 0 "$rows" "$columns" focus ;;
    document)
      zdraw-document-reflow "$((columns-phase))" || return
      zdraw-document sample 0 0 "$rows" "$((columns-phase))" normal ;;
    surfaces)
      zdraw treewin backing "$rows" "$columns" 0 0 || return
      zdraw move sample 0 0 || return
      zdraw fill backing 0 0 "$rows" "$columns" '' "$phase" || return
      zdraw fill floating 0 0 4 12 bold,red/black 'X' || return
      zdraw copy backing 0 0 sample 0 0 "$rows" "$columns" || return
      zdraw overlay floating 0 0 sample 2 "$((2+phase))" 4 12 ;;
    spans|prepared)
      for (( line=0; line<rows; line++ )); do
        if [[ $workload == prepared ]]; then zdraw draw sample "$line" 0 "row$phase" || return
        else zdraw spans sample "$line" 0 bold,red/black "${(pl:$columns::$phase:):-}" || return; fi
      done ;;
  esac
}
check zdraw init
{
  check zdraw addwin sample "$rows" "$columns" 0 0
  if [[ $workload == surfaces ]]; then
    check zdraw addwin backing "$rows" "$columns" 0 0
    check zdraw addwin child 2 4 1 1 backing
    check zdraw addwin floating 4 12 0 0
  fi
  if [[ $workload == prepared ]]; then
    check zdraw prepare row0 bold,red/black "${(pl:$columns::0:):-}"
    check zdraw prepare row1 bold,red/black "${(pl:$columns::1:):-}"
  fi
  # Warm up the same draw/stage/present path, then measure each boundary.
  for (( frame=-2; frame<frames; frame++ )); do
    phase=0
    [[ $pattern == changing ]] && phase=$(((frame+2)%2))
    started=$SECONDS
    check bench-work
    (( frame >= 0 )) && (( work += SECONDS-started ))
    started=$SECONDS
    check zdraw stage sample
    (( frame >= 0 )) && (( stage += SECONDS-started ))
    started=$SECONDS
    check zdraw present
    (( frame >= 0 )) && (( present += SECONDS-started ))
  done
  # Inspection and serialization are outside all measured boundaries.
  check zdraw snapshot sample snap
  (( ${zdraw_features[(Ie)resource_info]} )) && check zdraw resourceinfo resources
} always {
  zdraw end || exit 1
}
print -r -u "$report_fd" -- "$work $stage $present"
for key in "${(@ok)resources}"; do print -r -u "$report_fd" -- "$key=$resources[$key]"; done
print -r -u "$report_fd" -- SNAPSHOT
for key in "${(@ok)snap}"; do print -rn -u "$report_fd" -- "$key"$'\0'"$snap[$key]"$'\0'; done
# EOF lets the driver finish the report and sample post-exec RSS before exit.
exec {report_fd}>&-
read -r -u "$ack_fd" acknowledgement || exit 1
