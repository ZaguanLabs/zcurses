#!/usr/bin/env zsh
# One reusable treatment; this application owns the data, input and details.
emulate -R zsh
setopt nounset
typeset example_root=${0:A:h:h}
module_path=("$example_root/.build/modules")
zmodload zdraw || exit 1
source "$example_root/examples/components/linked-detail.zsh" || exit 1
source "$example_root/lib/zdraw-document.zsh" || exit 1
typeset -A zdraw_ui_theme zdraw_ui_list=(selected 3 first 1) zdraw_ui_link
typeset -A zdraw_ui_document event colors
typeset -a reply dimensions input_options items titles summaries details
typeset focus=list theme_name=dark profile=mono requested_profile=auto glyphs=auto dataset=changes layout_mode=tiny
typeset item_gap=1
typeset -i rows columns visible=1 dirty=1 exit_code=0 empty=0 variant=0 detail_offset=1 detail_height=1
while (( $# )); do
  case $1 in
    --theme) theme_name=$2; shift ;;
    --profile) requested_profile=$2; shift ;;
    --dataset) dataset=$2; shift ;;
    --ascii) glyphs=ascii ;;
    --empty) empty=1 ;;
    --variant) variant=1 ;;
    --item-gap) item_gap=$2; shift ;;
    *) print -ru2 -- "unknown option: $1"; exit 1 ;;
  esac
  shift
done
[[ $theme_name == (dark|light) && $requested_profile == (auto|mono|16|256) && $dataset == (changes|catalog) ]] || exit 1
[[ $item_gap == (0|1) ]] || exit 1
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)

