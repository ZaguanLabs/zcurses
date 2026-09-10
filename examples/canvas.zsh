#!/usr/bin/env zsh
# The same retained waveform and world scale in ASCII, Braille and block markers.
emulate -R zsh
setopt nounset
typeset recipe_root=${0:A:h:h}
module_path=("$recipe_root/.build/modules")
zmodload zdraw || exit 1
source "$recipe_root/lib/zdraw-canvas.zsh" || exit 1
source "$recipe_root/lib/zdraw-panel.zsh" || exit 1
source "$recipe_root/lib/zdraw-layout.zsh" || exit 1
typeset -A zdraw_ui_canvas zdraw_ui_canvas_raster zdraw_ui_theme colors event
typeset -a reply dimensions content input_options
# Fixed integer samples: no sampling loop, floating-point dependency or timer.
typeset -a wave=(0 20 38 55 71 83 92 98 100 98 92 83 71 55 38 20 0 -20 -38 -55 -71 -83 -92 -98 -100 -98 -92 -83 -71 -55 -38 -20 0)
typeset theme_name=dark color_profile=mono profile=mono canvas_palette=auto shown_palette=auto mode=line
# Source coordinates survive palette/theme changes and resizing.
typeset -i rows columns dirty=1 scene_dirty=1 empty=0 exit_code=0
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)
function canvas-scene {
  emulate -L zsh
  local -i i
  zdraw-canvas-init 0 -100 32 100 || return
  if (( ! empty )); then
    for (( i=1; i<=${#wave}; i++ )); do
      if [[ $mode == point ]]; then zdraw-canvas-add point "$((i-1))" "$wave[$i]" || return
      elif (( i > 1 )); then zdraw-canvas-add line "$((i-2))" "$wave[$((i-1))]" "$((i-1))" "$wave[$i]" || return
      fi
    done
  fi
  zdraw_ui_canvas_raster=()
  scene_dirty=0
}
function recipe-render {
  emulate -L zsh
  local -A zdraw_ui_style
  local -a frame
  local -i plot_rows render_status
  zdraw position stdscr dimensions || return
  rows=$dimensions[5] columns=$dimensions[6]
  zdraw-ui-theme "$theme_name" "$profile" || return
  zdraw-ui-style normal fg=text bg=canvas || return
  zdraw fill stdscr 0 0 "$rows" "$columns" "$zdraw_ui_style[style]" ' ' || return
  if (( rows < 10 || columns < 28 )); then
    zdraw-label stdscr 0 0 "$columns" 'Resize to explore / q quit' normal bg=canvas || return
    zdraw refresh stdscr
    return
  fi
  zdraw-layout-center 0 0 "$rows" "$columns" "$((rows < 40 ? rows : 40))" 96 || return
  frame=("${reply[@]}")
  zdraw-label stdscr "$frame[1]" "$frame[2]" "$frame[4]" 'WAVEFORM / one signal, three ways to see it' normal fg=accent bg=canvas bold || return
  zdraw-panel stdscr "$((frame[1]+2))" "$frame[2]" "$((frame[3]-4))" "$frame[4]" ' AMPLITUDE / -100..100 units ' normal border=rounded px=2 title:fg=accent || return
  content=("${reply[@]}") plot_rows=$((content[3]-1))
  if (( plot_rows > 0 && content[4] > 0 )); then
    if (( scene_dirty )); then canvas-scene || return; fi
    if [[ ${zdraw_ui_canvas_raster[rows]-} != "$plot_rows" || ${zdraw_ui_canvas_raster[columns]-} != "$content[4]" ]]; then
      zdraw-canvas-raster "$plot_rows" "$content[4]" || return
    fi
    # Explicit unsupported profiles fall back by application policy, not inside
    # the renderer. No terminal negotiation or second input reader is involved.
    shown_palette=$canvas_palette
    zdraw-canvas-rows "$shown_palette"
    render_status=$?
    if (( render_status == 2 )); then shown_palette=ascii
    elif (( render_status != 0 )); then return "$render_status"; fi
    zdraw-canvas-draw stdscr "$content[1]" "$content[2]" normal "palette=$shown_palette" || return
    zdraw-label stdscr "$((content[1]+plot_rows))" "$content[2]" "$content[4]" 'x: 0..32 samples / same world scale in every mode' normal fg=muted || return
  fi
  zdraw-label stdscr "$((frame[1]+frame[3]-2))" "$frame[2]" "$frame[4]" "$mode / $shown_palette / $zdraw_ui_canvas[count] shapes / ${zdraw_ui_canvas_raster[pixels]:-0} dots" normal fg=muted bg=canvas || return
  zdraw-label stdscr "$((frame[1]+frame[3]-1))" "$frame[2]" "$frame[4]" 'g glyphs / p points-lines / e empty / t theme / m mono / q quit' normal fg=accent bg=canvas || return
  zdraw refresh stdscr
}
canvas-scene || exit 1
zdraw init || exit 1
{
  zdraw colorinfo colors || exit 1
  if [[ -z ${NO_COLOR:-} ]]; then
    (( colors[colors] >= 8 )) && color_profile=16
    (( colors[colors] >= 256 )) && color_profile=256
  fi
  profile=$color_profile
  zdraw timeout stdscr 100 || exit 1
  while true; do
    if (( dirty )); then recipe-render || { exit_code=1; break; }; dirty=0; fi
    zdraw event stdscr event "${input_options[@]}" || continue
    case $event[type] in
      character)
        case $event[text] in
          q|$'\e') break ;;
          g) case $canvas_palette in auto) canvas_palette=ascii ;; ascii) canvas_palette=block ;; block) canvas_palette=auto ;; esac ;;
          p) if [[ $mode == line ]]; then mode=point; else mode=line; fi; scene_dirty=1 ;;
          e) empty=$((!empty)); scene_dirty=1 ;;
          t) if [[ $theme_name == dark ]]; then theme_name=light; else theme_name=dark; fi ;;
          m) if [[ $profile == mono ]]; then profile=$color_profile; else profile=mono; fi ;;
          *) continue ;;
        esac ;;
      resize) zdraw resize "$event[rows]" "$event[columns]" nosave || { exit_code=1; break; } ;;
      *) continue ;;
    esac
    dirty=1
  done
} always {
  zdraw end || exit_code=1
}
exit "$exit_code"
