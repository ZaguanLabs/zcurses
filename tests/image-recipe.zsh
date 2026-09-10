#!/usr/bin/env zsh
emulate -R zsh
typeset test_report=$1 test_control=$2 test_image=$3 test_root=${0:A:h:h} test_ack
module_path=("$test_root/.build/modules")
zmodload zdraw || exit 1
print -r -u "$test_report" -- baseline
read -r -u "$test_control" test_ack || exit 1
function zdraw {
  case $1 in
    refresh)
      builtin zdraw "$@" || return
      print -r -u "$test_report" -- "frame $image_status $image_palette $image_colors $image_position[5] $image_position[6]"
      read -r -u "$test_control" test_ack || return 1
      if [[ $test_ack == interrupt ]]; then kill -TERM $$; fi
      return 0 ;;
  esac
  builtin zdraw "$@"
}
set -- "$test_image"
TRAPEXIT() {
  local test_exit=$?
  (( ZSH_SUBSHELL )) && return "$test_exit"
  print -r -u "$test_report" -- done
  return "$test_exit"
}
source "$test_root/examples/image-preview.zsh"
