#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
typeset root=${0:A:h:h}
zmodload zdraw || exit 1
source "$root/lib/zdraw-panel.zsh" || exit 1
source "$root/lib/zdraw-list.zsh" || exit 1
source "$root/lib/zdraw-meter.zsh" || exit 1
source "$root/lib/zdraw-fixture.zsh" || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
typeset -A zdraw_ui_theme zdraw_ui_list
typeset -a reply content position_before position_after
typeset zdraw_ui_fixture=sentinel name profile density saved
check zdraw init
{
  check zdraw addwin sample 10 44 1 1
  for name in dark light; do
    for profile in 256 mono; do
      for density in 0 1; do
        check zdraw-ui-theme "$name" "$profile"
        check zdraw-panel sample 0 0 10 44 ' Tasks ' focus border=ascii "px=$density"
        content=("${reply[@]}")
        zdraw_ui_list=(selected 2 first 1)
        check zdraw-list-update 3 3 keep
        check zdraw-list sample "$content[1]" "$content[2]" 3 "$content[4]" focus -- Alpha Beta Gamma
        check zdraw-meter sample 6 "$content[2]" "$content[4]" 37 100 normal
        check zdraw move sample 9 42
        check zdraw position sample position_before
        check zdraw-fixture sample
        check zdraw position sample position_after
        [[ "$position_before" == "$position_after" ]] || fail 'capture moved cursor'
        print -r -- "$zdraw_ui_fixture" > "$ZDRAW_VISUAL_DIR/$name-$profile-$density.json"
      done
    done
  done
  check zdraw clear sample
  check zdraw spans sample 0 0 bold,red/black $'"\\e\u0301界'
  check zdraw-fixture sample
  saved=$zdraw_ui_fixture
  print -r -- "$saved" > "$ZDRAW_VISUAL_DIR/quoted.json"
  check zdraw spans sample 0 0 bold,1/0 $'"\\e\u0301界'
  check zdraw-fixture sample
  [[ $saved == "$zdraw_ui_fixture" ]] || fail 'color alias affected portable capture'
  zdraw-fixture missing 2>/dev/null && fail 'missing window accepted'
  [[ $saved == "$zdraw_ui_fixture" ]] || fail 'failed capture changed output'
  () {
    local -r zdraw_ui_fixture=sentinel
    zdraw-fixture sample && fail 'readonly output accepted'
  }
} always {
  zdraw end
}
print -r -- 'VISUAL PASS'
