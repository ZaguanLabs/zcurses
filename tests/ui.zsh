#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset mode=$2 root=${0:A:h:h}
zmodload zdraw || exit 1
source "$root/lib/zdraw-panel.zsh" || exit 1
source "$root/lib/zdraw-list.zsh" || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A zdraw_ui_theme zdraw_ui_style zdraw_ui_list before after info
zdraw_ui_style=(sentinel unchanged)
typeset -a reply position labels=('alpha' 'beta' 'gamma' 'delta')
typeset field
same() {
  for field in "${(@k)before}"; do
    [[ $before[$field] == "$after[$field]" ]] || fail "changed snapshot: $field"
  done
}
check zdraw-ui-theme dark 256
check zdraw init
{
  check zdraw addwin sample 12 28 1 1
  check zdraw attr sample underline 2/0
  check zdraw move sample 11 26
  check zdraw-panel sample 1 2 7 22 Title focus border=ascii px=1 py=1 title:fg=accent
  [[ $reply == '3 4 3 18' ]] || fail "content rect: $reply"
  check zdraw snapshot sample before
  [[ $before[1,2,text] == + && $before[1,3,text] == T && $before[7,23,text] == + ]] || fail 'panel edges/title'
  [[ $before[1,3,color] == 80/236 && $before[1,3,attributes] == bold ]] || fail 'title style'
  check zdraw-list-update 4 3 end
  check zdraw-list sample "${reply[@]}" focus -- "${labels[@]}"
  check zdraw snapshot sample before
  [[ $before[3,6,text] == b && $before[5,4,text] == '>' && $before[5,6,text] == d ]] || fail 'visible list rows'
  [[ $before[5,4,color] == 231/30 && $before[5,4,attributes] == bold ]] || fail 'selected style'
  check zdraw-list sample "${reply[@]}" inactive selected+inactive:bg=52 -- "${labels[@]}"
  check zdraw snapshot sample before
  [[ $before[5,4,color] == 252/52 ]] || fail 'instance state override'
  check zdraw-list sample "${reply[@]}" disabled -- "${labels[@]}"
  check zdraw snapshot sample before
  [[ $before[5,4,color] == 245/236 && -z $before[5,4,attributes] ]] || fail 'disabled appearance'
  reject zdraw-panel sample 1 2 7 22 $'bad\ntext' normal
  reject zdraw-panel sample 'evil=1' 2 7 22 Title normal
  reject zdraw-panel sample 11 27 2 2 Title normal
  reject zdraw-list sample "${reply[@]}" focus -- $'offscreen\e]52;bad' beta gamma delta
  reject zdraw-list sample "${reply[@]}" focus inactive:fg=bogus -- "${labels[@]}"
  () {
    local zdraw_ui_theme=invalid
    reject zdraw-list sample "${reply[@]}" focus -- "${labels[@]}"
  }
  check zdraw snapshot sample after
  same
  # A tiny panel collapses its border and returns zero content without touching
  # adjacent cells. Oversized padding also produces a valid empty rectangle.
  check zdraw-panel sample 0 0 1 1 '' normal border=double
  [[ $reply[3] == 1 && $reply[4] == 0 ]] || fail 'tiny panel'
  check zdraw-panel sample 1 2 7 22 Title normal px=16 py=16
  [[ $reply[3] == 0 && $reply[4] == 0 ]] || fail 'empty content'
  check zdraw-panel sample 1 2 7 22 Title normal border=none px=1
  [[ $reply == '2 3 6 20' ]] || fail 'borderless title consumes row'
  check zdraw-list-update 0 4 keep
  check zdraw-list sample 2 3 4 20 focus empty-text=Empty empty:fg=accent --
  check zdraw snapshot sample after
  [[ $after[2,3,text] == E && $after[2,3,color] == 80/236 && $after[5,4,text] == ' ' ]] || fail 'empty clears stale content'
  check zdraw-label sample 8 2 12 abc normal align=right px=1
  check zdraw snapshot sample after
  [[ $after[8,10,text] == a && $after[8,12,text] == c && $after[8,13,text] == ' ' ]] || fail 'label alignment'
  check zdraw-label sample 8 16 12 abc normal align=right
  check zdraw snapshot sample after
  [[ $after[8,25,text] == a && $after[8,27,text] == c ]] || fail 'alignment at window edge'
  if [[ $mode == wide ]]; then
    check zdraw-label sample 9 2 2 $'e\u0301界' normal
    check zdraw snapshot sample after
    [[ $after[9,2,text] == $'e\u0301' && $after[9,3,text] == ' ' ]] || fail 'complete unit clipping'
    check zdraw-panel sample 1 2 7 22 Title normal border=rounded
    check zdraw snapshot sample after
    [[ $after[1,2,text] == ╭ ]] || fail 'rounded border'
  else
    LC_ALL=C
    check zdraw-panel sample 1 2 7 22 Title normal border=rounded
    check zdraw snapshot sample after
    [[ $after[1,2,text] == + ]] || fail 'ASCII fallback'
  fi
  check zdraw-ui-theme light 256
  check zdraw-panel sample 1 2 7 22 Title normal
  check zdraw snapshot sample after
  [[ $after[2,3,color] == 235/231 ]] || fail 'theme redraw'
  check zdraw-ui-theme dark mono
  check zdraw-list-update 1 1 keep
  check zdraw-list sample 2 3 1 10 focus -- alpha
  check zdraw snapshot sample after
  [[ $after[2,3,pair] == 0 && $after[2,3,attributes] == 'bold reverse' ]] || fail 'monochrome selection'
  check zdraw position sample position
  [[ $position[1] == 11 && $position[2] == 26 ]] || fail 'cursor moved'
  check zdraw char sample X
  check zdraw move sample 11 26
  check zdraw cellinfo sample info
  [[ $info[color] == 2/0 && $info[attributes] == underline ]] || fail 'drawing style leaked'
  [[ $zdraw_ui_style[sentinel] == unchanged && ${#zdraw_ui_style} == 1 ]] || fail 'caller style output changed'
  check zdraw refresh sample
} always {
  zdraw end
}
print -r -- 'UI PASS'
