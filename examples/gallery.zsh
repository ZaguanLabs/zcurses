#!/usr/bin/env zsh
# Run with .build/zsh/Src/zsh -df examples/gallery.zsh
emulate -R zsh
setopt nounset
typeset gallery_root=${0:A:h:h}
module_path=("$gallery_root/.build/modules")
zmodload zdraw || exit 1
source "$gallery_root/lib/zdraw-panel.zsh" || exit 1
source "$gallery_root/lib/zdraw-list.zsh" || exit 1
source "$gallery_root/lib/zdraw-layout.zsh" || exit 1
typeset -A zdraw_ui_theme zdraw_ui_style zdraw_ui_list event colors
typeset -a reply dimensions input_options items=(
  'Panels and surfaces' 'Lists and selection' 'Theme tokens' 'Local overrides'
  'Focus and inactive states' 'Clipping and alignment' 'Small terminal layouts'
  'Empty states' 'ASCII border fallback' 'Caller-owned interaction'
)
typeset -a shown panel_rect panel_utilities border_names=(rounded double ascii none)
typeset theme_name=dark profile=16 native_profile list_focus=focus
typeset -i border_index=1 compact=0 empty=0 narrow=0 mono=0 dirty=1 exit_code=0
typeset -i rows columns width origin visible=0 y
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)

function gallery-render {
  emulate -L zsh
  local -A zdraw_ui_layout
  local -a canvas body footer list_frame detail_frame
  local -i max_width=112
  zdraw position stdscr dimensions || return
  rows=$dimensions[5] columns=$dimensions[6]
  profile=$native_profile
  (( mono )) && profile=mono
  zdraw-ui-theme "$theme_name" "$profile" || return
  zdraw-ui-style normal fg=text bg=canvas || return
  zdraw fill stdscr 0 0 "$rows" "$columns" "$zdraw_ui_style[style]" ' ' || return
  (( narrow )) && max_width=44
  zdraw-layout-center 0 0 "$rows" "$columns" "$rows" "$max_width" || return
  canvas=("${reply[@]}") width=$reply[4] origin=$reply[2]
  zdraw-label stdscr 0 "$origin" "$width" 'zdraw / component studio' normal bg=canvas fg=accent bold || return
  if (( rows < 8 || width < 18 )); then
    visible=0
    (( rows > 1 )) && zdraw-label stdscr 1 0 "$columns" 'q quit; resize to explore' normal bg=canvas
    zdraw refresh stdscr
    return
  fi
  zdraw-label stdscr 1 "$origin" "$width" "Theme: $theme_name   Border: $border_names[$border_index]   Colors: $profile" normal bg=canvas fg=muted || return
  zdraw-layout-split "${canvas[@]}" rows 0 fixed=3 flex=1 fixed=2 || return
  zdraw-layout-rect 2 || return
  body=("${reply[@]}")
  zdraw-layout-rect 3 || return
  footer=("${reply[@]}")
  panel_utilities=("border=$border_names[$border_index]" 'title:fg=accent')
  if (( compact )); then panel_utilities+=(px=0 py=0); else panel_utilities+=(px=1 py=1); fi
  list_frame=("${body[@]}")
  if (( width >= 72 )); then
    zdraw-layout-split "${body[@]}" columns 2 fixed=36 flex=1 || return
    zdraw-layout-rect 1 || return
    list_frame=("${reply[@]}")
    zdraw-layout-rect 2 || return
    detail_frame=("${reply[@]}")
  fi
  zdraw-panel stdscr "${list_frame[@]}" ' Components ' "$list_focus" "${panel_utilities[@]}" || return
  panel_rect=("${reply[@]}") visible=$reply[3]
  shown=("${items[@]}")
  (( empty )) && shown=()
  zdraw-list-update "${#shown}" "$visible" keep || return
  if (( reply[3] && reply[4] )); then
    zdraw-list stdscr "${panel_rect[@]}" "$list_focus" 'empty-text=Nothing here yet' -- "${shown[@]}" || return
  fi
  if (( width >= 72 )); then
    zdraw-panel stdscr "${detail_frame[@]}" ' Your design ' normal "${panel_utilities[@]}" || return
    panel_rect=("${reply[@]}")
    local density_name=comfortable
    (( compact )) && density_name=compact
    local -a lines=(
      'Small pieces. Your choices.'
      ''
      'Choose a component; change its appearance.'
      'Share a theme, or override one instance.'
      ''
      "Density: $density_name"
      "List state: $list_focus"
      'No required icons or terminal protocols.'
    )
    # Use the public label and ordinary utilities for a custom element.
    for (( y=1; y<=${#lines} && y<=panel_rect[3]; y++ )); do
      local -a utilities=(fg=text)
      (( y == 1 )) && utilities=(fg=accent bold)
      zdraw-label stdscr "$((panel_rect[1]+y-1))" "$panel_rect[2]" "$panel_rect[4]" "$lines[$y]" normal "${utilities[@]}" || return
    done
  fi
  local help='t theme  b border  d density  Tab focus  e empty  n narrow  m mono'
  local navigation='q quit  Up/Down select  PgUp/PgDn scroll  Home/End  x disabled'
  if (( width < 72 )); then
    help='n width  d density  m mono  e empty'
    navigation='q quit  j/k move  t theme  b border'
  fi
  zdraw-label stdscr "$footer[1]" "$footer[2]" "$footer[4]" "$help" normal bg=canvas fg=muted || return
  zdraw-label stdscr "$((footer[1]+1))" "$footer[2]" "$footer[4]" "$navigation" normal bg=canvas || return
  zdraw refresh stdscr
}

zdraw init || exit 1
{
  zdraw colorinfo colors || exit 1
  native_profile=mono
  if [[ $colors[colors] == <-> ]]; then
    (( colors[colors] >= 8 )) && native_profile=16
    (( colors[colors] >= 256 )) && native_profile=256
  fi
  [[ -n ${NO_COLOR:-} ]] && mono=1
  zdraw timeout stdscr 100 || exit 1
  while true; do
    if (( dirty )); then
      gallery-render || { exit_code=1; break; }
      dirty=0
    fi
    if zdraw event stdscr event "${input_options[@]}"; then
      typeset action=keep
      case $event[type] in
        character)
          case $event[text] in
            q|$'\x03'|$'\e') break ;;
            t) if [[ $theme_name == dark ]]; then theme_name=light; else theme_name=dark; fi ;;
            b) border_index=$(( border_index % 4 + 1 )) ;;
            d) compact=$(( ! compact )) ;; e) empty=$(( ! empty )) ;;
            n) narrow=$(( ! narrow )) ;; m) mono=$(( ! mono )) ;;
            $'\t') if [[ $list_focus == focus ]]; then list_focus=inactive; else list_focus=focus; fi ;;
            x) if [[ $list_focus == disabled ]]; then list_focus=focus; else list_focus=disabled; fi ;;
            j) action=down ;; k) action=up ;;
          esac ;;
        key)
          case $event[key] in
            UP) action=up ;; DOWN) action=down ;; HOME) action=home ;; END) action=end ;;
            NPAGE) action=page-down ;; PPAGE) action=page-up ;;
          esac ;;
        resize)
          if (( ${zdraw_features[(Ie)resize]} )); then
            zdraw resize "$event[rows]" "$event[columns]" nosave || { exit_code=1; break; }
          fi ;;
      esac
      if [[ $list_focus == focus ]]; then
        zdraw-list-update "${#shown}" "$visible" "$action" || { exit_code=1; break; }
      fi
      dirty=1
    fi
  done
} always {
  zdraw end || exit_code=1
}
exit "$exit_code"
