#!/usr/bin/env zsh
# Decode once before terminal ownership; subsequent frames use retained data.
emulate -R zsh
setopt nounset
typeset image_root=${0:A:h:h} image_packet image_name='Image preview' image_palette=auto image_colors=image
typeset -i image_status=0 image_exit=0
[[ $# == 1 ]] || { print -ru2 -- 'usage: image-preview.zsh image.png|image.jpg'; exit 1; }
module_path=("$image_root/.build/modules")
zmodload zdraw || exit 1
source "$image_root/lib/zdraw-image.zsh" || exit 1
typeset -A zdraw_ui_image zdraw_ui_theme image_event image_info
typeset -a image_position image_input
image_packet=$(command python3 "$image_root/scripts/image-preview.py" --rows 32 --columns 128 -- "$1")
image_status=$?
(( image_status == 130 || image_status == 143 )) && exit "$image_status"
if (( ! image_status )); then
  zdraw-image-load "$image_packet" "$image_name" || image_status=1
fi
(( ${zdraw_features[(Ie)norefresh_events]} )) && image_input+=(norefresh)
TRAPINT() { image_exit=130; return 0; }
TRAPTERM() { image_exit=143; return 0; }
function image-render {
  emulate -L zsh
  local -i image_rows image_columns image_h image_w image_y image_x
  local -A zdraw_ui_style
  zdraw position stdscr image_position || return
  image_rows=$image_position[5] image_columns=$image_position[6]
  zdraw-ui-style normal fg=text bg=canvas || return
  zdraw fill stdscr 0 0 "$image_rows" "$image_columns" "$zdraw_ui_style[style]" ' ' || return
  zdraw-label stdscr 0 0 "$image_columns" "$image_name / character mosaic" normal fg=accent bg=canvas bold || return
  if (( image_status )); then
    (( image_rows > 2 )) && zdraw-label stdscr 2 0 "$image_columns" '[Image unavailable] PNG/JPEG preview' normal fg=muted
  elif (( image_rows > 4 )); then
    image_h=$((image_rows-4 < 64 ? image_rows-4 : 64)) image_w=$((image_columns < 128 ? image_columns : 128))
    (( image_h*image_w > 4096 )) && image_h=$((4096/image_w))
    image_y=$((2+(image_rows-4-image_h)/2)) image_x=$(((image_columns-image_w)/2))
    zdraw-image-draw stdscr "$image_y" "$image_x" "$image_h" "$image_w" normal "palette=$image_palette" "colors=$image_colors" fit=contain bg=canvas || return
  fi
  (( image_rows > 1 )) && zdraw-label stdscr "$((image_rows-1))" 0 "$image_columns" 'g glyphs / m monochrome / s suspend-resume / q quit' normal fg=muted bg=canvas
  zdraw refresh stdscr
}
zdraw init || exit 1
{
  zdraw colorinfo image_info || image_exit=1
  if (( ! image_exit )); then
    if (( image_info[colors] >= 256 )) && [[ -z ${NO_COLOR:-} ]]; then zdraw-ui-theme dark 256
    elif (( image_info[colors] >= 16 )) && [[ -z ${NO_COLOR:-} ]]; then zdraw-ui-theme dark 16
    else zdraw-ui-theme dark mono; fi
  fi
  while (( ! image_exit )); do
    image-render || { image_exit=1; break; }
    (( image_exit )) && break
    zdraw event stdscr image_event "${image_input[@]}" || continue
    case $image_event[type] in
      character)
        case $image_event[text] in
          q|$'\e') break ;;
          g) if [[ $image_palette == auto ]]; then image_palette=ascii; else image_palette=auto; fi ;;
          m) if [[ $image_colors == image ]]; then image_colors=theme; else image_colors=image; fi ;;
          s) zdraw suspend && zdraw resume || { image_exit=1; break; } ;;
        esac ;;
      resize) zdraw resize "$image_event[rows]" "$image_event[columns]" nosave || { image_exit=1; break; } ;;
    esac
  done
} always {
  zdraw end || image_exit=1
}
exit "$image_exit"
