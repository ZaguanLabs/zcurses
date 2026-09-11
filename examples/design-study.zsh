#!/usr/bin/env zsh
# SPDX-License-Identifier: LicenseRef-Zsh
# One review workspace, three compositions. All work and data are simulated.
# Run with the matching shell: .build/zsh/Src/zsh -df examples/design-study.zsh
emulate -R zsh
setopt nounset
typeset study_root=${0:A:h:h}
typeset design=quiet scenario=ready requested_profile=auto profile=mono
typeset focus=list layout_mode=tiny border=none
typeset -i ascii=0 monochrome=0 rows=0 columns=0 visible=0 detail_visible=0
typeset -i detail_offset=0 detail_count=0 progress=3 dirty=1 exit_code=0 saved_selection=1
typeset -a design_names=(quiet workbench expressive) state_names=(ready empty busy error)
while (( $# )); do
  case $1 in
    --design|--state|--profile)
      (( $# >= 2 )) || { print -ru2 -- "Missing value for $1"; exit 1; }
      case $1 in
        --design) design=$2 ;; --state) scenario=$2 ;; --profile) requested_profile=$2 ;;
      esac
      shift 2 ;;
    --ascii) ascii=1; shift ;;
    --help)
      print -r -- 'usage: design-study.zsh [--design quiet|workbench|expressive] [--state ready|empty|busy|error] [--profile auto|256|16|mono] [--ascii]'
      print -r -- '1/2/3 design; s state; Tab/Enter list/detail; j/k or arrows move; PgUp/PgDn page; m monochrome; r retry; Space advance simulated work; q quit.'
      exit 0 ;;
    *) print -ru2 -- "Unknown option: $1"; exit 1 ;;
  esac
done
[[ $design == (quiet|workbench|expressive) && $scenario == (ready|empty|busy|error) &&
   $requested_profile == (auto|256|16|mono) ]] || { print -ru2 -- 'Invalid design, state or color profile; see --help.'; exit 1; }
module_path=("$study_root/.build/modules")
zmodload zdraw || exit 1
for component in panel list layout help meter document; do
  source "$study_root/lib/zdraw-$component.zsh" || exit 1
done
typeset -A zdraw_ui_theme zdraw_ui_list colors event
typeset -a reply dimensions input_options shown
typeset -a tasks=(
  'Keep pasted text in the draft' 'Preserve position on resize'
  'Make approvals easy to read' 'Show changed files together'
  'Restore focus after a command' 'Wrap long tool output'
  'Keep shortcuts discoverable' 'Handle an empty workspace'
  'A deliberately long change title: retain the complete meaning in the detail view'
)
typeset -a files=(lib/input.zsh lib/layout.zsh lib/approval.zsh lib/changes.zsh
  lib/terminal.zsh lib/transcript.zsh lib/help.zsh lib/workspace.zsh docs/decisions.md)
typeset -a navigation=(
  'Paste stays in the draft' 'Position after resize' 'Readable approvals'
  'Changed files' 'Focus after a command' 'Long tool output'
  'Discoverable shortcuts' 'Empty workspace'
  'A deliberately long change title: retain the complete meaning in the detail view'
)
typeset -a summaries=(
  'A pasted newline belongs to the draft. Keep paste events separate from the key that sends a message, even while a response is streaming.'
  'Keep the selected change and reading position available when a narrow terminal returns to its full width.'
  'Put the requested command, working directory and available choices together. Give the decision room to breathe.'
  'Let the reader move through changed files while keeping the current explanation visible.'
  'Return to the same selection and draft after a foreground command finishes.'
  'Wrap explanations to the available columns. Preserve the meaning of long paths and show code without pretending to be a full editor.'
  'Keep the most useful keys visible. Show complete shortcut pairs and offer a compact layout when space is limited.'
  'Explain why the list is empty and make the next action obvious. Empty space can still be useful.'
  'Navigation labels may be clipped, but the selected title is wrapped here in full. Try this item at a narrow terminal width.'
)
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)

