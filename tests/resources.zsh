#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A info baseline row before after capabilities old_capabilities
typeset key
typeset -a position before_position
check zdraw resourceinfo info
[[ $info[format] == zdraw-resources-1 && $info[session] == inactive && $info[windows] == 0 ]] || fail inactive
check zdraw init
{
  check zdraw resourceinfo baseline
  [[ $baseline[windows] == 1 && $baseline[owned_windows] == 0 && $baseline[child_windows] == 0 ]] || fail stdscr
  check zdraw addwin sample 4 20 1 1
  check zdraw addwin child 2 4 2 2 sample
  check zdraw addpad pad 10 30
  check zdraw prepare text bold,red/black SECRETRESOURCE
  check zdraw draw sample 0 0 text
  check zdraw draw sample 1 0 text 0
  reject zdraw draw sample 0 19 text
  reject zdraw prepare text '' duplicate
  check zdraw move sample 2 3
  check zdraw position sample before_position
  check zdraw snapshot sample before
  check zdraw capabilities old_capabilities
  check zdraw resourceinfo info
  [[ $info[windows] == 3 && $info[owned_windows] == 1 && $info[child_windows] == 1 &&
     $info[pads] == 1 && $info[pad_cells] == 300 && $info[prepared_rows] == 1 &&
     $info[prepared_created] == 1 && $info[prepared_draws] == 2 && $info[retired_tree_windows] == 0 ]] || fail counts
  (( info[window_cells] == baseline[window_cells]+88 && info[backing_cells] == baseline[backing_cells]+80 )) || fail sharing
  check zdraw rowinfo text row
  [[ $row[draws] == 2 && $row[bytes] == $info[prepared_bytes] && $row[session_limit] == $info[prepared_byte_limit] ]] || fail reuse
  check zdraw position sample position
  [[ "${position[*]}" == "${before_position[*]}" ]] || fail cursor
  check zdraw snapshot sample after
  for key in "${(@k)before}"; do [[ $before[$key] == "$after[$key]" ]] || fail "changed cell: $key"; done
  check zdraw capabilities capabilities
  for key in "${(@k)old_capabilities}"; do [[ $old_capabilities[$key] == "$capabilities[$key]" ]] || fail "changed capability: $key"; done
  if (( ${zdraw_features[(Ie)suspend_resume]} )); then
    check zdraw suspend
    check zdraw resourceinfo after
    [[ $after[session] == suspended ]] || fail suspend
    for key in "${(@k)info}"; do [[ $key == session || $info[$key] == "$after[$key]" ]] || fail "suspend lost: $key"; done
    check zdraw resume
  fi
  check zdraw resizepad pad 4 5
  check zdraw unprepare text
  check zdraw resourceinfo info
  [[ $info[pad_cells] == 20 && $info[prepared_rows] == 0 && $info[prepared_bytes] == 0 &&
     $info[prepared_created] == 1 && $info[prepared_draws] == 2 ]] || fail release
  check zdraw delwin child
  check zdraw delwin sample
  check zdraw delwin pad
  check zdraw resourceinfo info
  [[ $info[windows] == 1 && $info[pads] == 0 && $info[pad_cells] == 0 ]] || fail deletion
} always {
  zdraw end || exit 1
}
check zdraw resourceinfo info
[[ $info[session] == inactive ]] || fail ended
for key in windows child_windows owned_windows window_cells backing_cells pads pad_cells private_input_pads retired_tree_windows cached_color_pairs prepared_rows prepared_bytes prepared_created prepared_draws; do
  [[ $info[$key] == 0 ]] || fail "not released: $key"
done
check zdraw init
check zdraw resourceinfo info
[[ $info[windows] == 1 && $info[prepared_created] == 0 && $info[prepared_draws] == 0 ]] || fail reinit
check zdraw end
check zmodload -u zdraw
check zmodload zdraw
check zdraw resourceinfo info
[[ $info[windows] == 0 && $info[prepared_created] == 0 ]] || fail reload
print -r -- 'RESOURCES PASS'
