#!/usr/bin/env zsh
# Present the real recipe one frame at a time for deterministic PTY assertions.
emulate -R zsh
typeset report_fd=$1 control_fd=$2 example=$3
[[ $example == (form|form-enhanced|events-enhanced|document|canvas|capabilities) ]] || exit 1
function zdraw {
  builtin zdraw "$@" || return
  case $1 in
    refresh)
      if [[ $example == form-enhanced ]]; then
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
if [[ $example == form-enhanced ]]; then
  source "${0:A:h:h}/examples/form.zsh" --paste --focus --keyboard
elif [[ $example == events-enhanced ]]; then
  source "${0:A:h:h}/examples/events.zsh" --focus --keyboard
elif [[ $example == form ]]; then
  source "${0:A:h:h}/examples/$example.zsh" --paste
else
  source "${0:A:h:h}/examples/$example.zsh"
fi
