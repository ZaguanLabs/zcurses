#!/usr/bin/env zsh
# Simulated task updates. Components never run work or own input/timers.
emulate -R zsh
setopt nounset
typeset example_root=${0:A:h:h}
module_path=("$example_root/.build/modules")
zmodload zdraw || exit 1
source "$example_root/examples/components/status-strip.zsh" || exit 1
source "$example_root/lib/zdraw-help.zsh" || exit 1
typeset -A zdraw_ui_theme event colors
typeset -a dimensions input_options progress_options overrides
typeset theme_name=dark profile=mono requested_profile=auto phase=working layout_mode=tiny detail
typeset -i rows columns height=2 known=1 value=7 compact=0 variant=0 dirty=1 exit_code=0
while (( $# )); do
  case $1 in
    --theme) theme_name=$2; shift ;;
    --profile) requested_profile=$2; shift ;;
    --phase) phase=$2; shift ;;
    --unknown) known=0 ;;
    --compact) compact=1 ;;
    --variant) variant=1 ;;
    *) print -ru2 -- "unknown option: $1"; exit 1 ;;
  esac
  shift
done
[[ $theme_name == (dark|light) && $requested_profile == (auto|mono|16|256) && $phase == (working|waiting|done|failed) ]] || exit 1
[[ $phase == done ]] && value=12
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)

function status-render {
  emulate -L zsh
  local -A zdraw_ui_style
  local -i y
  zdraw position stdscr dimensions || return
  rows=$dimensions[5] columns=$dimensions[6]
  zdraw-ui-theme "$theme_name" "$profile" || return
  zdraw-ui-style normal fg=text bg=canvas || return
  zdraw fill stdscr 0 0 "$rows" "$columns" "$zdraw_ui_style[style]" ' ' || return
  zdraw-label stdscr 0 0 "$columns" 'WORK / review session' normal fg=accent bg=canvas bold || return
  layout_mode=tiny
  if (( rows<15 || columns<26 )); then
    (( rows>1 )) && zdraw-label stdscr 1 0 "$columns" 'q quit; resize to explore' normal bg=canvas
    zdraw refresh stdscr
    return
  fi
  height=2
  (( compact || rows<19 )) && height=1
  layout_mode=detail
  (( height==1 )) && layout_mode=compact
  case $phase in
    working) detail='Scanning module headers' ;;
    waiting) detail='Waiting for the source tree' ;;
    done) detail='All source checks completed' ;;
    failed) detail='Stopped at the parser check' ;;
  esac
  progress_options=() overrides=()
  (( known )) && progress_options=("value=$value" total=12)
  (( variant )) && overrides=(title:no-bold key:reverse)
  zdraw-status-strip stdscr 2 1 "$height" "$((columns-2))" "$phase" 'Check source files' "$detail" \
    "${progress_options[@]}" "${overrides[@]}" || return
  y=$((height+4))
  zdraw-label stdscr "$y" 1 "$((columns-2))" 'OTHER TASKS' normal fg=muted bg=canvas || return
  (( y+=2 ))
  zdraw-status-strip stdscr "$y" 1 "$height" "$((columns-2))" waiting 'Publish documentation' 'Awaiting review' || return
  (( y+=height+1 ))
  zdraw-status-strip stdscr "$y" 1 "$height" "$((columns-2))" done 'Index sources' '18 source files indexed' || return
  (( y+=height+1 ))
  zdraw-status-strip stdscr "$y" 1 "$height" "$((columns-2))" failed 'Run checks' 'One parser check failed' || return
  zdraw-label stdscr "$((rows-3))" 1 "$((columns-2))" 'Sample tasks; no work is run.' normal fg=muted bg=canvas || return
  zdraw-help stdscr "$((rows-2))" 1 "$((columns-2))" normal -- q quit 1-4 state Space advance || return
  zdraw-help stdscr "$((rows-1))" 1 "$((columns-2))" normal -- p total c compact t theme v treatment m mono || return
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
    if (( dirty )); then status-render || { exit_code=1; break; }; dirty=0; fi
    if zdraw event stdscr event "${input_options[@]}"; then
      case $event[type] in
        character)
          case $event[text] in
            q|$'\e') break ;;
            1) phase=working value=7 ;; 2) phase=waiting ;; 3) phase=done value=12 ;; 4) phase=failed ;;
            ' ')
              if [[ $phase == working ]]; then
                (( value<12 )) && (( value++ ))
                (( value==12 )) && phase=done
              fi ;;
            p) (( known=!known )) ;;
            c) (( compact=!compact )) ;;
            t) if [[ $theme_name == dark ]]; then theme_name=light; else theme_name=dark; fi ;;
            v) (( variant=!variant )) ;;
            m)
              if [[ $profile == mono ]]; then
                (( colors[colors]>=8 )) && profile=16
                (( colors[colors]>=256 )) && profile=256
              else profile=mono; fi ;;
            *) continue ;;
          esac ;;
        resize) zdraw resize "$event[rows]" "$event[columns]" nosave || { exit_code=1; break; } ;;
        *) continue ;;
      esac
      dirty=1
    fi
  done
} always {
  zdraw end || exit_code=1
}
exit "$exit_code"
