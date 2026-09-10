#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
typeset root=${0:A:h:h}
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
# Load under hostile caller options and a parse-time alias. Source is passive.
alias local='false ALIAS_LEAK'
setopt shwordsplit ksharrays globsubst
source "$root/lib/zdraw-list.zsh" || exit 1
[[ -o shwordsplit && -o ksharrays && -o globsubst ]] || fail 'loader options'
unsetopt shwordsplit ksharrays globsubst
unalias local
zmodload -e zdraw && fail 'loader loaded native module'
whence -w zdraw-panel >/dev/null && fail 'list loaded panel'
typeset -A zdraw_ui_theme zdraw_ui_style zdraw_ui_list
typeset -a reply
check zdraw-ui-theme dark 256 accent=081
[[ $zdraw_ui_theme[accent] == 81 ]] || fail 'canonical theme color'
check zdraw-ui-style focus 'focus:fg=accent' fg=text bg=canvas border=rounded px=02
[[ $zdraw_ui_style[fg] == 81 && $zdraw_ui_style[bg] == 234 &&
   $zdraw_ui_style[px] == 2 && $zdraw_ui_style[border] == rounded ]] || fail 'conditional precedence'
check zdraw-ui-style focus,selected fg=text selected:bg=selection selected+focus:underline bold no-bold
[[ $zdraw_ui_style[style] == underline,252/30 ]] || fail 'combined state and removal'
typeset -A previous=("${(@kv)zdraw_ui_style}")
same() {
  local -A actual=("$@")
  local key
  [[ ${#previous} == ${#actual} ]] || fail 'association size changed'
  for key in "${(@k)previous}"; do
    [[ ${actual[$key]-} == "$previous[$key]" ]] || fail "changed output: $key"
  done
}
typeset bad
for bad in 'px=x=7' 'py=-1' 'px=17' 'fg=256' 'fg=1/0' 'fg=#123' 'bg=unknown' \
  'focus:fg=bogus' 'hover:underline' 'focus++selected:bold' 'focus::bold' 'focus:' \
  'align=diagonal' 'border=cloud' 'fg=$(touch SHOULD_NOT_EXIST)'; do
  reject zdraw-ui-style normal "$bad"
  same "${(@kv)zdraw_ui_style}"
done
for bad in '' 'focus,,selected' 'hover' 'focus+'; do reject zdraw-ui-style "$bad" bold; done
check zdraw-ui-theme light 16
[[ $zdraw_ui_theme[text] == 0 && $zdraw_ui_theme[surface] == 7 ]] || fail 'light theme'
previous=("${(@kv)zdraw_ui_theme}")
reject zdraw-ui-theme light 16 accent=blue
reject zdraw-ui-theme light 16 'accent=a[1+evil=1]'
same "${(@kv)zdraw_ui_theme}"
NO_COLOR=1
check zdraw-ui-theme dark
[[ $zdraw_ui_theme[profile] == mono ]] || fail 'NO_COLOR'
check zdraw-ui-theme dark 256
[[ $zdraw_ui_theme[profile] == 256 ]] || fail 'explicit profile'
unset NO_COLOR
setopt shwordsplit ksharrays globsubst
zdraw-ui-style normal fg=text bg=surface || fail 'foreign option call'
[[ -o shwordsplit && -o ksharrays && -o globsubst ]] || fail 'call options'
unsetopt shwordsplit ksharrays globsubst
check zdraw-list-update 10 3 end
[[ $zdraw_ui_list[selected] == 10 && $zdraw_ui_list[first] == 8 ]] || fail 'end scroll'
check zdraw-list-update 10 3 page-up
[[ $zdraw_ui_list[selected] == 7 && $zdraw_ui_list[first] == 7 ]] || fail 'page up'
check zdraw-list-update 2 3 keep
[[ $zdraw_ui_list[selected] == 2 && $zdraw_ui_list[first] == 1 ]] || fail 'shrinking data'
check zdraw-list-update 0 0 keep
[[ $zdraw_ui_list[selected] == 0 && $zdraw_ui_list[first] == 1 ]] || fail 'empty state'
check zdraw-list-update 10 0 down
[[ $zdraw_ui_list[selected] == 2 ]] || fail 'zero viewport'
previous=("${(@kv)zdraw_ui_list}")
reject zdraw-list-update 'evil=1' 3 keep
reject zdraw-list-update 10 3 '$(false)'
same "${(@kv)zdraw_ui_list}"
zdraw_ui_list[selected]='evil=1'
reject zdraw-list-update 10 3 keep
(( ! ${+evil} )) || fail 'arithmetic injection'
() {
  local -A zdraw_ui_theme zdraw_ui_style zdraw_ui_list
  check zdraw-ui-theme light 16
  check zdraw-ui-style normal fg=text
  check zdraw-list-update 3 2 end
  [[ $zdraw_ui_list[selected] == 3 && $zdraw_ui_style[fg] == 0 ]] || fail 'local outputs'
}
() {
  local -Ar zdraw_ui_style=(keep yes)
  reject zdraw-ui-style normal bold
  [[ $zdraw_ui_style[keep] == yes ]] || fail 'readonly output'
}
print -r -- 'UI STYLE PASS'
