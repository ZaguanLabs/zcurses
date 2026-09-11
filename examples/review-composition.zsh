#!/usr/bin/env zsh
# Application composition only: fictional data, no file access or work execution.
emulate -R zsh
setopt nounset
typeset example_root=${0:A:h:h}
module_path=("$example_root/.build/modules")
zmodload zdraw || exit 1
source "$example_root/examples/components/linked-detail.zsh" || exit 1
source "$example_root/examples/components/change-gutter.zsh" || exit 1
source "$example_root/examples/components/status-strip.zsh" || exit 1
source "$example_root/lib/zdraw-help.zsh" || exit 1
typeset -A zdraw_ui_theme zdraw_ui_list=(selected 2 first 1) zdraw_ui_link zdraw_ui_gutter event colors
typeset -a reply dimensions input_options items records
typeset -a titles=(settings.zsh session.zsh parser.zsh notes.txt)
typeset -a summaries=('Done / defaults checked' 'Working / checking cleanup' 'Failed / check the parser' 'Waiting / review the wording')
typeset -a phases=(done working failed waiting)
typeset -a explanations=('All defaults checked' 'Checking terminal cleanup' 'Parser check needs attention' 'Awaiting editorial review')
typeset focus=list theme_name=dark profile=mono requested_profile=auto glyphs=auto layout_mode=tiny phase=working
typeset -i rows columns first=1 offset=0 visible=1 dirty=1 exit_code=0 empty=0 variant=0 selected=2
typeset -i compact=0 status_height=2 status_gap=1
typeset -i show_help=0 help_first=1
typeset -a review_keys=(
  Tab 'Switch pane' j/k 'Move file or row' Up/Down 'Move file or row'
  h/l 'Pan change text' 0 'Leftmost text' c 'Compact status'
  t 'Switch theme' v 'Status emphasis' m Monochrome e 'Empty sample'
  q/Esc 'Quit review' '?' 'Show these keys'
)
while (( $# )); do
  case $1 in
    --theme|--profile)
      (( $#>=2 )) || { print -ru2 -- "missing value: $1"; exit 1; }
      if [[ $1 == --theme ]]; then theme_name=$2; else requested_profile=$2; fi
      shift ;;
    --ascii) glyphs=ascii ;;
    --empty) empty=1 ;;
    --variant) variant=1 ;;
    --compact) compact=1 ;;
    --keys) show_help=1 ;;
    *) print -ru2 -- "unknown option: $1"; exit 1 ;;
  esac
  shift
done
[[ $theme_name == (dark|light) && $requested_profile == (auto|mono|16|256) ]] || exit 1
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)

function review-data {
  emulate -L zsh
  # The caller chooses which already-classified rows belong to the selection.
  case $selected in
    1) records=(hunk - - '@@ Defaults @@'
      remove 8 - 'typeset theme=light' add - 8 'typeset theme=dark'
      context 9 9 'typeset density=compact') ;;
    2) records=(hunk - - '@@ Restore terminal ownership @@'
      context 20 20 'zdraw init || return 1'
      remove 21 - 'run-interface' remove 22 - 'zdraw end'
      add - 21 '{' add - 22 '  run-interface' add - 23 '} always {'
      add - 24 '  zdraw end' add - 25 '}'
      context 23 26 ''
      context 24 27 '# Return to the shell with its terminal settings restored, including after an ordinary render failure.') ;;
    3) records=(hunk - - '@@ Preserve the draft @@'
      remove 43 - 'paste) submit "$event[text]" ;;'
      add - 43 'paste) draft+=$event[text] ;;'
      context 44 44 '# A paste remains editable until submission.') ;;
    4) records=(hunk - - '@@ Review instructions @@'
      remove 7 - 'Paste to submit.'
      add - 7 'Paste into the draft. Read it, edit it, then submit when it says what you mean.') ;;
    *) records=() ;;
  esac
}

