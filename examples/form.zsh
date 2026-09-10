#!/usr/bin/env zsh
# Optional --paste enables bracketed paste; libraries never own terminal input.
emulate -R zsh
setopt nounset
typeset recipe_root=${0:A:h:h}
typeset paste_enabled='' message='A small form, ready for your application.'
typeset -a example_protocol_queue
typeset example_protocol_current='' protocol_note='' option
typeset -i example_keyboard_active=0
for option in "$@"; do
  case $option in
    --paste) paste_enabled=1 ;;
    --focus) example_protocol_queue+=(focus_events) ;;
    --keyboard) example_protocol_queue+=(keyboard_events) ;;
    *) print -ru2 -- 'usage: form.zsh [--paste] [--focus] [--keyboard]'; exit 1 ;;
  esac
done
example_protocol_queue=("${(@u)example_protocol_queue}")
source "$recipe_root/examples/input-protocols.zsh" || exit 1
module_path=("$recipe_root/.build/modules")
zmodload zdraw || exit 1
source "$recipe_root/lib/zdraw-form.zsh" || exit 1
source "$recipe_root/lib/zdraw-panel.zsh" || exit 1
source "$recipe_root/lib/zdraw-layout.zsh" || exit 1
typeset -A zdraw_ui_theme zdraw_ui_form event colors
typeset -a reply dimensions content input_options
typeset -i rows columns exit_code=0 submitted=0 dirty=1 application_focused=1
(( ${zdraw_features[(Ie)norefresh_events]} )) && input_options+=(norefresh)
zdraw-form-init 'Display name' '' required,max-length=40 'Port' 443 required,integer,min=1,max=65535 || exit 1
function recipe-render {
  emulate -L zsh
  local -A zdraw_ui_style
  local view_state=focus help='Tab fields / Enter validate / Esc quit'
  (( example_keyboard_active )) && help='Tab / Enter / Esc / Ctrl+Shift+S validate'
  (( application_focused )) || view_state=inactive
  zdraw position stdscr dimensions || return
  rows=$dimensions[5] columns=$dimensions[6]
  zdraw-ui-style normal fg=text bg=canvas || return
  zdraw fill stdscr 0 0 "$rows" "$columns" "$zdraw_ui_style[style]" ' ' || return
  if (( rows >= 14 && columns >= 28 )); then
    zdraw-layout-center 1 0 "$((rows-2))" "$columns" 12 64 || return
    zdraw-panel stdscr "${reply[@]}" ' CONNECTION / make it yours ' "$view_state" border=rounded px=2 title:fg=accent || return
    content=("${reply[@]}")
    zdraw-form stdscr "$content[1]" "$content[2]" 6 "$content[4]" "$view_state" || return
    zdraw-label stdscr "$((content[1]+7))" "$content[2]" "$content[4]" "$message" normal fg=muted || return
    zdraw-label stdscr "$((content[1]+8))" "$content[2]" "$content[4]" "$help | focus=$application_focused" normal fg=accent || return
  else
    zdraw-label stdscr 0 0 "$columns" 'Resize to edit / Esc quit' normal bg=canvas || return
  fi
  zdraw refresh stdscr
}
zdraw init || exit 1
{
  zdraw colorinfo colors || exit 1
  typeset profile=mono
  if [[ -z ${NO_COLOR:-} ]]; then
    (( colors[colors] >= 8 )) && profile=16
    (( colors[colors] >= 256 )) && profile=256
  fi
  zdraw-ui-theme dark "$profile" || exit 1
  zdraw timeout stdscr 100 || exit 1
  [[ -z $paste_enabled ]] || zdraw paste on || exit 1
  example-protocol-next
  while true; do
    if (( dirty )); then recipe-render || { exit_code=1; break; }; dirty=0; fi
    zdraw event stdscr event "${input_options[@]}" || continue
    if example-protocol-event; then dirty=1; continue; fi
    if [[ ${event[source]-} == kitty ]]; then
      [[ $event[type] == key && ${event[action]-} != release && ${event[supported]-} == yes ]] || continue
      case "$event[key]:$event[modifiers]" in
        ESC:|U+0063:CTRL) break ;;
        U+0073:'SHIFT CTRL'|ENTER:)
          if zdraw-form-action validate; then message='Validated. Your application can now use the values.' submitted=1
          else message='Check the highlighted field.' submitted=0; fi ;;
        U+0061:CTRL) zdraw-form-action edit select-all ;;
        TAB:SHIFT) zdraw-form-action previous ;; TAB:) zdraw-form-action next ;;
        LEFT:SHIFT) zdraw-form-action edit select-left ;; RIGHT:SHIFT) zdraw-form-action edit select-right ;;
        LEFT:) zdraw-form-action edit left ;; RIGHT:) zdraw-form-action edit right ;;
        HOME:) zdraw-form-action edit home ;; END:) zdraw-form-action edit end ;;
        BACKSPACE:) zdraw-form-action edit backspace ;; DC:) zdraw-form-action edit delete ;;
        *) [[ $event[text_status] == provided && -n $event[text] ]] && zdraw-form-action edit insert "$event[text]" 2>/dev/null ;;
      esac
      dirty=1
      continue
    fi
    case $event[type] in
      focus) application_focused=$event[focused] ;;
      character)
        case $event[text] in
          $'\e'|$'\x03') break ;;
          $'\t') zdraw-form-action next ;;
          $'\n'|$'\r')
            if zdraw-form-action validate; then
              message='Validated. Your application can now use the values.' submitted=1
            else message='Check the highlighted field.' submitted=0; fi ;;
          $'\x01') zdraw-form-action edit select-all ;;
          $'\x7f'|$'\b') zdraw-form-action edit backspace ;;
          *) zdraw-form-action edit insert "$event[text]" 2>/dev/null ;;
        esac ;;
      key)
        case $event[key] in
          LEFT) zdraw-form-action edit left ;; RIGHT) zdraw-form-action edit right ;;
          HOME) zdraw-form-action edit home ;; END) zdraw-form-action edit end ;;
          SLEFT) zdraw-form-action edit select-left ;; SRIGHT) zdraw-form-action edit select-right ;;
          BACKSPACE) zdraw-form-action edit backspace ;; DC) zdraw-form-action edit delete ;;
          BTAB) zdraw-form-action previous ;;
          *) continue ;;
        esac ;;
      paste)
        if [[ $event[phase] == data ]]; then
          zdraw-form-action paste data "$event[text]" 2>/dev/null
        else
          zdraw-form-action paste "$event[phase]" 2>/dev/null
        fi
        (( $? == 0 )) || message='Paste rejected: use printable text within the field limit.' ;;
      resize) zdraw resize "$event[rows]" "$event[columns]" nosave || { exit_code=1; break; } ;;
      *) continue ;;
    esac
    dirty=1
  done
} always {
  # end restores modes even when an input or drawing error aborts the recipe.
  zdraw end || exit_code=1
}
exit "$exit_code"
