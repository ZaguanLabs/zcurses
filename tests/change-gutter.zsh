#!/usr/bin/env zsh
emulate -R zsh
typeset report_fd=$1 control_fd=$2 variant_name=$3
shift 3
typeset -a test_options
typeset -F SECONDS gutter_started=0 gutter_ms=0
case $variant_name in
  mono|16) test_options=(--profile "$variant_name" --ascii) ;;
  light) test_options=(--theme light) ;;
  forced) test_options=(--profile 256 --ascii --variant) ;;
esac
source "${0:A:h:h}/lib/zdraw-screen.zsh" || exit 1
function zdraw {
  builtin zdraw "$@" || return
  case $1 in
    init)
      functions[gutter-render-original]=$functions[gutter-render]
      function gutter-render {
        gutter_started=$SECONDS
        gutter-render-original
      } ;;
    refresh)
      gutter_ms=$((1000*(SECONDS-gutter_started)))
      local -A capture
      local -i r c
      local text='' REPLY acknowledgement
      builtin zdraw snapshot stdscr capture || return
      for (( r=0; r<capture[rows]; r++ )); do
        for (( c=0; c<capture[columns]; c++ )); do text+=$capture[$r,$c,text]; done
        text+=$'\n'
      done
      _zdraw_screen_hex "$text" || return
      print -r -u "$report_fd" -- "frame $rows $columns $first $offset $layout_mode $theme_name $profile $empty $variant $gutter_ms $REPLY"
      read -r -u "$control_fd" acknowledgement ;;
    end) print -r -u "$report_fd" -- done ;;
  esac
  return 0
}
print -r -u "$report_fd" -- baseline
read -r -u "$control_fd" acknowledgement
source "${0:A:h:h}/examples/change-gutter.zsh" "${test_options[@]}"
