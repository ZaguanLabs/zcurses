#!/usr/bin/env zsh
# Present the real recipe one frame at a time for deterministic PTY assertions.
emulate -R zsh
typeset report_fd=$1 control_fd=$2 example=$3
[[ $example == (form|form-enhanced|events-enhanced|document|canvas|capabilities|overlays|stacking) ]] || exit 1
typeset -a test_stage_order
function zdraw {
  builtin zdraw "$@" || return
  case $1 in
    stage)
      [[ $2 == stdscr ]] && test_stage_order=()
      test_stage_order+=("${@:2}") ;;
    refresh|present)
      if [[ $example == stacking ]]; then
        print -r -u "$report_fd" -- "frame $y $x $visible $reverse_order ${(j:,:)test_stage_order}"
      elif [[ $example == overlays ]]; then
        local -A pixels
        builtin zdraw snapshot stdscr pixels || return
        if (( rows >= 12 && cols >= 42 && y == 5 && x == 16 && !moved && !view )); then
          local face=' ' hole=.
          (( shown && !reversed )) && face=F
          (( shown && !transparent )) && hole=' '
          [[ $pixels[5,16,text] == "$face" && $pixels[8,16,text] == "$hole" ]] || {
            print -ru2 -- 'overlay composition mismatch'; return 1
          }
        fi
        print -r -u "$report_fd" -- "frame $rows $cols $y $x $height $width $shown $transparent $reversed $moved $view"
      elif [[ $example == form-enhanced ]]; then
        print -r -u "$report_fd" -- "frame $application_focused $zdraw_ui_form[focus] $submitted ${#zdraw_ui_form[1,text]} ${example_protocol_current:-done} $example_keyboard_active"
      elif [[ $example == events-enhanced ]]; then
        print -r -u "$report_fd" -- "frame $event[type] ${event[source]:-none} ${event[action]:-none} ${example_protocol_current:-done} $example_keyboard_active"
      elif [[ $example == form ]]; then
        print -r -u "$report_fd" -- "frame $rows $columns $zdraw_ui_form[focus] $submitted ${#zdraw_ui_form[1,text]} ${#zdraw_ui_form[1,error]} $zdraw_ui_form[1,paste_active]"
      elif [[ $example == capabilities ]]; then
        print -r -u "$report_fd" -- "frame $size[1] $size[2] $next $cap[query_owner] $cap[synchronized_output,support] $cap[synchronized_output,source] $cap[streaming_paste,support] $cap[streaming_paste,enabled]"
      elif [[ $example == canvas ]]; then
        print -r -u "$report_fd" -- "frame $rows $columns $mode $canvas_palette $empty $theme_name $profile $zdraw_ui_canvas[count] ${zdraw_ui_canvas_raster[pixels]:-0}"
      else
        local test_doc_top=$zdraw_ui_document[first]
        print -r -u "$report_fd" -- "frame $rows $columns $test_doc_top $zdraw_ui_document[columns] $zdraw_ui_document[$test_doc_top,block] $zdraw_ui_document[$test_doc_top,byte_start] $theme_name"
      fi
      local acknowledgement
      read -r -u "$control_fd" acknowledgement ;;
    end) print -r -u "$report_fd" -- done ;;
  esac
  return 0
}
print -r -u "$report_fd" -- baseline
read -r -u "$control_fd" acknowledgement
if [[ $example == (overlays|stacking) ]]; then
  typeset overlay_example=${0:A:h:h}/examples/$example.zsh
  () { source "$overlay_example"; }
elif [[ $example == form-enhanced ]]; then
  source "${0:A:h:h}/examples/form.zsh" --paste --focus --keyboard
elif [[ $example == events-enhanced ]]; then
  source "${0:A:h:h}/examples/events.zsh" --focus --keyboard
elif [[ $example == form ]]; then
  source "${0:A:h:h}/examples/$example.zsh" --paste
else
  source "${0:A:h:h}/examples/$example.zsh"
fi
