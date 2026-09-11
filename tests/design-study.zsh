#!/usr/bin/env zsh
# Exercise the real example, pausing after each presented frame.
emulate -R zsh
typeset report_fd=$1 control_fd=$2 example=$3 study_capture=${ZDRAW_STUDY_CAPTURE:-}
typeset -i study_frame=0 study_calls=0
typeset -F study_started=0 study_ms=0
typeset -a study_options=(--design "$example")
[[ $example == mono ]] && study_options=(--design expressive --profile mono --ascii)
[[ $example == basic ]] && study_options=(--design expressive --profile 16 --ascii)
[[ $example == vt100 ]] && study_options=(--design expressive --ascii)
source "${0:A:h:h}/lib/zdraw-screen.zsh" || exit 1
source "${0:A:h:h}/lib/zdraw-fixture.zsh" || exit 1
function zdraw {
  (( study_calls++ ))
  builtin zdraw "$@" || return
  case $1 in
    init)
      functions[study-render-original]=$functions[study-render]
      function study-render {
        study_started=$SECONDS study_calls=0
        study-render-original
      } ;;
    refresh)
      study_ms=$((1000*(SECONDS-study_started)))
      local -A capture
      local -i r c
      local text='' REPLY acknowledgement
      builtin zdraw snapshot stdscr capture || return
      for (( r=0; r<capture[rows]; r++ )); do
        for (( c=0; c<capture[columns]; c++ )); do text+=$capture[$r,$c,text]; done
        text+=$'\n'
      done
      _zdraw_screen_hex "$text" || return
      print -r -u "$report_fd" -- "frame $rows $columns $design $scenario $focus $zdraw_ui_list[selected] $zdraw_ui_list[first] $detail_offset $layout_mode $profile $progress $study_ms $study_calls $REPLY"
      if [[ -n $study_capture ]]; then
        local zdraw_ui_fixture
        zdraw-fixture stdscr || return
        print -r -- "$zdraw_ui_fixture" > "$study_capture/$example-$study_frame.json"
      fi
      (( study_frame++ ))
      read -r -u "$control_fd" acknowledgement ;;
    end) print -r -u "$report_fd" -- done ;;
  esac
  return 0
}
typeset -F SECONDS
print -r -u "$report_fd" -- baseline
read -r -u "$control_fd" acknowledgement
source "${0:A:h:h}/examples/design-study.zsh" "${study_options[@]}"
