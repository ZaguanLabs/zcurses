#!/usr/bin/env zsh
# Copyable recipe: application data and input remain outside the UI libraries.
# Run from the checkout with .build/zsh/Src/zsh -df examples/table-inspector.zsh
emulate -R zsh
setopt nounset
typeset recipe_root=${0:A:h:h}
module_path=("$recipe_root/.build/modules")
zmodload zdraw || exit 1
source "$recipe_root/lib/zdraw-panel.zsh" || exit 1
source "$recipe_root/lib/zdraw-table.zsh" || exit 1
source "$recipe_root/lib/zdraw-layout.zsh" || exit 1
typeset -A zdraw_ui_theme zdraw_ui_table event colors
typeset -a reply dimensions input_options
typeset -a projects=('Atlas' 'Field notes' 'Night shift' 'Paper trail' 'Signal garden')
typeset -a summaries=(
  'A workspace for a growing collection.'
  'Observations, sketches and loose ends.'
  'Small tasks for quiet hours.'
  'Documents ready for review.'
  'An experiment in useful notifications.'
)
typeset -a owners=('Mira' 'Jules' 'Sam' 'Alex' 'Rowan')
typeset -a stages=('In progress' 'Draft' 'Ready' 'In review' 'Prototype')
typeset theme_name=dark profile=mono view=table layout_mode=tiny
typeset -i rows columns visible=0 dirty=1 exit_code=0 empty=0 row_count=5
typeset -a jobs=(12 4 8 0 21)
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)