# Design decisions live here. The component API and application state are shared.
function study-theme {
  emulate -L zsh
  local base=dark
  local -a tokens
  [[ $design == quiet ]] && base=light
  profile=$color_profile
  (( monochrome )) && profile=mono
  border=none
  [[ $design == workbench ]] && border=ascii
  [[ $design == expressive ]] && border=rounded
  (( ascii )) && [[ $border != none ]] && border=ascii
  if [[ $profile == 256 ]]; then
    case $design in
      quiet) tokens=(canvas=255 surface=255 text=235 muted=241 accent=24 border=250
        selection=153 on-selection=17 inactive=254 on-inactive=235 error=124) ;;
      workbench) tokens=(canvas=234 surface=234 text=252 muted=247 accent=150 border=240
        selection=150 on-selection=234 inactive=238 on-inactive=252 error=210) ;;
      expressive) tokens=(canvas=17 surface=18 text=255 muted=153 accent=219 border=62
        selection=219 on-selection=17 inactive=24 on-inactive=255 error=217) ;;
    esac
  fi
  zdraw-ui-theme "$base" "$profile" "${tokens[@]}"
}

# The following helpers belong to this example, not a new toolkit abstraction.
# A rectangle is row, column, height, width; a line outside it is simply absent.
function study-line {
  emulate -L zsh
  local -i y=$1 x=$2 h=$3 w=$4 offset=$5
  (( offset >= 0 && offset < h && w > 0 )) || return 0
  zdraw-label stdscr "$((y+offset))" "$x" "$w" "$6" normal "${@:7}"
}

function study-paragraph {
  emulate -L zsh
  local kind=paragraph
  case $2 in title) kind=heading ;; muted) kind=subheading ;; accent) kind=code ;; esac
  detail_blocks+=("block-$(( ${#detail_blocks}/3+1 ))" "$kind" "$1")
}

function study-detail {
  emulate -L zsh
  local -a rect=("$@") detail_blocks
  local -A zdraw_ui_document
  local -i paragraph_width=$rect[4] i index=${zdraw_ui_list[selected]} y=0
  local title='' heading='REVIEW NOTES' description='' marker=''
  (( rect[3] > 0 && paragraph_width > 0 )) || { detail_visible=0; return 0; }
  case $scenario in
    empty)
      title='A little room for the next change.'
      description='There are no changes to review. Press r to simulate a fresh check, or s to explore another state.' ;;
    error)
      heading='CHECK INTERRUPTED'
      title='The workspace could not be read.'
      description='The simulated connection closed before the check finished. Your selection is still here. Press r to retry; no files will be changed.' ;;
    busy)
      heading='CHECKING THE WORKSPACE'
      title='Useful progress, without stealing focus.'
      description="Read or navigate while the check runs. This demo advances only when you press Space: $progress of 5 checks complete." ;;
    ready) title=$tasks[$index] description=$summaries[$index] ;;
  esac
  study-paragraph "$heading" muted || return
  study-paragraph "$title" title || return
  study-paragraph "$description" text || return
  if [[ $scenario == ready ]]; then
    study-paragraph "$files[$index]  /  proposed change" accent || return
    if (( index == 1 )); then
      study-paragraph $'- submit on every newline\n+ insert paste into the draft\n+ submit on a deliberate Enter' accent || return
    fi
    study-paragraph 'WHAT TO CHECK' muted || return
    study-paragraph 'The active selection stays visible. Long text remains readable. Returning from a narrow view preserves the selected change.' text || return
    study-paragraph 'TRY IT HERE' muted || return
    study-paragraph 'Use Tab to move between the list and these notes. Use j/k or the arrow keys to move; Page Up and Page Down travel farther. Switch designs with 1, 2 and 3 without losing your place.' text || return
    study-paragraph 'REVIEW CONTEXT' muted || return
    study-paragraph 'The content is fictional and shared by all three designs. No model, network connection or application repository is required. The comparison is about the interface you can build with the existing toolkit.' text || return
  fi
  zdraw-document-init "$paragraph_width" "${detail_blocks[@]}" || return
  detail_count=$zdraw_ui_document[line_count] detail_visible=$((rect[3]-1))
  (( detail_visible < 1 )) && detail_visible=1
  local -i maximum=$((detail_count-detail_visible))
  (( maximum < 0 )) && maximum=0
  (( detail_offset > maximum )) && detail_offset=$maximum
  (( detail_offset < 0 )) && detail_offset=0
  for (( i=detail_offset+1; i<=detail_count && y<detail_visible; i++,y++ )); do
    local -a style=(fg=text)
    case $zdraw_ui_document[$i,role] in
      heading) style=(fg=text bold) ;; subheading) style=(fg=muted) ;; code) style=(fg=accent) ;;
    esac
    study-line "${rect[@]}" "$y" "$zdraw_ui_document[$i,text]" "${style[@]}" || return
  done
  if (( rect[3] > 1 && detail_count > detail_visible )); then
    marker="Notes $((detail_offset+1))-$((detail_offset+detail_visible)) / $detail_count"
    [[ $focus == detail ]] && marker+='  j/k scroll'
    study-line "${rect[@]}" "$((rect[3]-1))" "$marker" fg=muted || return
  fi
  return 0
}

