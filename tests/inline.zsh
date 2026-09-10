# Isolated interactive startup for the inline picker PTY tests.
module_path=("$ZDRAW_INLINE_ROOT/.build/modules")
fpath=("$ZDRAW_INLINE_ROOT/.build/functions" "${fpath[@]}")
zmodload zsh/parameter || return
source "$ZDRAW_INLINE_ROOT/examples/inline-picker.zsh" || return
source "$ZDRAW_INLINE_ROOT/lib/zdraw-screen.zsh" || return
zdraw-inline-setup || return
typeset -a zdraw_inline_items=('alpha beta' '$(not-executed)' '界')
typeset zdraw_inline_result=sentinel zdraw_inline_source_fd=${ZDRAW_INLINE_SOURCE_FD:-}
PROMPT='INLINE> ' RPROMPT=RIGHT
bindkey -e
functions[_inline_test_original_draw]=$functions[_zdraw_inline_draw]
function _zdraw_inline_draw {
  _inline_test_original_draw "$@" || return
  (( _zinline_fd >= 0 )) && inline_test_duplicate=$_zinline_fd
  local REPLY
  _zdraw_screen_hex "$POSTDISPLAY"
  print -r -u "$ZDRAW_INLINE_REPORT" -- "frame $_zinline_selected ${#_zinline_items} $_zinline_fd $REPLY"
}
function inline-test-pick {
  if [[ ${INLINE_TEST_DECORATE:-0} == 1 ]]; then
    POSTDISPLAY=$'\nexisting suffix'
    region_highlight=('0 2 bold memo=other-owner')
    MARK=1 REGION_ACTIVE=1
  fi
  local before=$BUFFER before_post=$POSTDISPLAY before_map=$KEYMAP
  local -i before_cursor=$CURSOR before_mark=$MARK before_region=$REGION_ACTIVE result
  local -a before_highlights=("${region_highlight[@]}")
  local -i inline_test_duplicate=-1
  if [[ -n $zdraw_inline_source_fd ]]; then
    [[ -e /dev/fd/$zdraw_inline_source_fd ]] || { print -r -u "$ZDRAW_INLINE_REPORT" -- 'FAIL missing original FD'; return 1; }
  fi
  zle zdraw-inline-pick
  result=$?
  local REPLY encoded_result encoded_buffer
  _zdraw_screen_hex "$zdraw_inline_result"; encoded_result=$REPLY
  _zdraw_screen_hex "$BUFFER"; encoded_buffer=$REPLY
  local -A info
  zdraw capabilities info
  print -r -u "$ZDRAW_INLINE_REPORT" -- "result $result $encoded_result $encoded_buffer $CURSOR $KEYMAP $info[session]"
  [[ $BUFFER == "$before" && $CURSOR == $before_cursor && $MARK == $before_mark && $REGION_ACTIVE == $before_region &&
     $POSTDISPLAY == "$before_post" && $KEYMAP == "$before_map" && "${(j:|:)region_highlight}" == "${(j:|:)before_highlights}" ]] || {
    print -r -u "$ZDRAW_INLINE_REPORT" -- 'FAIL editor state'; return 1
  }
  [[ -z ${${(M)${(k)widgets}:#zdraw-inline-<->-*}} ]] || { print -r -u "$ZDRAW_INLINE_REPORT" -- 'FAIL leaked widgets'; return 1; }
  [[ -z ${${(M)keymaps:#zdraw-inline-<->}} ]] || { print -r -u "$ZDRAW_INLINE_REPORT" -- 'FAIL leaked keymap'; return 1; }
  if (( inline_test_duplicate >= 0 )); then
    if [[ -e /dev/fd/$inline_test_duplicate ]] || zle -F -L "$inline_test_duplicate" >/dev/null; then
      print -r -u "$ZDRAW_INLINE_REPORT" -- 'FAIL leaked duplicate or watcher'; return 1
    fi
  fi
  if [[ -n $zdraw_inline_source_fd ]]; then
    [[ -e /dev/fd/$zdraw_inline_source_fd ]] || { print -r -u "$ZDRAW_INLINE_REPORT" -- 'FAIL closed borrowed FD'; return 1; }
  fi
  print -r -u "$ZDRAW_INLINE_REPORT" -- clean
}
zle -N inline-test-pick
bindkey '^X^I' inline-test-pick
function zle-line-init {
  print -r -u "$ZDRAW_INLINE_REPORT" -- ready
}
zle -N zle-line-init
