#!/usr/bin/env zsh
# Private runner for replay.py. Only the named, trusted repository recipes run.
emulate -R zsh
typeset replay_report=$1 replay_control=$2 replay_recipe=$3
[[ $replay_recipe == (form|document|canvas) ]] || exit 1
source "${0:A:h:h}/lib/zdraw-fixture.zsh" || exit 1
source "${0:A:h:h}/lib/zdraw-screen.zsh" || exit 1
function replay-association {
  emulate -L zsh
  local kind=$1 parameter=$2 key REPLY packet=$1
  local -A values=("${(@kvP)parameter}")
  for key in "${(@ok)values}"; do
    _zdraw_screen_hex "$values[$key]" || return
    packet+=$'\t'"$key=$REPLY"
  done
  print -r -u "$replay_report" -- "$packet"
}
function zdraw {
  builtin zdraw "$@" || return
  case $1 in
    init)
      local -A context
      builtin zdraw capabilities context || return
      local -a features=("${(@o)zdraw_features}")
      context[features]="${(j:,:)features}"
      replay-association context context || return ;;
    event) replay-association event "$3" || return ;;
    refresh|present)
      local zdraw_ui_fixture acknowledgement
      zdraw-fixture stdscr || return
      # Fixtures are ASCII JSON; remove formatting newlines for pipe framing.
      print -r -u "$replay_report" -- $'frame\t'"${zdraw_ui_fixture//$'\n'/}"
      read -r -u "$replay_control" acknowledgement || return ;;
    end) print -r -u "$replay_report" -- done ;;
  esac
  return 0
}
print -r -u "$replay_report" -- baseline
read -r -u "$replay_control" acknowledgement || exit 1
if [[ $replay_recipe == form ]]; then
  source "${0:A:h:h}/examples/form.zsh" --paste
else
  source "${0:A:h:h}/examples/$replay_recipe.zsh"
fi
