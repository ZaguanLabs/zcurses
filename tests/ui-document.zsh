#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
typeset root=${0:A:h:h}
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
alias local='false ALIAS_LEAK'
setopt shwordsplit ksharrays globsubst
source "$root/lib/zdraw-document.zsh" || exit 1
[[ -o shwordsplit && -o ksharrays && -o globsubst ]] || fail options
unsetopt shwordsplit ksharrays globsubst
unalias local
zmodload -e zdraw && fail 'loader activated native module'
module_path=("$1")
zmodload zdraw || exit 1
same() {
  local -A actual=("$@")
  local field
  [[ ${#before} == ${#actual} ]] || fail 'association size changed'
  for field in "${(@k)before}"; do
    [[ ${actual[$field]-} == "$before[$field]" ]] || fail "changed key: $field"
  done
}
typeset -A zdraw_ui_document before info
typeset -i i top block offset
typeset row collected
check zdraw-document-init 8 intro heading 'Hello' prose paragraph 'alpha beta gamma' \
  first bullet 'one two three' second bullet 'four' quoted quote 'a thought' \
  snippet code $'  a b\n\nlast\n' line separator '' next subheading 'Next'
[[ $zdraw_ui_document[1,text] == Hello && $zdraw_ui_document[1,role] == heading &&
   $zdraw_ui_document[3,text] == 'alpha ' && $zdraw_ui_document[4,text] == 'beta ' &&
   $zdraw_ui_document[5,text] == gamma ]] || fail 'word wrapping'
[[ $zdraw_ui_document[7,text] == '- one ' && $zdraw_ui_document[8,text] == '  two ' &&
   $zdraw_ui_document[9,text] == '  three' && $zdraw_ui_document[10,text] == '- four' ]] || fail 'list continuation'
check zdraw-document-scroll 3 anchor snippet
top=$zdraw_ui_document[first]
[[ $zdraw_ui_document[$top,text] == '    a b' && $zdraw_ui_document[$((top+1)),text] == '  ' &&
   $zdraw_ui_document[$((top+2)),text] == '  last' && $zdraw_ui_document[$((top+3)),text] == '  ' ]] || fail 'code line preservation'
check zdraw-document-scroll 1 anchor prose
check zdraw-document-scroll 1 down
top=$zdraw_ui_document[first] block=$zdraw_ui_document[$top,block] offset=$zdraw_ui_document[$top,byte_start]
check zdraw-document-reflow 12
top=$zdraw_ui_document[first]
[[ $zdraw_ui_document[$top,block] == $block ]] || fail 'reflow block anchor'
(( zdraw_ui_document[$top,byte_start] <= offset && zdraw_ui_document[$top,byte_end] > offset )) || fail 'reflow byte anchor'
check zdraw-document-scroll 1 home
check zdraw-document-scroll 1 next-heading
top=$zdraw_ui_document[first]
[[ $zdraw_ui_document[$top,text] == Next ]] || fail 'next heading'
check zdraw-document-scroll 1 previous-heading
[[ $zdraw_ui_document[first] == 1 ]] || fail 'previous heading'
check zdraw-document-scroll 3 page-down
[[ $zdraw_ui_document[first] == 3 ]] || fail page
before=("${(@kv)zdraw_ui_document}")
for row in 'unknown' 'bad id' '$(touch SHOULD_NOT_EXIST)'; do
  reject zdraw-document-scroll 3 anchor "$row"
  same "${(@kv)zdraw_ui_document}"
done
reject zdraw-document-init 8 same heading Hello same paragraph duplicate
reject zdraw-document-init 8 bad unknown text
reject zdraw-document-init 8 bad separator text
reject zdraw-document-init 8 'bad id' paragraph text
reject zdraw-document-init 8 good paragraph ok bad code $'oops\e'
reject zdraw-document-init 8 good paragraph $'tab\there'
reject zdraw-document-init 'evil=1' good paragraph data
same "${(@kv)zdraw_ui_document}"
(( ! ${+evil} )) || fail injection
check zdraw-document-init 4 unicode paragraph $'ăe\u0301界b'
[[ $zdraw_ui_document[1,text] == $'ăe\u0301界' && $zdraw_ui_document[2,text] == b &&
   $zdraw_ui_document[2,byte_start] == 8 ]] || fail 'wide wrapping bytes'
before=("${(@kv)zdraw_ui_document}")
reject zdraw-document-reflow 1
same "${(@kv)zdraw_ui_document}"
check zdraw-document-init 3 marks paragraph $'a \u0301bc'
[[ $zdraw_ui_document[1,text] == $'a \u0301b' ]] || fail 'space combining unit split'
check zdraw-document-init 3 long paragraph abcdefg
[[ $zdraw_ui_document[1,text] == abc && $zdraw_ui_document[3,text] == g ]] || fail 'long word fallback'
# Cell wrapping preserves every printable character, including whitespace.
check zdraw-document-init 5 spaces paragraph '  alpha  beta '
collected=''
for (( i=1; i<=zdraw_ui_document[line_count]; i++ )); do
  collected+=$zdraw_ui_document[$i,text]
  check zdraw textinfo info "$zdraw_ui_document[$i,text]"
  (( info[width] <= 5 )) || fail 'overwide row'
done
[[ $collected == '  alpha  beta ' ]] || fail 'whitespace lost'
# Oversized source, too many blocks and too many wrapped rows fail atomically.
typeset long_text=${(l:32768::x:):-} many_rows=${(l:4097::x:):-}
reject zdraw-document-init 8 large paragraph "$long_text"
reject zdraw-document-init 1 long paragraph "$many_rows"
typeset -a too_many
for (( i=1; i<=129; i++ )); do too_many+=("block$i" paragraph x); done
reject zdraw-document-init 8 "${too_many[@]}"
check zdraw-document-init 8
check zdraw-document-scroll 10 end
check zdraw-document-reflow 16
[[ $zdraw_ui_document[line_count] == 0 && $zdraw_ui_document[first] == 1 ]] || fail 'empty document'
() {
  local -A zdraw_ui_document
  check zdraw-document-init 8 local paragraph local
  check zdraw-document-reflow 4
  [[ $zdraw_ui_document[1,text] == loca ]] || fail 'local scope'
}
() {
  local -Ar zdraw_ui_document=(sentinel yes)
  reject zdraw-document-init 8
  reject zdraw-document-scroll 1 home
}
(( ${#zdraw_windows} == 0 )) || fail 'headless initialized terminal'
print -r -- 'UI DOCUMENT PASS'
