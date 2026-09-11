#!/usr/bin/env zsh
# Fictional review data; no file access, diff parser or patch application.
emulate -R zsh
setopt nounset
typeset example_root=${0:A:h:h}
module_path=("$example_root/.build/modules")
zmodload zdraw || exit 1
source "$example_root/examples/components/change-gutter.zsh" || exit 1
source "$example_root/lib/zdraw-help.zsh" || exit 1
typeset -A zdraw_ui_theme zdraw_ui_gutter event colors
typeset -a dimensions input_options records overrides
typeset theme_name=dark profile=mono requested_profile=auto glyphs=auto number_mode=auto layout_mode=tiny
typeset -i rows columns first=1 offset=0 visible=1 dirty=1 exit_code=0 empty=0 variant=0
while (( $# )); do
  case $1 in
    --theme) theme_name=$2; shift ;;
    --profile) requested_profile=$2; shift ;;
    --ascii) glyphs=ascii ;;
    --empty) empty=1 ;;
    --variant) variant=1 ;;
    *) print -ru2 -- "unknown option: $1"; exit 1 ;;
  esac
  shift
done
[[ $theme_name == (dark|light) && $requested_profile == (auto|mono|16|256) ]] || exit 1
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)
records=(
  hunk - - '@@ Input ownership / draft.zsh @@'
  context 41 41 'function accept-event {'
  context 42 42 '  case $event[type] in'
  remove 43 - '    paste) submit "$event[text]" ;;'
  add - 43 '    paste) draft+=$event[text] ;;'
  add - 44 '    # A paste stays editable until the user submits it.'
  context 44 45 '    character) draft+=$event[text] ;;'
  context 45 46 '  esac'
  context 46 47 '}'
  hunk - - '@@ Terminal handoff / session.zsh @@'
  context 108 109 'zdraw init || return 1'
  remove 109 - 'run-interface'
  remove 110 - 'zdraw end'
  add - 110 '{'
  add - 111 '  run-interface'
  add - 112 '} always {'
  add - 113 '  zdraw end'
  add - 114 '}'
  context 111 115 ''
  hunk - - '@@ Review note / notes.txt @@'
  remove 7 - 'A paste submits immediately.'
  add - 7 'A paste remains in the draft. Review it, edit it, and submit only when it says what you mean.'
)

function gutter-render {
  emulate -L zsh
  local -A zdraw_ui_style
  local -a content=("${records[@]}")
  local review_status
  zdraw position stdscr dimensions || return
  rows=$dimensions[5] columns=$dimensions[6]
  zdraw-ui-theme "$theme_name" "$profile" || return
  zdraw-ui-style normal fg=text bg=canvas || return
  zdraw fill stdscr 0 0 "$rows" "$columns" "$zdraw_ui_style[style]" ' ' || return
  zdraw-label stdscr 0 0 "$columns" 'REVIEW / keep the draft in your hands' normal fg=accent bg=canvas bold || return
  layout_mode=tiny
  if (( rows<8 || columns<24 )); then
    (( rows>1 )) && zdraw-label stdscr 1 0 "$columns" 'q quit; resize to read' normal bg=canvas
    zdraw refresh stdscr
    return
  fi
  (( empty )) && content=()
  overrides=()
  if (( variant )); then
    if [[ $profile == mono ]]; then overrides=(positive:bold negative:bold)
    else overrides=(positive:bg=canvas negative:bg=canvas positive:fg=accent negative:fg=error); fi
  fi
  zdraw-change-gutter stdscr 2 1 "$((rows-5))" "$((columns-2))" "$first" \
    "numbers=$number_mode" "offset=$offset" "glyphs=$glyphs" "${overrides[@]}" -- "${content[@]}" || return
  first=$zdraw_ui_gutter[first] offset=$zdraw_ui_gutter[offset] visible=$zdraw_ui_gutter[visible] layout_mode=$zdraw_ui_gutter[numbers]
  review_status="Row $first/$zdraw_ui_gutter[count]  Text column $((offset+1))  + added / - removed"
  (( !zdraw_ui_gutter[count] )) && review_status='0 changes'
  zdraw-label stdscr "$((rows-3))" 1 "$((columns-2))" "$review_status" normal fg=muted bg=canvas || return
  zdraw-help stdscr "$((rows-2))" 1 "$((columns-2))" normal -- q quit j/k scroll h/l pan 0 left || return
  zdraw-help stdscr "$((rows-1))" 1 "$((columns-2))" normal -- t theme n numbers e empty v treatment m mono || return
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
    if (( dirty )); then gutter-render || { exit_code=1; break; }; dirty=0; fi
    if zdraw event stdscr event "${input_options[@]}"; then
      case $event[type] in
        character)
          case $event[text] in
            q|$'\e') break ;;
            j) (( first++ )) ;; k) (( first-- )) ;;
            h) (( offset-=4 )) ;; l) (( offset+=4 )) ;; 0) offset=0 ;;
            t) if [[ $theme_name == dark ]]; then theme_name=light; else theme_name=dark; fi ;;
            n) if [[ $number_mode == auto ]]; then number_mode=single; else number_mode=auto; fi ;;
            e) (( empty=!empty )); first=1 offset=0 ;;
            v) (( variant=!variant )) ;;
            m)
              if [[ $profile == mono ]]; then
                (( colors[colors]>=8 )) && profile=16
                (( colors[colors]>=256 )) && profile=256
              else profile=mono; fi ;;
            *) continue ;;
          esac ;;
        key)
          case $event[key] in
            UP) (( first-- )) ;; DOWN) (( first++ )) ;;
            LEFT) (( offset-=4 )) ;; RIGHT) (( offset+=4 )) ;;
            HOME) first=1 ;; END) first=32767 ;;
            NPAGE) (( first+=visible )) ;; PPAGE) (( first-=visible )) ;; *) continue ;;
          esac ;;
        resize) zdraw resize "$event[rows]" "$event[columns]" nosave || { exit_code=1; break; } ;;
        *) continue ;;
      esac
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
