#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
typeset root=${0:A:h:h} logfile=${0:A:h:h}/.build/ui-component-diagnostics-$$.log
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
for component in form document tabs meter badge help; do
  source "$root/lib/zdraw-$component.zsh" || exit 1
done
module_path=("$1")
zmodload zdraw || exit 1

# Exercise real headless text geometry, with controlled rendering failures.
# The retained-cell and PTY tests separately exercise actual drawing.
typeset native_failure='' mode log previous delta
typeset -i paints=0
function zdraw {
  [[ $1 != "$native_failure" ]] || return 7
  case $1 in
    position) set -A "$3" 0 0 0 0 24 80 ;;
    fill|spans|spansclip) (( paints++ )); return 0 ;;
    *) builtin zdraw "$@" ;;
  esac
}
expect() {
  local expected=$1 message=$2 result previous=$(<"$logfile") log delta
  shift 2
  "$@"
  result=$?
  [[ $result == $expected ]] || fail "expected $expected, got $result: $1"
  log=$(<"$logfile")
  if [[ $mode == enabled && -n $message ]]; then
    [[ $log != "$previous" ]] || fail "missing diagnostic from $1"
    delta=${log[${#previous}+1,-1]}
    [[ $delta == *"$message"* && $delta == *"(status $expected)"* ]] || fail "wrong diagnostic: $delta"
  else
    [[ $log == "$previous" ]] || fail "unexpected diagnostic from $1"
  fi
}
same() {
  local -A actual=("$@")
  local field
  [[ ${#before} == ${#actual} ]] || fail 'association size changed'
  for field in "${(@k)before}"; do
    [[ ${actual[$field]-} == "$before[$field]" ]] || fail "changed key: $field"
  done
}
exercise() {
  local -A zdraw_ui_input zdraw_ui_form zdraw_ui_document zdraw_ui_theme before
  local zdraw_ui_error=sentinel
  expect 0 '' zdraw-ui-theme dark mono
  () {
    local zdraw_ui_input=wrong-type
    expect 1 'writable zdraw_ui_input' zdraw-input-init secret-input
  }
  () {
    local -Ar zdraw_ui_form=(sentinel unchanged)
    expect 1 'writable zdraw_ui_form' zdraw-form-init Label text ''
    expect 2 'writable zdraw_ui_form' zdraw-form-action validate
  }
  () {
    local -Ar zdraw_ui_document=(sentinel unchanged)
    expect 1 'writable zdraw_ui_document' zdraw-document-init 8
  }
  expect 0 '' zdraw-input-init '' 4
  expect 1 '' zdraw-input-check required
  [[ $zdraw_ui_error == 'This field is required.' ]] || fail 'validation message lost'
  zdraw_ui_error=sentinel
  expect 2 'unknown input validation rule' zdraw-input-check required secret-rule
  [[ $zdraw_ui_error == sentinel ]] || fail 'bad rule changed output'
  expect 2 'unsigned integer' zdraw-input-check 'min=evil=1'
  (( ! ${+evil} )) || fail 'rule evaluated arithmetic'
  before=("${(@kv)zdraw_ui_input}")
  expect 1 'unknown input edit action' zdraw-input-edit secret-action
  expect 1 'initial text exceeds' zdraw-input-init secret-input 4
  expect 1 'edit exceeds' zdraw-input-edit insert secret-input
  same "${(@kv)zdraw_ui_input}"
  expect 0 '' zdraw-input-init 界 4
  zdraw_ui_input[cursor]=1
  expect 1 'cursor/anchor must be text boundaries' zdraw-input-edit left
  expect 2 'invalid for validation' zdraw-input-check required
  expect 0 '' zdraw-input-init abc 4
  expect 0 '' zdraw-input-paste begin
  expect 1 'paste is already active' zdraw-input-edit clear
  expect 1 'paste exceeds' zdraw-input-paste data secret-payload
  [[ $zdraw_ui_input[paste_failed] == 1 && -z $zdraw_ui_input[paste_buffer] ]] || fail 'paste drain state lost'
  expect 1 'drain to end or cancel' zdraw-input-paste data secret-payload
  expect 1 'rejected paste discarded' zdraw-input-paste end
  [[ $zdraw_ui_input[paste_active] == 0 && $zdraw_ui_input[paste_failed] == 0 &&
     $zdraw_ui_input[text] == abc ]] || fail 'paste cleanup changed'
  expect 0 '' zdraw-form-init Name '' required
  expect 1 '' zdraw-form-action validate
  [[ $zdraw_ui_form[1,error] == 'This field is required.' ]] || fail 'form validation message lost'
  before=("${(@kv)zdraw_ui_form}")
  expect 2 'unknown form action' zdraw-form-action secret-action
  expect 1 'invalid input state or rules' zdraw-form-init Name secret-input secret-rule
  same "${(@kv)zdraw_ui_form}"
  expect 0 '' zdraw-form-action paste begin
  before=("${(@kv)zdraw_ui_form}")
  expect 2 'finish or cancel' zdraw-form-action next
  same "${(@kv)zdraw_ui_form}"
  expect 1 'paste exceeds' zdraw-form-action paste data "${(l:4097::x:):-}"
  expect 1 'rejected paste discarded' zdraw-form-action paste end
  [[ $zdraw_ui_form[1,paste_active] == 0 && $zdraw_ui_form[1,paste_failed] == 0 ]] || fail 'form paste cleanup lost'
  expect 0 '' zdraw-document-init 8 intro paragraph 界
  before=("${(@kv)zdraw_ui_document}")
  expect 1 'duplicate document block ID' zdraw-document-init 8 same heading secret-document same paragraph text
  expect 1 'anchor does not identify' zdraw-document-scroll 3 anchor secret-anchor
  expect 2 'does not fit' zdraw-document-reflow 1
  same "${(@kv)zdraw_ui_document}"
  paints=0
  expect 1 'reflow before drawing' zdraw-document sample 0 0 3 4 normal
  expect 2 'at least three rows' zdraw-form sample 0 0 2 8 focus
  expect 1 'input requires border=none' zdraw-input sample 0 0 8 focus px=1
  expect 1 'missing --' zdraw-tabs sample 0 0 8 1 focus Label
  expect 1 'valid selection' zdraw-tabs sample 0 0 8 2 focus -- Label
  expect 1 'must not exceed total' zdraw-meter sample 0 0 8 3 2 normal
  expect 1 'label must be on or off' zdraw-meter sample 0 0 8 1 2 normal label=secret-label
  expect 1 'occupy one cell' zdraw-meter sample 0 0 8 1 2 normal fill-char=界
  expect 1 'key/description pairs' zdraw-help sample 0 0 8 normal -- key
  () {
    local zdraw_ui_theme=wrong-type
    expect 1 'zdraw_ui_theme association' zdraw-badge sample 0 0 8 Text normal
  }
  (( paints == 0 )) || fail 'validation painted cells'
  native_failure=textpos
  before=("${(@kv)zdraw_ui_input}")
  expect 7 'native textpos failed' zdraw-input-init secret-input
  expect 7 'native textpos failed' zdraw-input-edit left
  expect 2 'invalid for validation' zdraw-input-check required
  same "${(@kv)zdraw_ui_input}"
  native_failure=textinfo
  expect 7 'native textinfo failed' zdraw-form-init Name secret-input ''
  expect 7 'native textinfo failed' zdraw-document-init 8 intro paragraph secret-document
  native_failure=fill
  expect 7 'native fill failed' zdraw-input sample 0 0 8 focus
  expect 7 'native fill failed' zdraw-form sample 0 0 3 8 focus
  expect 7 'native fill failed' zdraw-document sample 0 0 3 8 normal
  expect 7 'native fill failed' zdraw-tabs sample 0 0 8 1 focus -- Label
  expect 7 'native fill failed' zdraw-meter sample 0 0 8 1 2 normal
  expect 7 'native fill failed' zdraw-badge sample 0 0 8 Text normal
  expect 7 'native fill failed' zdraw-help sample 0 0 8 normal -- q Quit
  native_failure=spans
  expect 7 'native spans failed' zdraw-help sample 0 0 8 normal -- q Quit
  native_failure=spansclip
  expect 7 'native spansclip failed' zdraw-input sample 0 0 8 focus
  native_failure=''
}
{
  : > "$logfile"
  for mode in absent enabled closed malformed; do
    case $mode in
      enabled) exec {ZDRAW_UI_DEBUG_FD}>>"$logfile" ;;
      closed) exec {ZDRAW_UI_DEBUG_FD}>&- ;;
      malformed) unset ZDRAW_UI_DEBUG_FD; ZDRAW_UI_DEBUG_FD='1+evil=1' ;;
    esac
    exercise
    if [[ $mode == enabled ]]; then
      print -r -u "$ZDRAW_UI_DEBUG_FD" -- 'caller still owns descriptor'
    fi
  done
  log=$(<"$logfile")
  [[ $log != *secret-* && $log == *'caller still owns descriptor'* ]] || fail 'diagnostic payload or descriptor contract'
  (( ! ${+evil} && ${#zdraw_windows} == 0 )) || fail 'diagnostics evaluated data or initialized curses'
} always {
  unset ZDRAW_UI_DEBUG_FD
  rm -f -- "$logfile"
}
print -r -- 'UI COMPONENT DIAGNOSTICS PASS'