function review-render {
  emulate -L zsh
  local -A zdraw_ui_style
  local -a body progress_options status_overrides
  local -i i
  zdraw position stdscr dimensions || return
  rows=$dimensions[5] columns=$dimensions[6]
  zdraw-ui-theme "$theme_name" "$profile" || return
  zdraw-ui-style normal fg=text bg=canvas || return
  zdraw fill stdscr 0 0 "$rows" "$columns" "$zdraw_ui_style[style]" ' ' || return
  if (( show_help )); then
    zdraw-label stdscr 0 0 "$columns" 'KEYS / review' normal fg=accent bg=canvas bold || return
    if (( rows<5 || columns<26 )); then
      if (( rows>1 )); then
        zdraw-label stdscr 1 0 "$columns" '? back; q quit; resize' normal bg=canvas || return
      fi
    else
      local -i key_count=$((${#review_keys}/2)) key_rows=$((rows-4)) last
      local key_label
      (( help_first>key_count-key_rows+1 )) && help_first=$((key_count-key_rows+1))
      (( help_first<1 )) && help_first=1
      last=$((help_first+key_rows-1))
      (( last>key_count )) && last=$key_count
      for (( i=help_first; i<=last; i++ )); do
        printf -v key_label '%-7s' "$review_keys[$((2*i-1))]"
        zdraw-help stdscr "$((2+i-help_first))" 1 "$((columns-2))" normal -- \
          "$key_label" "$review_keys[$((2*i))]" || return
      done
      zdraw-label stdscr "$((rows-2))" 1 "$((columns-2))" "j/k scroll keys $help_first-$last/$key_count" normal fg=muted bg=canvas || return
      zdraw-help stdscr "$((rows-1))" 1 "$((columns-2))" normal -- q quit '?' back Esc back || return
    fi
    zdraw refresh stdscr
    return
  fi
  zdraw-label stdscr 0 0 "$columns" 'REVIEW / terminal ownership' normal fg=accent bg=canvas bold || return
  layout_mode=tiny
  if (( rows<11 || columns<26 )); then
    (( rows>1 )) && zdraw-label stdscr 1 0 "$columns" 'q quit; resize to review' normal bg=canvas
    zdraw refresh stdscr
    return
  fi
  # Density belongs to this application. Compact status returns two review rows.
  status_height=2 status_gap=1
  (( compact || rows<18 )) && { status_height=1; status_gap=0; }
  items=()
  if (( !empty )); then
    for (( i=1; i<=${#titles}; i++ )); do items+=("$titles[$i]" "$summaries[$i]"); done
  fi
  zdraw-linked-detail stdscr 2 1 "$((rows-5))" "$((columns-2))" "$focus" \
    list-title='FILES' detail-title='CHANGE / CHECK' item-gap=0 "glyphs=$glyphs" -- "${items[@]}" || return
  # Save the returned rectangle before calling another helper that uses reply.
  body=("${reply[@]}") visible=$zdraw_ui_link[visible] layout_mode=$zdraw_ui_link[mode]
  selected=$zdraw_ui_list[selected]
  phase=empty
  (( selected )) && phase=$phases[$selected]
  if (( body[3] && body[4] )); then
    if (( selected )); then
      case $phase in
        done) progress_options=(value=12 total=12) ;;
        working) progress_options=(value=7 total=12) ;;
        failed) progress_options=(value=3 total=12) ;;
      esac
      (( variant )) && status_overrides=(key:reverse title:no-bold)
      zdraw-status-strip stdscr "$body[1]" "$body[2]" "$status_height" "$body[4]" "$phase" \
        "$titles[$selected]" "$explanations[$selected]" "${progress_options[@]}" "${status_overrides[@]}" || return
      review-data
      zdraw-change-gutter stdscr "$((body[1]+status_height+status_gap))" "$body[2]" \
        "$((body[3]-status_height-status_gap))" "$body[4]" "$first" \
        "offset=$offset" "glyphs=$glyphs" -- "${records[@]}" || return
      first=$zdraw_ui_gutter[first] offset=$zdraw_ui_gutter[offset]
    else
      zdraw-label stdscr "$body[1]" "$body[2]" "$body[4]" 'No changes to review' normal bg=canvas || return
      zdraw-label stdscr "$((body[1]+1))" "$body[2]" "$body[4]" 'Press e to restore sample files.' normal fg=muted bg=canvas || return
    fi
  fi
  local hint='j/k files'
  [[ $focus == detail ]] && hint='j/k rows; h/l pan; 0 left'
  zdraw-label stdscr "$((rows-2))" 1 "$((columns-2))" "Tab pane; $hint" normal fg=muted bg=canvas || return
  zdraw-help stdscr "$((rows-1))" 1 "$((columns-2))" normal -- q quit '?' keys c compact t theme v status m mono e empty || return
  zdraw refresh stdscr
}

zdraw init || exit 1
{
  zdraw colorinfo colors || exit 1
  if [[ -z ${NO_COLOR:-} ]]; then
    (( colors[colors]>=8 )) && profile=16
    (( colors[colors]>=256 )) && profile=256
  fi
  [[ $requested_profile == mono ]] && profile=mono
  [[ $requested_profile == 16 && $profile == 256 ]] && profile=16
  zdraw timeout stdscr 100 || exit 1
  while true; do
    if (( dirty )); then review-render || { exit_code=1; break; }; dirty=0; fi
    if zdraw event stdscr event "${input_options[@]}"; then
      # The application owns help input. Review state remains untouched here.
      if (( show_help )); then
        case $event[type] in
          character)
            case $event[text] in
              q) break ;;
              '?'|$'\e') show_help=0 ;;
              j) (( help_first++ )) ;; k) (( help_first-- )) ;;
              *) continue ;;
            esac ;;
          key)
            case $event[key] in
              DOWN) (( help_first++ )) ;; UP) (( help_first-- )) ;; *) continue ;;
            esac ;;
          resize) zdraw resize "$event[rows]" "$event[columns]" nosave || { exit_code=1; break; } ;;
          *) continue ;;
        esac
        (( help_first<1 )) && help_first=1
        (( help_first>${#review_keys}/2 )) && help_first=$((${#review_keys}/2))
        dirty=1
        continue
      fi
      typeset action=keep
      case $event[type] in
        character)
          case $event[text] in
            q|$'\e') break ;;
            '?') show_help=1 help_first=1 ;;
            $'\t') if [[ $focus == list ]]; then focus=detail; else focus=list; fi ;;
            j) action=down ;; k) action=up ;;
            h) [[ $focus == detail ]] && (( offset-=4 )) ;;
            l) [[ $focus == detail ]] && (( offset+=4 )) ;;
            0) offset=0 ;;
            t) if [[ $theme_name == dark ]]; then theme_name=light; else theme_name=dark; fi ;;
            v) (( variant=!variant )) ;;
            c) (( compact=!compact )) ;;
            e) (( empty=!empty )); first=1 offset=0 ;;
            m)
              if [[ $profile == mono ]]; then
                (( colors[colors]>=8 )) && profile=16
                (( colors[colors]>=256 )) && profile=256
              else profile=mono; fi ;;
            *) continue ;;
          esac ;;
        key)
          case $event[key] in
            UP) action=up ;; DOWN) action=down ;; *) continue ;;
          esac ;;
        resize) zdraw resize "$event[rows]" "$event[columns]" nosave || { exit_code=1; break; } ;;
        *) continue ;;
      esac
      if [[ $action != keep && $layout_mode != tiny ]]; then
        if [[ $focus == list ]]; then
          zdraw-list-update "$(( ${#titles} * !empty ))" "$visible" "$action" || { exit_code=1; break; }
          if (( zdraw_ui_list[selected]!=selected )); then first=1 offset=0; fi
        elif (( selected )); then
          if [[ $action == down ]]; then (( first++ )); else (( first-- )); fi
        fi
      fi
      (( first<1 )) && first=1
      (( first>32767 )) && first=32767
      (( offset<0 )) && offset=0
      (( offset>32767 )) && offset=32767
      dirty=1
    fi
  done
} always {
  zdraw end || exit_code=1
}
exit "$exit_code"
