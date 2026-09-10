#!/usr/bin/env zsh
# Structured content, reusable semantic styles and a responsive reading viewport.
emulate -R zsh
setopt nounset
typeset recipe_root=${0:A:h:h}
module_path=("$recipe_root/.build/modules")
zmodload zdraw || exit 1
source "$recipe_root/lib/zdraw-document.zsh" || exit 1
source "$recipe_root/lib/zdraw-panel.zsh" || exit 1
source "$recipe_root/lib/zdraw-layout.zsh" || exit 1
source "$recipe_root/lib/zdraw-list.zsh" || exit 1
typeset -A zdraw_ui_theme zdraw_ui_document zdraw_ui_list event colors
typeset -a reply dimensions input_options content frame sidebar main_frame
# Stable IDs are navigation anchors. Content is always passed as quoted data.
typeset -a document_blocks=(
  beginning heading '01 / Leave room to think'
  opening paragraph 'A useful terminal interface can be quiet, clear and beautiful. Start with a small set of semantic colors, an obvious focus state and enough space between ideas.'
  breathing quote 'The most useful thing on a screen should be the easiest thing to find.'
  hierarchy subheading 'A little hierarchy goes a long way'
  hierarchy_text paragraph 'Give the page one clear title. Use shorter section headings, restrained accent colors and generous grouping. Borders should explain a relationship; whitespace can do the same work with less visual weight.'
  one bullet 'Choose a surface, text, muted and accent role before picking individual colors.'
  two bullet 'Keep focused, selected and inactive states visually distinct.'
  three bullet 'Make empty states useful: explain what belongs here and how to begin.'
  dividing separator ''
  composition heading '02 / Compose small pieces'
  composition_text paragraph 'Panels, labels, lists and documents share a theme and a small utility vocabulary. Each component takes a rectangle and paints it. Your application chooses the layout, supplies data and owns the event loop.'
  snippet code $'typeset -A zdraw_ui_theme\nzdraw-ui-theme dark 256\n\n# Override roles, then reuse them.\nzdraw-ui-theme dark 256 accent=81'
  ownership paragraph 'Keep state separate from drawing. An input event changes the model; a redraw reads that model. This makes resize behavior predictable and allows the same component to appear in several applications.'
  reuse bullet 'Store repeated utility arguments in an array and pass each element as one argument.'
  test bullet 'Capture meaningful states as portable fixtures and review text and style changes together.'
  resize heading '03 / Design for the narrow screen'
  resize_text paragraph 'A layout is a set of priorities. When space runs out, keep the primary task visible, move secondary information into another view and keep selection anchored to data. The reading position in this example follows a source byte when wrapping changes.'
  small bullet 'Use stacked panes when a side-by-side layout becomes cramped.'
  smaller bullet 'Hide secondary metadata before removing the primary action.'
  smallest bullet 'At very small sizes, explain how to return to a usable view.'
  ending quote 'Good defaults should make the first version pleasant, and leave the next version open.'
  closing paragraph 'Try resizing this reader. Press n or p to move between headings, 1/2/3 for chapters, and t to switch themes. The source blocks and reading state stay separate from their current presentation.'
)
typeset -a chapters=('Leave room to think' 'Compose small pieces' 'Design for narrow screens')
typeset theme_name=dark profile=mono
typeset -i rows columns visible=0 dirty=1 exit_code=0
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)
zdraw-document-init 40 "${document_blocks[@]}" || exit 1
function recipe-render {
  emulate -L zsh
  local -A zdraw_ui_style zdraw_ui_layout
  local -i top source_block selected=1
  zdraw position stdscr dimensions || return
  rows=$dimensions[5] columns=$dimensions[6]
  zdraw-ui-theme "$theme_name" "$profile" || return
  zdraw-ui-style normal fg=text bg=canvas || return
  zdraw fill stdscr 0 0 "$rows" "$columns" "$zdraw_ui_style[style]" ' ' || return
  visible=0
  if (( rows < 9 || columns < 24 )); then
    zdraw-label stdscr 0 0 "$columns" 'Resize to read / q quit' normal bg=canvas || return
    zdraw refresh stdscr
    return
  fi
  zdraw-layout-center 0 0 "$rows" "$columns" "$rows" 116 || return
  frame=("${reply[@]}")
  zdraw-label stdscr 0 "$frame[2]" "$frame[4]" 'FIELD GUIDE / beautiful things, built in the terminal' normal fg=accent bg=canvas bold || return
  main_frame=(2 "$frame[2]" "$((rows-4))" "$frame[4]")
  sidebar=()
  if (( frame[4] >= 92 )); then
    zdraw-layout-split "${main_frame[@]}" columns 2 fixed=27 flex=1 || return
    zdraw-layout-rect 1 || return
    sidebar=("${reply[@]}")
    zdraw-layout-rect 2 || return
    main_frame=("${reply[@]}")
  fi
  zdraw-panel stdscr "${main_frame[@]}" ' THE READING ROOM ' focus border=rounded px=2 title:fg=accent || return
  content=("${reply[@]}") visible=$reply[3]
  if (( content[3] && content[4] )); then
    if (( content[4] != zdraw_ui_document[columns] )); then
      zdraw-document-reflow "$content[4]" || return
    fi
    zdraw-document-scroll "$visible" keep || return
    zdraw-document stdscr "${content[@]}" normal heading:bold quote:fg=muted || return
  fi
  if (( ${#sidebar} )); then
    top=$zdraw_ui_document[first] source_block=$zdraw_ui_document[$top,block]
    (( source_block >= 10 )) && selected=2
    (( source_block >= 16 )) && selected=3
    zdraw_ui_list=(selected "$selected" first 1)
    zdraw-panel stdscr "${sidebar[@]}" ' CHAPTERS ' inactive border=rounded px=1 || return
    if (( reply[3] && reply[4] )); then
      zdraw-list stdscr "${reply[@]}" inactive -- "${chapters[@]}" || return
    fi
  fi
  zdraw-label stdscr "$((rows-1))" "$frame[2]" "$frame[4]" "j/k scroll / n/p headings / 1-3 chapters / t theme / q quit    $zdraw_ui_document[first]/$zdraw_ui_document[line_count]" normal fg=muted bg=canvas || return
  zdraw refresh stdscr
}
zdraw init || exit 1
{
  zdraw colorinfo colors || exit 1
  if [[ -z ${NO_COLOR:-} ]]; then
    (( colors[colors] >= 8 )) && profile=16
    (( colors[colors] >= 256 )) && profile=256
  fi
  zdraw timeout stdscr 100 || exit 1
  while true; do
    if (( dirty )); then recipe-render || { exit_code=1; break; }; dirty=0; fi
    zdraw event stdscr event "${input_options[@]}" || continue
    typeset action=keep anchor=''
    case $event[type] in
      character)
        case $event[text] in
          q|$'\e') break ;; j) action=down ;; k) action=up ;;
          ' ') action=page-down ;; n) action=next-heading ;; p) action=previous-heading ;;
          1) action=anchor anchor=beginning ;; 2) action=anchor anchor=composition ;; 3) action=anchor anchor=resize ;;
          t) if [[ $theme_name == dark ]]; then theme_name=light; else theme_name=dark; fi ;;
          *) continue ;;
        esac ;;
      key)
        case $event[key] in
          UP) action=up ;; DOWN) action=down ;; HOME) action=home ;; END) action=end ;;
          NPAGE) action=page-down ;; PPAGE) action=page-up ;; *) continue ;;
        esac ;;
      resize) zdraw resize "$event[rows]" "$event[columns]" nosave || { exit_code=1; break; } ;;
      *) continue ;;
    esac
    if [[ $action == anchor ]]; then
      zdraw-document-scroll "$visible" anchor "$anchor" || { exit_code=1; break; }
    elif [[ $event[type] != resize ]]; then
      zdraw-document-scroll "$visible" "$action" || { exit_code=1; break; }
    fi
    dirty=1
  done
} always {
  zdraw end || exit_code=1
}
exit "$exit_code"
