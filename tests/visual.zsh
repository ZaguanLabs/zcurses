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
source "$root/lib/zdraw-form.zsh" || exit 1
source "$root/lib/zdraw-document.zsh" || exit 1
source "$root/lib/zdraw-sparkline.zsh" || exit 1
source "$root/lib/zdraw-bars.zsh" || exit 1
source "$root/lib/zdraw-canvas.zsh" || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
typeset -A zdraw_ui_theme zdraw_ui_list zdraw_ui_form zdraw_ui_document zdraw_ui_chart zdraw_ui_canvas zdraw_ui_canvas_raster
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
  for name in dark light; do
    for profile in 256 mono; do
      check zdraw-ui-theme "$name" "$profile"
      check zdraw-form-init Name '' required Port 443 integer
      zdraw-form-action validate && fail 'empty name validated'
      check zdraw-form-action next
      check zdraw-form-action edit select-all
      check zdraw-form sample 0 0 6 44 focus
      check zdraw-document-init 44 guide heading 'A place for good ideas' body paragraph 'Structured content, styled by role and wrapped for the space available.'
      check zdraw-document sample 6 0 4 44 normal
      check zdraw-fixture sample
      print -r -- "$zdraw_ui_fixture" > "$ZDRAW_VISUAL_DIR/$name-$profile-composition.json"
    done
  done
  for name in dark light; do
    for profile in 256 mono; do
      check zdraw-ui-theme "$name" "$profile"
      check zdraw-panel sample 0 0 10 44 ' SIGNAL / -10..10 units ' normal border=ascii
      check zdraw-chart-series fixed -10 10 -- -15 -10 -5 - 0 5 10 15
      check zdraw-sparkline sample 1 2 40 normal palette=ascii
      check zdraw-sparkline sample 2 2 40 normal palette=unicode
      check zdraw-chart-series fixed -10 10 -- -15 -5 0 - 10
      check zdraw-bars sample 4 2 5 40 normal palette=ascii track-char='.'
      check zdraw-fixture sample
      print -r -- "$zdraw_ui_fixture" > "$ZDRAW_VISUAL_DIR/$name-$profile-charts.json"
    done
  done
  check zdraw-canvas-init 0 -4 8 4
  check zdraw-canvas-add line 0 0 2 4
  check zdraw-canvas-add line 2 4 4 0
  check zdraw-canvas-add line 4 0 6 -4
  check zdraw-canvas-add line 6 -4 8 0
  check zdraw-canvas-add rect 1 -3 7 3
  check zdraw-canvas-raster 3 44
  for name in dark light; do
    for profile in 256 mono; do
      check zdraw-ui-theme "$name" "$profile"
      check zdraw-canvas-draw sample 0 0 normal palette=ascii
      check zdraw-canvas-draw sample 3 0 normal palette=braille
      check zdraw-canvas-draw sample 6 0 normal palette=block
      check zdraw-label sample 9 0 44 'Same grid / ASCII, Braille, blocks' normal fg=muted
      check zdraw-fixture sample
      print -r -- "$zdraw_ui_fixture" > "$ZDRAW_VISUAL_DIR/$name-$profile-canvas.json"
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