function linked-data {
  emulate -L zsh
  if [[ $dataset == changes ]]; then
    titles=('Input handling' 'Selection state' 'Terminal cleanup' 'Narrow layouts' 'Long descriptions' 'Theme inheritance')
    summaries=('Keep pasted text together' 'Retain the current item' 'Leave the shell as we found it' 'One task at a time' 'Wrap without losing meaning' 'One language, distinct pieces')
    details=(
      'A paste belongs to the draft. Application code decides what to do with it; drawing a component never consumes input.'
      'The list owns no application data. Its caller keeps selection and viewport state and can replace the data between frames.'
      'Opening a terminal interface is temporary. Quitting returns terminal ownership to the shell. This example uses the existing curses lifecycle.'
      'When two panes no longer fit, show the focused pane. Tab moves between the list and its details without losing the selection.'
      'A clipped list summary is a signpost. The detail view wraps the complete explanation and can scroll when the available height is small.'
      'Theme tokens establish colors and emphasis across the composition. Local overrides change one treatment without modifying the shared theme.'
    )
  else
    titles=('Field notes' 'Night shift' 'Paper trail' 'Signal garden' 'Atlas' 'Open questions')
    summaries=('Sketches from the workshop' 'Small tasks for quiet hours' 'Documents ready for review' 'Useful notifications' 'A growing collection' 'Ideas to revisit')
    details=(
      'Collect observations before deciding what they mean. This catalog uses the same component and navigation as the change review.'
      'A short collection for the end of the day. Keep the next action visible and leave room to think.'
      'Read the notes, follow the references and record the decision. The application supplies this content; the component supplies its visual connection.'
      'An experiment in notifications that arrive when they can help. The catalog knows nothing about source files or agent workflows.'
      'A collection can grow without changing the visual contract. Selection and viewport remain caller-owned.'
      'Questions can stay open while a useful next step is taken. Try the narrow view, alternate theme and local accent override.'
    )
  fi
  items=()
  local -i i
  if (( !empty )); then
    for (( i=1; i<=${#titles}; i++ )); do items+=("$titles[$i]" "$summaries[$i]"); done
  fi
}

function linked-render {
  emulate -L zsh
  local -A zdraw_ui_style
  local -a body overrides
  local -i selected
  zdraw position stdscr dimensions || return
  rows=$dimensions[5] columns=$dimensions[6]
  zdraw-ui-theme "$theme_name" "$profile" || return
  zdraw-ui-style normal fg=text bg=canvas || return
  zdraw fill stdscr 0 0 "$rows" "$columns" "$zdraw_ui_style[style]" ' ' || return
  zdraw-label stdscr 0 0 "$columns" "LINKED / $dataset / $theme_name" normal fg=accent bg=canvas bold || return
  layout_mode=tiny
  if (( rows < 10 || columns < 26 )); then
    (( rows > 1 )) && zdraw-label stdscr 1 0 "$columns" 'Resize to explore; q quit' normal bg=canvas
    zdraw refresh stdscr
    return
  fi
  linked-data
  if (( variant )); then
    if [[ $profile == mono ]]; then overrides=(header:underline); else overrides=(header:fg=5 selected:fg=7 selected:bg=5); fi
  fi
  zdraw-linked-detail stdscr 2 1 "$((rows-5))" "$((columns-2))" "$focus" \
    list-title='COLLECTION' detail-title='READING ROOM' "glyphs=$glyphs" \
    "item-gap=$item_gap" "${overrides[@]}" -- "${items[@]}" || return
  body=("${reply[@]}") visible=$zdraw_ui_link[visible] layout_mode=$zdraw_ui_link[mode]
  selected=$zdraw_ui_list[selected]
  detail_height=$body[3]
  if (( body[3] && body[4] )); then
    if (( selected )); then
      zdraw-document-init "$body[4]" \
        title heading "$titles[$selected]" summary paragraph "$summaries[$selected]" \
        body paragraph "$details[$selected]" \
        note paragraph 'This is sample content. Switch datasets with d: the treatment stays the same.' || return
    else
      zdraw-document-init "$body[4]" title heading 'Nothing selected' body paragraph 'The collection is empty. Press e to restore the sample items.' || return
    fi
    zdraw_ui_document[first]=$detail_offset
    zdraw-document-scroll "$body[3]" keep || return
    detail_offset=$zdraw_ui_document[first]
    zdraw-document stdscr "${body[@]}" normal bg=canvas heading:fg=accent || return
  fi
  zdraw-label stdscr "$((rows-2))" 1 "$((columns-2))" 'q quit  Tab pane  j/k move' normal fg=muted bg=canvas || return
  zdraw-label stdscr "$((rows-1))" 1 "$((columns-2))" "g: gap $item_gap  t: theme  d: data  e: empty  v: accent  m: mono" normal fg=muted bg=canvas || return
  zdraw refresh stdscr
}

zdraw init || exit 1
{
  zdraw colorinfo colors || exit 1
  if [[ -z ${NO_COLOR:-} ]]; then
    (( colors[colors] >= 8 )) && profile=16
    (( colors[colors] >= 256 )) && profile=256
  fi
  # A requested profile is a ceiling, never an override of terminal capability.
  [[ $requested_profile == mono ]] && profile=mono
  [[ $requested_profile == 16 && $profile == 256 ]] && profile=16
  zdraw timeout stdscr 100 || exit 1
  while true; do
    if (( dirty )); then linked-render || { exit_code=1; break; }; dirty=0; fi
    if zdraw event stdscr event "${input_options[@]}"; then
      typeset action=keep
      case $event[type] in
        character)
          case $event[text] in
            q) break ;;
            $'\e') focus=list ;;
            $'\t'|$'\r'|$'\n') if [[ $focus == list ]]; then focus=detail; else focus=list; fi ;;
            j) action=down ;; k) action=up ;;
            t) if [[ $theme_name == dark ]]; then theme_name=light; else theme_name=dark; fi ;;
            d) if [[ $dataset == changes ]]; then dataset=catalog; else dataset=changes; fi; detail_offset=1 ;;
            e) (( empty=!empty )); detail_offset=1 ;;
            v) (( variant=!variant )) ;;
            g) if [[ $item_gap == 1 ]]; then item_gap=0; else item_gap=1; fi ;;
            m)
              if [[ $profile == mono ]]; then
                (( colors[colors]>=8 )) && profile=16
                (( colors[colors]>=256 )) && profile=256
              else profile=mono; fi ;;
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
      if [[ $action != keep ]]; then
        if [[ $focus == list ]]; then
          zdraw-list-update "$(( ${#titles} * !empty ))" "$visible" "$action" || { exit_code=1; break; }
          detail_offset=1
        elif (( detail_height && rows>=10 && columns>=26 )); then
          zdraw-document-scroll "$detail_height" "$action" || { exit_code=1; break; }
          detail_offset=$zdraw_ui_document[first]
        fi
      fi
      dirty=1
    fi
  done
} always {
  zdraw end || exit_code=1
}
exit "$exit_code"
