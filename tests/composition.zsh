#!/usr/bin/env zsh
# Present the real recipe one frame at a time for deterministic PTY assertions.
emulate -R zsh
typeset report_fd=$1 control_fd=$2 example=$3
[[ $example == (form|document) ]] || exit 1
function zdraw {
  builtin zdraw "$@" || return
  case $1 in
    refresh)
      if [[ $example == form ]]; then
        print -r -u "$report_fd" -- "frame $rows $columns $zdraw_ui_form[focus] $submitted ${#zdraw_ui_form[1,text]} ${#zdraw_ui_form[1,error]} $zdraw_ui_form[1,paste_active]"
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
if [[ $example == form ]]; then
  source "${0:A:h:h}/examples/$example.zsh" --paste
else
  source "${0:A:h:h}/examples/$example.zsh"
fi
