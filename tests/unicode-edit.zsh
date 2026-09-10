#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
zmodload zdraw || exit 1
source "${0:A:h:h}/lib/zdraw-form.zsh" || exit 1
source "${0:A:h:h}/lib/zdraw-document.zsh" || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A zdraw_ui_input before zdraw_ui_form zdraw_ui_document p
typeset key
typeset family='👨‍👩‍👧‍👦' flag='🇳🇴' toned='👍🏽'
if [[ $2 == unavailable ]]; then
  zdraw textpos p abc byte 0 grapheme
  (( $? == 2 )) || fail 'unsupported status'
  zdraw textinfo p abc 2 grapheme
  (( $? == 2 )) || fail 'unsupported clip'
  print -r -- 'UNICODE EDIT PASS'
  exit 0
fi
check zdraw-input-init "A${toned}${flag}${family}B" 4096 grapheme
check zdraw-input-edit left
check zdraw-input-edit select-left
[[ $zdraw_ui_input[cursor] == 17 && $zdraw_ui_input[anchor] == 42 ]] || fail 'family selection bytes'
check zdraw-input-edit backspace
[[ $zdraw_ui_input[text] == "A${toned}${flag}B" ]] || fail 'family deletion'
check zdraw-input-edit left
check zdraw-input-edit delete
[[ $zdraw_ui_input[text] == "A${toned}B" ]] || fail 'flag deletion'
check zdraw-input-edit backspace
[[ $zdraw_ui_input[text] == AB ]] || fail 'modifier deletion'
check zdraw-input-edit insert "$family"
[[ $zdraw_ui_input[text] == "A${family}B" && $zdraw_ui_input[cursor] == 26 ]] || fail 'insertion anchor'
# Insertion/deletion can change boundaries across the splice point.
check zdraw-input-init '👩💻' 64 grapheme
check zdraw-input-edit home
check zdraw-input-edit right
check zdraw-input-edit insert $'\u200d'
[[ $zdraw_ui_input[text] == '👩‍💻' && $zdraw_ui_input[cursor] == 11 ]] || fail 'joiner splice'
check zdraw-input-init '🇳X🇴' 64 grapheme
check zdraw-input-edit home
check zdraw-input-edit right
check zdraw-input-edit delete
[[ $zdraw_ui_input[text] == "$flag" && $zdraw_ui_input[cursor] == 8 ]] || fail 'flag splice'
# Streaming paste accepts fragments only once the complete text validates.
check zdraw-input-init '' 64 grapheme
check zdraw-input-paste begin
check zdraw-input-paste data $'\xf0\x9f'
check zdraw-input-paste data $'\x91\x8d\xf0\x9f\x8f\xbd'
check zdraw-input-paste end
[[ $zdraw_ui_input[text] == "$toned" ]] || fail 'fragmented paste'
check zdraw-input-edit backspace
[[ -z $zdraw_ui_input[text] ]] || fail 'pasted modifier deletion'
# Default behavior and caller-owned byte anchors remain available.
check zdraw-input-init "$toned"
check zdraw-input-edit backspace
[[ $zdraw_ui_input[text] == '👍' ]] || fail 'default changed'
check zdraw-input-init "$toned" 64 grapheme
zdraw_ui_input[cursor]=4
before=("${(@kv)zdraw_ui_input}")
reject zdraw-input-edit delete
for key in "${(@k)before}"; do [[ $before[$key] == "$zdraw_ui_input[$key]" ]] || fail 'invalid anchor mutated'; done
check zdraw-input-init "$toned" 64 grapheme
before=("${(@kv)zdraw_ui_input}")
() { local LC_ALL=C; zdraw-input-edit left; (( $? == 2 )) || fail 'locale unavailable'; }
() { emulate -L zsh; unsetopt multibyte; zdraw-input-edit left; (( $? == 2 )) || fail 'option unavailable'; }
for key in "${(@k)before}"; do [[ $before[$key] == "$zdraw_ui_input[$key]" ]] || fail 'locale mutated'; done
# Form helpers retain each field's chosen policy.
check zdraw-form-init Name "$toned" ''
zdraw_ui_form[1,boundary]=grapheme
check zdraw-form-action edit backspace
[[ -z $zdraw_ui_form[1,text] && $zdraw_ui_form[1,boundary] == grapheme ]] || fail 'form boundary lost'
# Document reflow retains its default clipping units and source byte anchors.
check zdraw-document-init 2 one paragraph "${toned}AB"
[[ $zdraw_ui_document[1,text] == '👍' ]] || fail 'document default changed'
check zdraw-document-scroll 1 down
check zdraw-document-reflow 4
[[ $zdraw_ui_document[1,text] == "$toned" && $zdraw_ui_document[b,1,text] == "${toned}AB" ]] || fail 'reflow source'
[[ $zdraw_ui_document[first] == 1 ]] || fail 'reflow byte anchor'
# Failed explicit budgets and malformed policy never replace output.
p=(sentinel yes)
reject zdraw textpos p abc byte 0 bad
reject zdraw textinfo p abc 1 bad
[[ $p[sentinel] == yes ]] || fail 'invalid policy assignment'
typeset huge=${(pl:1048577::x:):-}
reject zdraw textpos p "$huge" byte 0 grapheme
[[ $p[sentinel] == yes ]] || fail 'byte bound assignment'
print -r -- 'UNICODE EDIT PASS'