function recipe-render {
  emulate -L zsh
  local -A zdraw_ui_layout zdraw_ui_style wrapped
  local -a frame body footer table_frame detail_frame content lines cells
  local -a zdraw_ui_headers zdraw_ui_tracks zdraw_ui_alignments
  local -i selected i
  zdraw position stdscr dimensions || return
  rows=$dimensions[5] columns=$dimensions[6]
  zdraw-ui-theme "$theme_name" "$profile" || return
  zdraw-ui-style normal fg=text bg=canvas || return
  zdraw fill stdscr 0 0 "$rows" "$columns" "$zdraw_ui_style[style]" ' ' || return
  zdraw-layout-center 0 0 "$rows" "$columns" "$rows" 124 || return
  frame=("${reply[@]}")
  zdraw-label stdscr 0 "$frame[2]" "$frame[4]" 'WORKSPACE / project overview' normal bg=canvas fg=accent bold || return
  visible=0 layout_mode=tiny
  if (( rows < 8 || columns < 24 )); then
    (( rows > 1 )) && zdraw-label stdscr 1 0 "$columns" 'q quit; resize to explore' normal bg=canvas
    zdraw refresh stdscr
    return
  fi
  # Reserve a heading and footer; the middle track takes the remaining rows.
  zdraw-layout-split "${frame[@]}" rows 0 fixed=2 flex=1 fixed=2 || return
  zdraw-layout-rect 2 || return
  body=("${reply[@]}")
  zdraw-layout-rect 3 || return
  footer=("${reply[@]}")
  table_frame=("${body[@]}") detail_frame=("${body[@]}")
  layout_mode=single
  if (( body[4] >= 100 )); then
    layout_mode=split
    zdraw-layout-split "${body[@]}" columns 2 fixed=56 flex=1 || return
    zdraw-layout-rect 1 || return
    table_frame=("${reply[@]}")
    zdraw-layout-rect 2 || return
    detail_frame=("${reply[@]}")
  fi
  row_count=${#projects}
  (( empty )) && row_count=0
  if [[ $layout_mode == split || $view == table ]]; then
    zdraw-panel stdscr "${table_frame[@]}" ' Projects ' focus border=rounded px=1 title:fg=accent || return
    content=("${reply[@]}")
    visible=$(( content[3] > 0 ? content[3]-1 : 0 ))
    zdraw-table-update "$row_count" "$visible" keep || return
    zdraw_ui_headers=(Project Jobs) zdraw_ui_tracks=(flex=1 fixed=4)
    zdraw_ui_alignments=(left right)
    if (( content[4] >= 42 )); then
      zdraw_ui_headers+=(Status) zdraw_ui_tracks+=(fixed=12) zdraw_ui_alignments+=(left)
    fi
    for (( i=1; i<=row_count; i++ )); do
      cells+=("$projects[$i]" "$jobs[$i]")
      (( ${#zdraw_ui_headers} == 3 )) && cells+=("$stages[$i]")
    done
    if (( content[3] && content[4] )); then
      zdraw-table stdscr "${content[@]}" focus gap=2 -- "${cells[@]}" || return
    fi
  else
    zdraw-table-update "$row_count" 0 keep || return
  fi
  if [[ $layout_mode == split || $view == detail ]]; then
    selected=$zdraw_ui_table[selected]
    zdraw-panel stdscr "${detail_frame[@]}" ' Inspector ' normal border=rounded px=1 py=0 title:fg=accent || return
    content=("${reply[@]}")
    if (( selected )); then
      lines=("$projects[$selected]" "$stages[$selected] / $owners[$selected]" "Jobs: $jobs[$selected]" '')
      if (( content[4] > 0 && ${zdraw_features[(Ie)text_wrapping]} )); then
        zdraw textwrap wrapped "$summaries[$selected]" "$content[4]" || return
        for (( i=0; i<wrapped[line_count]; i++ )); do lines+=("$wrapped[$i,text]"); done
      else
        lines+=("$summaries[$selected]")
      fi
    else
      lines=('No project selected' '' 'The workspace is empty.')
    fi
    for (( i=1; i<=${#lines} && i<=content[3] && content[4]>0; i++ )); do
      local -a utilities=(fg=text)
      (( i == 1 )) && utilities=(fg=accent bold)
      (( i == 2 )) && utilities=(fg=muted)
      zdraw-label stdscr "$((content[1]+i-1))" "$content[2]" "$content[4]" "$lines[$i]" normal "${utilities[@]}" || return
    done
  fi
  local hint='Enter inspect/back  j/k select'
  [[ $layout_mode == split ]] && hint='j/k select  Home/End  PgUp/PgDn'
  zdraw-label stdscr "$footer[1]" "$footer[2]" "$footer[4]" "$hint" normal bg=canvas fg=muted || return
  zdraw-label stdscr "$((footer[1]+1))" "$footer[2]" "$footer[4]" 'q quit  Esc back  t theme  e empty' normal bg=canvas || return
  zdraw refresh stdscr
}

zdraw init || exit 1
{
  zdraw colorinfo colors || exit 1
  if [[ $colors[colors] == <-> && -z ${NO_COLOR:-} ]]; then
    (( colors[colors] >= 8 )) && profile=16
    (( colors[colors] >= 256 )) && profile=256
  fi
  zdraw timeout stdscr 100 || exit 1
  zdraw-table-update "${#projects}" 0 keep || exit 1
  while true; do
    if (( dirty )); then
      recipe-render || { exit_code=1; break; }
      dirty=0
    fi
    if zdraw event stdscr event "${input_options[@]}"; then
      typeset action=keep
      case $event[type] in
        character)
          case $event[text] in
            q) break ;;
            $'\e')
              if [[ $layout_mode == single && $view == detail ]]; then view=table; else break; fi ;;
            $'\n'|$'\r')
              if [[ $layout_mode == single ]]; then
                if [[ $view == table ]]; then view=detail; else view=table; fi
              fi ;;
            j) action=down ;; k) action=up ;;
            e) empty=$(( ! empty )) ;;
            t) if [[ $theme_name == dark ]]; then theme_name=light; else theme_name=dark; fi ;;
            *) continue ;;
          esac ;;
        key)
          case $event[key] in
            UP) action=up ;; DOWN) action=down ;; HOME) action=home ;; END) action=end ;;
            NPAGE) action=page-down ;; PPAGE) action=page-up ;;
            *) continue ;;
          esac ;;
        resize)
          if (( ${zdraw_features[(Ie)resize]} )); then
            zdraw resize "$event[rows]" "$event[columns]" nosave || { exit_code=1; break; }
          fi ;;
        *) continue ;;
      esac
      zdraw-table-update "$row_count" "$visible" "$action" || { exit_code=1; break; }
      dirty=1
    fi
  done
} always {
  zdraw end || exit_code=1
}
exit "$exit_code"
