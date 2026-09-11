#!/usr/bin/env zsh
emulate -R zsh
typeset report_fd=$1 control_fd=$2 variant_name=$3
shift 3
typeset -a test_options
typeset -F SECONDS linked_started=0 linked_ms=0
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
      functions[linked-render-original]=$functions[linked-render]
      function linked-render {
        linked_started=$SECONDS
        linked-render-original
      } ;;
    refresh)
      linked_ms=$((1000*(SECONDS-linked_started)))
      local -A capture
      local -i r c
      local text='' REPLY acknowledgement
      builtin zdraw snapshot stdscr capture || return
      for (( r=0; r<capture[rows]; r++ )); do
        for (( c=0; c<capture[columns]; c++ )); do text+=$capture[$r,$c,text]; done
        text+=$'\n'
      done
      _zdraw_screen_hex "$text" || return
      print -r -u "$report_fd" -- "frame $rows $columns $focus $zdraw_ui_list[selected] ${zdraw_ui_list[first]:-1} $layout_mode $theme_name $profile $dataset $empty $variant $detail_offset $linked_ms $REPLY"
      read -r -u "$control_fd" acknowledgement ;;
    end) print -r -u "$report_fd" -- done ;;
  esac
  return 0
}
print -r -u "$report_fd" -- baseline
read -r -u "$control_fd" acknowledgement
source "${0:A:h:h}/examples/linked-detail.zsh" "${test_options[@]}"