function study-render {
  emulate -L zsh
  local -A zdraw_ui_layout zdraw_ui_style
  local -a frame body rail notes context content panel_style labels list_style shortcuts
  local -i top=3 margin=1 gap=2 rail_width=30 selected=0
  local rail_state=inactive notes_state=normal state_label='Ready to review'
  zdraw position stdscr dimensions || return
  rows=$dimensions[5] columns=$dimensions[6]
  study-theme || return
  zdraw-ui-style normal fg=text bg=canvas || return
  zdraw fill stdscr 0 0 "$rows" "$columns" "$zdraw_ui_style[style]" ' ' || return
  visible=0 detail_visible=0 layout_mode=tiny
  shown=("${tasks[@]}")
  [[ $scenario == empty ]] && shown=()
  if (( rows < 12 || columns < 32 )); then
    zdraw-label stdscr 0 0 "$columns" 'Review workspace' normal bg=canvas bold || return
    (( rows > 1 )) && zdraw-label stdscr 1 0 "$columns" 'q quit; resize to 32x12' normal bg=canvas
    zdraw refresh stdscr
    return
  fi
  case $scenario in
    empty) state_label='No changes' ;; busy) state_label="Checking $progress/5" ;; error) state_label='Check failed - r retry' ;;
  esac
  case $design in
    quiet) margin=2 top=4 ;;
    workbench) margin=0 gap=1 rail_width=28 ;;
    expressive) margin=1 top=5 gap=2 rail_width=30 ;;
  esac
  zdraw-layout-center 0 0 "$rows" "$columns" "$rows" 132 || return
  zdraw-layout-inset "${reply[@]}" 0 "$margin" 0 "$margin" || return
  frame=("${reply[@]}")
  if [[ $design == expressive ]]; then
    study-line "${frame[@]}" 0 ' FIELDWORK / REVIEW STUDIO' bg=selection fg=on-selection bold || return
    local subtitle=' Make the next change a good one.' location="$state_label  /  local workspace"
    (( frame[4] < 34 )) && subtitle=' Make a considered change.'
    (( frame[4] < 64 )) && location=$state_label
    study-line "${frame[@]}" 1 "$subtitle" bg=selection fg=on-selection || return
    study-line "${frame[@]}" 3 "$location" bg=canvas fg=accent || return
  elif [[ $design == workbench ]]; then
    local heading=' REVIEW / fieldwork' status_line=" $state_label"
    if (( frame[4] >= 64 )); then
      heading+='     branch: input-care'
      status_line+=" | ${#shown} proposals | no files modified"
    fi
    study-line "${frame[@]}" 0 "$heading" bg=canvas bold || return
    study-line "${frame[@]}" 1 "$status_line" bg=canvas fg=accent || return
  else
    study-line "${frame[@]}" 1 'Fieldwork' bg=canvas fg=accent bold || return
    local subtitle="A considered change.  /  $state_label"
    (( frame[4] < 50 )) && subtitle='Review / local workspace'
    study-line "${frame[@]}" 2 "$subtitle" bg=canvas fg=muted || return
  fi
  zdraw-layout-split "${frame[@]}" rows 0 "fixed=$top" flex=1 fixed=3 || return
  zdraw-layout-rect 2 || return
  body=("${reply[@]}") rail=("${reply[@]}") notes=("${reply[@]}")
  layout_mode=single
  if (( body[4] >= 78 )); then
    layout_mode=split
    if [[ $design == expressive ]]; then
      zdraw-layout-split "${body[@]}" columns "$gap" flex=1 "fixed=$rail_width" || return
      zdraw-layout-rect 1 || return; notes=("${reply[@]}")
      zdraw-layout-rect 2 || return; rail=("${reply[@]}")
    else
      if [[ $design == workbench ]] && (( body[4] >= 112 )); then
        layout_mode=triple
        zdraw-layout-split "${body[@]}" columns "$gap" "fixed=$rail_width" flex=1 fixed=24 || return
        zdraw-layout-rect 3 || return; context=("${reply[@]}")
      else
        zdraw-layout-split "${body[@]}" columns "$gap" "fixed=$rail_width" flex=1 || return
      fi
      zdraw-layout-rect 1 || return; rail=("${reply[@]}")
      zdraw-layout-rect 2 || return; notes=("${reply[@]}")
    fi
  fi
  [[ $focus == list ]] && rail_state=focus
  [[ $focus == detail ]] && notes_state=focus
  zdraw-list-update "${#shown}" 0 keep || return
  panel_style=("border=$border" px=1 title:fg=accent)
  [[ $design == quiet ]] && panel_style+=(bg=canvas py=1)
  if [[ $layout_mode != single || $focus == list ]]; then
    zdraw-panel stdscr "${rail[@]}" ' Changes ' "$rail_state" "${panel_style[@]}" || return
    content=("${reply[@]}") visible=$reply[3]
    # A small breathing space after a borderless title keeps hierarchy clear.
    if [[ $design == quiet ]] && (( content[3] > 2 )); then
      zdraw-layout-inset "${content[@]}" 1 0 0 0 || return; content=("${reply[@]}") visible=$reply[3]
    fi
    zdraw-list-update "${#shown}" "$visible" keep || return
    if (( content[3] && content[4] )); then
      labels=("${navigation[@]}")
      [[ $scenario == empty ]] && labels=()
      # Some 8/16-color terminals brighten bold black into a lower-contrast gray.
      [[ $profile == 16 ]] && list_style+=(selected:no-bold)
      if [[ $design == workbench ]]; then
        local -i i
        for (( i=1; i<=${#labels}; i++ )); do labels[$i]="$i  $labels[$i]"; done
      fi
      zdraw-list stdscr "${content[@]}" "$rail_state" empty-text='No changes. Press r.' "${list_style[@]}" -- "${labels[@]}" || return
    fi
  fi
  if [[ $layout_mode != single || $focus == detail ]]; then
    zdraw-panel stdscr "${notes[@]}" ' Details ' "$notes_state" "${panel_style[@]}" || return
    content=("${reply[@]}")
    if [[ $design == quiet ]]; then
      zdraw-layout-center "${content[@]}" "$content[3]" 68 || return; content=("${reply[@]}")
    fi
    study-detail "${content[@]}" || return
  fi
  if (( ${#context} )); then
    zdraw-panel stdscr "${context[@]}" ' Context ' normal "${panel_style[@]}" || return
    content=("${reply[@]}")
    study-line "${content[@]}" 1 'WORKSPACE' fg=muted || return
    study-line "${content[@]}" 2 'fieldwork / local' bold || return
    study-line "${content[@]}" 4 'BRANCH' fg=muted || return
    study-line "${content[@]}" 5 'input-care' || return
    study-line "${content[@]}" 7 'REVIEW' fg=muted || return
    study-line "${content[@]}" 8 "$state_label" fg=accent || return
    study-line "${content[@]}" 10 'No files modified.' fg=muted || return
    study-line "${content[@]}" 12 'Simulated local data.' fg=muted || return
  fi
  local -a footer=("$((rows-3))" "$frame[2]" 3 "$frame[4]")
  if [[ $scenario == busy ]]; then
    zdraw-meter stdscr "$footer[1]" "$footer[2]" "$footer[4]" "$progress" 5 normal bg=canvas || return
  else
    local hint="${(C)design} / $scenario   Focus: $focus   Simulated data"
    [[ $scenario == error ]] && hint='Check failed. Press r to retry; your selection is preserved.'
    (( frame[4] < 64 )) && hint="$design / $scenario | $focus"
    study-line "${footer[@]}" 0 "$hint" bg=canvas fg=muted || return
  fi
  shortcuts=(q quit Tab focus j/k move PgUp/PgDn page r retry)
  [[ $scenario == busy ]] && shortcuts=(q quit Space step Tab focus j/k move)
  [[ $scenario == error || $scenario == empty ]] && shortcuts=(q quit r retry Tab focus j/k move)
  zdraw-help stdscr "$((rows-2))" "$frame[2]" "$frame[4]" normal -- "${shortcuts[@]}" || return
  zdraw-help stdscr "$((rows-1))" "$frame[2]" "$frame[4]" normal -- 1/2/3 design s state m mono || return
  zdraw refresh stdscr
}

function study-state {
  emulate -L zsh
  [[ $scenario != empty ]] && saved_selection=${zdraw_ui_list[selected]:-1}
  scenario=$1 progress=3 detail_offset=0
  if [[ $scenario == empty ]]; then
    zdraw-list-update 0 0 keep
  else
    zdraw_ui_list[selected]=$saved_selection
    zdraw-list-update "${#tasks}" "$visible" keep
  fi
}

zdraw init || exit 1
{
  zdraw colorinfo colors || exit 1
  typeset color_profile=mono
  if [[ $colors[colors] == <-> && $colors[has_colors] == 1 && $colors[color_started] == 1 ]]; then
    (( colors[colors] >= 8 )) && color_profile=16
    (( colors[colors] == 256 )) && color_profile=256
  fi
  case $requested_profile in
    mono) color_profile=mono ;;
    16) [[ $color_profile == 256 ]] && color_profile=16 ;;
    256|auto) ;; # Never force unavailable indexed colors or mistake direct RGB for indices.
  esac
  [[ -n ${NO_COLOR:-} ]] && color_profile=mono
  zdraw-list-update "${#tasks}" 0 keep || exit 1
  study-state "$scenario" || exit 1
  zdraw timeout stdscr 100 || exit 1
  while true; do
    if (( dirty )); then
      study-render || { exit_code=1; break; }
      dirty=0
    fi
    if zdraw event stdscr event "${input_options[@]}"; then
      typeset action=keep
      case $event[type] in
        character)
          case $event[text] in
            q|$'\x03') break ;;
            $'\e') if [[ $focus == detail ]]; then focus=list; else break; fi ;;
            1|2|3) design=$design_names[$event[text]] ;;
            s) study-state "$state_names[$(( ${state_names[(Ie)$scenario]} % 4 + 1 ))]" || { exit_code=1; break; } ;;
            m) monochrome=$((!monochrome)) ;;
            r) study-state busy || { exit_code=1; break; } ;;
            ' ') [[ $scenario == busy ]] || continue
              (( progress++ ))
              (( progress >= 5 )) && study-state ready ;;
            $'\t'|$'\r'|$'\n') if [[ $focus == list ]]; then focus=detail; else focus=list; fi ;;
            j) action=down ;; k) action=up ;;
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
      if [[ $focus == list && $action != keep ]]; then
        typeset -i previous=${zdraw_ui_list[selected]}
        zdraw-list-update "${#shown}" "$visible" "$action" || { exit_code=1; break; }
        (( previous != zdraw_ui_list[selected] )) && detail_offset=0
      else
        case $action in
          up) (( detail_offset-- )) ;; down) (( detail_offset++ )) ;;
          home) detail_offset=0 ;; end) detail_offset=$detail_count ;;
          page-up) (( detail_offset-=detail_visible )) ;; page-down) (( detail_offset+=detail_visible )) ;;
        esac
      fi
      dirty=1
    fi
  done
} always {
  zdraw end || exit_code=1
}
exit "$exit_code"
