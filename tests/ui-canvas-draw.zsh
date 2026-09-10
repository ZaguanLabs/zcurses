#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
typeset root=${0:A:h:h}
source "$root/lib/zdraw-canvas.zsh" || exit 1
module_path=("$1")
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A zdraw_ui_canvas zdraw_ui_canvas_raster zdraw_ui_theme before after info zdraw_ui_style=(sentinel yes)
typeset -a reply=(sentinel) position
typeset key
typeset -i i
same() { for key in "${(@k)before}"; do [[ ${after[$key]-} == "$before[$key]" ]] || fail "changed $key"; done; }
check zdraw-ui-theme dark 256
check zdraw-canvas-init 0 0 7 7
check zdraw-canvas-add rect 0 0 7 7
check zdraw-canvas-raster 2 4
check zdraw-canvas-rows ascii
[[ $reply[1] == '####' && $reply[2] == '####' ]] || fail 'ASCII edge cells'
if [[ $2 == wide ]]; then
  check zdraw-canvas-rows braille
  [[ $reply[1] == '⡏⠉⠉⢹' && $reply[2] == '⣇⣀⣀⣸' ]] || fail 'Braille border'
  check zdraw-canvas-rows block
  [[ $reply[1] == '█▀▀█' && $reply[2] == '█▄▄█' ]] || fail 'half-block border'
else
  reject zdraw-canvas-rows braille
  reject zdraw-canvas-rows block
  check zdraw-canvas-rows auto
  [[ $reply[1] == '####' ]] || fail 'narrow fallback'
fi
reply=(sentinel)
check zdraw init
{
  check zdraw addwin sample 8 24 1 1
  check zdraw attr sample underline 2/0
  check zdraw move sample 7 22
  # Exported rows can use the native prepared-row lifecycle unchanged.
  check zdraw-canvas-rows ascii
  check zdraw prepare canvas_row bold,2/0 "$reply[1]"
  check zdraw draw sample 6 0 canvas_row
  check zdraw unprepare canvas_row
  check zdraw snapshot sample after
  [[ $after[6,0,text] == '#' && $after[6,0,attributes] == bold ]] || fail 'prepared row export'
  reply=(sentinel)
  check zdraw-canvas-draw sample 0 0 normal palette=ascii fg=error
  check zdraw snapshot sample after
  [[ $after[0,0,text] == '#' && $after[0,0,color] == 210/236 ]] || fail 'ASCII styled draw'
  check zdraw-canvas sample 2 0 2 4 normal palette=auto
  check zdraw snapshot sample before
  if [[ $2 == wide ]]; then [[ $before[2,0,text] == ⡏ ]] || fail 'automatic Braille'
  else [[ $before[2,0,text] == '#' ]] || fail 'automatic ASCII'; fi
  [[ $zdraw_ui_canvas_raster[rows] == 2 && $zdraw_ui_canvas_raster[columns] == 4 ]] || fail 'convenience mutated raster'
  reject zdraw-canvas-draw sample 0 0 normal palette=bad
  reject zdraw-canvas-draw sample 0 0 normal ink-char=$'\e'
  reject zdraw-canvas-draw sample 0 0 normal ink-char=界
  reject zdraw-canvas-draw sample 0 0 normal border=rounded
  reject zdraw-canvas-draw sample 0 0 normal selected:fg=bogus
  reject zdraw-canvas-draw sample 7 23 normal
  check zdraw snapshot sample after
  same
  zdraw_ui_canvas_raster[1,mask]='evil=1'
  reject zdraw-canvas-draw sample 0 0 normal
  (( ! ${+evil} )) || fail injection
  check zdraw snapshot sample after
  same
  check zdraw-canvas-clear
  check zdraw-canvas sample 0 0 4 4 normal palette=ascii
  check zdraw snapshot sample after
  [[ $after[0,0,text] == ' ' && $after[2,0,text] == ' ' ]] || fail 'empty replaces old drawing'
  check zdraw-canvas-add fill 0 0 7 7
  check zdraw-canvas-raster 1 1
  check zdraw-ui-theme dark mono
  check zdraw-canvas-draw sample 4 0 focus palette=ascii ink-char=X bold
  check zdraw snapshot sample after
  [[ $after[4,0,text] == X && $after[4,0,pair] == 0 && $after[4,0,attributes] == bold ]] || fail 'monochrome custom ink'
  () {
    local LC_ALL=C
    local -a reply
    check zdraw-canvas-rows auto
    [[ $reply == '#' ]] || fail 'C locale fallback'
    reject zdraw-canvas-rows braille
    reject zdraw-canvas-rows block
  }
  check zdraw position sample position
  [[ $position[1] == 7 && $position[2] == 22 ]] || fail cursor
  check zdraw char sample X
  check zdraw move sample 7 22
  check zdraw cellinfo sample info
  [[ $info[color] == 2/0 && $info[attributes] == underline ]] || fail 'drawing style'
  [[ $reply == sentinel && $zdraw_ui_style[sentinel] == yes ]] || fail 'public output leaked'
  check zdraw refresh sample
} always {
  zdraw end
}
print -r -- 'UI CANVAS DRAW PASS'
