#!/usr/bin/env zsh
# Research fixture for image-matrix.py ONLY: a fresh, exclusively owned terminal.
# Quiet uploads own image 33554474; native input never receives graphics replies.
emulate -R zsh
setopt nounset
[[ $# == 1 && -d $1 && -p $1/ack && -f $1/upload ]] || exit 1
typeset image_directory=$1 image_root=${0:A:h:h:h} image_ack image_row image_key image_phase_name
typeset -i image_fd=-1 image_owned=0 image_partial=0 image_active=0 image_interrupted=0 image_y image_x image_code
typeset -a image_marks=($'\u0305' $'\u030d' $'\u030e' $'\u0310' $'\u0312' $'\u033d' $'\u033e' $'\u033f') image_rows image_position
typeset -A image_info image_snapshot
exec 2> "$image_directory/error"
module_path=("$image_root/.build/modules")
zmodload zdraw || exit 1
zmodload zsh/system || exit 1
check() { "$@" || { print -ru2 -- "failed: ${(q)@}"; return 1; }; }
TRAPINT() { image_interrupted=130; return 0; }
TRAPTERM() { image_interrupted=143; return 0; }
function image-delete {
  (( image_owned )) || return 0
  if (( image_partial )); then
    command cat "$image_directory/abort" || return
    image_partial=0
  fi
  command cat "$image_directory/delete" || return
  image_owned=0
}
function image-upload {
  # Claim before sending so even a partial transmission takes the cleanup path.
  image_owned=1
  [[ $1 == interrupted ]] && image_partial=1
  command cat "$image_directory/$1"
}
function image-capture {
  (( ! image_interrupted )) || return "$image_interrupted"
  print -r -- "$1" > "$image_directory/phase.next"
  command mv "$image_directory/phase.next" "$image_directory/phase"
  sysread -i "$image_fd" -s 1 -t 10 image_ack || {
    (( image_interrupted )) && return "$image_interrupted"
    return 1
  }
  (( ! image_interrupted )) || return "$image_interrupted"
}
function image-present {
  check zdraw refresh stdscr
  check zdraw snapshot stdscr image_snapshot
  print -r -- "$1"$'\t'"${image_snapshot[3,3,text]-}"$'\t'"${image_snapshot[3,3,color]-}" >> "$image_directory/readback.tsv"
  image-capture "$1"
}
function image-draw {
  check zdraw fill stdscr 3 3 6 12 '' ' '
  for (( image_y=1; image_y<=4; image_y++ )); do
    check zdraw spans stdscr "$((image_y+2))" 3 42/default "$image_rows[$image_y]"
  done
}
() {
  setopt localoptions errreturn
  check zdraw init
  image_active=1
  {
  exec {image_fd}<> "$image_directory/ack" || return 1
  check zdraw spans stdscr 0 0 bold 'IMAGE RESEARCH / quiet upload / explicit cell coordinates'
  check zdraw spans stdscr 1 0 '' 'Text fallback remains the public preview path.'
  for (( image_y=1; image_y<=4; image_y++ )); do
    image_row=''
    for (( image_x=1; image_x<=8; image_x++ )); do
      image_row+=$'\U10eeee'"$image_marks[$image_y]$image_marks[$image_x]$image_marks[3]"
    done
    image_rows+=("$image_row")
  done
  check zdraw textpos image_info "$image_rows[1]" byte 0
  print -r -- "width=$image_info[total_width] bytes=$image_info[total_bytes]" > "$image_directory/storage"
  # Full coordinates + high ID byte must round-trip, not merely measure.
  check zdraw spans stdscr 3 3 42/default "$image_rows[1]"
  check zdraw snapshot stdscr image_snapshot
  [[ $image_snapshot[3,3,text] == $'\U10eeee'"$image_marks[1]$image_marks[1]$image_marks[3]" ]] || { print -ru2 -- 'placeholder roundtrip failed'; return 1; }
  print -r -- 'full_coordinate_roundtrip=1' >> "$image_directory/storage"
  check zdraw refresh stdscr
  check image-upload upload
  image-draw
  image-present initial
  check zdraw refresh
  image-present redraw
  check zdraw copy stdscr 3 5 stdscr 9 3 4 6
  image-present scrolled
  check zdraw fill stdscr 4 5 2 3 reverse ' '
  image-present overlay
  image-draw
  check image-delete
  check image-upload replacement
  image-present replaced
  # Simulate a smaller curses viewport; the outer driver also resizes the window.
  image-capture before-resize
  check zdraw geometry image_position
  check zdraw resize "$image_position[1]" "$image_position[2]" nosave
  image-draw
  image-present resized
  check image-delete
  check zdraw suspend
  image_active=0
  image-capture suspended
  check zdraw resume
  image_active=1
  check image-upload upload
  image-draw
  image-present resumed
  check image-delete
  check image-upload interrupted
  # Finish the incomplete transfer quietly before deleting its owned image ID.
  check image-delete
  image-present interrupted
  check image-upload upload
  check zdraw refresh
  image-present reuploaded
  check image-delete
  check zdraw end
  image_active=0
  image-capture ended
  check zmodload -u zdraw
  image-capture unloaded
  } always {
    image-delete || true
    if (( image_active )); then zdraw end || true; fi
    if (( image_fd >= 0 )); then exec {image_fd}<&-; fi
  }
  print -r -- 'IMAGE PROBE PASS' > "$image_directory/done"
}
image_code=$?
exit "$image_code"
