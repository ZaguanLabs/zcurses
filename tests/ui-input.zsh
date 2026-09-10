#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
typeset root=${0:A:h:h}
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
alias local='false ALIAS_LEAK'
setopt shwordsplit ksharrays globsubst
source "$root/lib/zdraw-form.zsh" || exit 1
[[ -o shwordsplit && -o ksharrays && -o globsubst ]] || fail options
unsetopt shwordsplit ksharrays globsubst
unalias local
zmodload -e zdraw && fail 'loader activated module'
module_path=("$1")
zmodload zdraw || exit 1
typeset -A zdraw_ui_input zdraw_ui_form
typeset zdraw_ui_error=sentinel
check zdraw-input-init $'ăe\u0301界b' 16
[[ $zdraw_ui_input[cursor] == 9 ]] || fail bytes
check zdraw-input-edit left
check zdraw-input-edit select-left
[[ $zdraw_ui_input[cursor] == 5 && $zdraw_ui_input[anchor] == 8 ]] || fail selection
check zdraw-input-edit insert X
[[ $zdraw_ui_input[text] == $'ăe\u0301Xb' && $zdraw_ui_input[cursor] == 6 ]] || fail replacement
check zdraw-input-edit backspace
check zdraw-input-edit backspace
[[ $zdraw_ui_input[text] == ăb && $zdraw_ui_input[cursor] == 2 ]] || fail 'combining deletion'
check zdraw-input-edit select-all
check zdraw-input-edit insert hello
check zdraw-input-edit home
check zdraw-input-edit delete
[[ $zdraw_ui_input[text] == ello ]] || fail delete
check zdraw-input-edit end
check zdraw-input-edit insert $'\u0301'
[[ $zdraw_ui_input[text] == $'ello\u0301' && $zdraw_ui_input[cursor] == 6 ]] || fail 'combining insertion'
check zdraw-input-edit home
reject zdraw-input-edit insert $'\u0301'
reject zdraw-input-edit insert $'\n'
reject zdraw-input-edit insert $'\e[31m'
reject zdraw-input-edit insert $'\0'
check zdraw-input-edit clear
check zdraw-input-init abc 4
check zdraw-input-edit select-all
check zdraw-input-paste begin
reject zdraw-input-edit insert z
check zdraw-input-paste data $'\xe7'
check zdraw-input-paste data $'\x95\x8c'
[[ $zdraw_ui_input[text] == abc ]] || fail 'paste changed text early'
check zdraw-input-paste end
[[ $zdraw_ui_input[text] == 界 && $zdraw_ui_input[cursor] == 3 ]] || fail 'split UTF-8 paste'
check zdraw-input-paste begin
check zdraw-input-paste data abc
reject zdraw-input-paste data de
reject zdraw-input-paste data f
reject zdraw-input-paste end
[[ $zdraw_ui_input[text] == 界 && $zdraw_ui_input[paste_active] == 0 ]] || fail 'oversize paste'
check zdraw-input-paste begin
check zdraw-input-paste data $'\xe7'
reject zdraw-input-paste end
check zdraw-input-paste begin
check zdraw-input-paste cancel
check zdraw-input-init ''
reject zdraw-input-check required
[[ $zdraw_ui_error == 'This field is required.' ]] || fail required
zdraw_ui_error=sentinel
reject zdraw-input-check required 'min=evil=1'
[[ $zdraw_ui_error == sentinel ]] || fail 'invalid rules not atomic'
check zdraw-input-init 65535
check zdraw-input-check required integer min=1 max=65535
reject zdraw-input-check max=65534
check zdraw-input-init 00080
check zdraw-input-check integer min=80 max=80
check zdraw-input-init $'e\u0301'
check zdraw-input-check min-length=2 max-length=2
zdraw_ui_input[cursor]='evil=1'
reject zdraw-input-edit left
(( ! ${+evil} )) || fail 'arithmetic injection'
check zdraw-input-init 界
zdraw_ui_input[cursor]=1
reject zdraw-input-edit left
() {
  local -A zdraw_ui_input
  local zdraw_ui_error
  check zdraw-input-init local
  check zdraw-input-check required
  [[ $zdraw_ui_input[text] == local ]] || fail 'local state'
}
() {
  local -Ar zdraw_ui_input=(sentinel yes)
  reject zdraw-input-init foo
  reject zdraw-input-edit clear
}
check zdraw-form-init Name '' required Port 80 required,integer,min=1,max=65535
reject zdraw-form-action validate
[[ $zdraw_ui_form[focus] == 1 && $zdraw_ui_form[1,error] == 'This field is required.' ]] || fail 'form invalid'
check zdraw-form-action edit insert Ada
check zdraw-form-action next
check zdraw-form-action edit select-all
check zdraw-form-action paste begin
reject zdraw-form-action next
check zdraw-form-action paste data 443
check zdraw-form-action paste end
check zdraw-form-action validate
[[ $zdraw_ui_form[1,text] == Ada && $zdraw_ui_form[2,text] == 443 && $zdraw_ui_form[focus] == 2 ]] || fail 'form values'
check zdraw-form-action next
[[ $zdraw_ui_form[focus] == 1 ]] || fail 'focus wrap'
check zdraw-form-action previous
[[ $zdraw_ui_form[focus] == 2 ]] || fail previous
check zdraw-form-action edit insert 999999
reject zdraw-form-action validate
[[ -n $zdraw_ui_form[2,error] && $zdraw_ui_form[focus] == 2 ]] || fail 'form range'
reject zdraw-form-init Bad ok 'required,bogus'
[[ $zdraw_ui_form[1,text] == Ada ]] || fail 'init not atomic'
(( ${#zdraw_windows} == 0 )) || fail 'headless initialized curses'
print -r -- 'UI INPUT PASS'
