#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
typeset root=${0:A:h:h}
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
alias local='false ALIAS_LEAK'
setopt shwordsplit ksharrays globsubst
source "$root/lib/zdraw-canvas.zsh" || exit 1
[[ -o shwordsplit && -o ksharrays && -o globsubst ]] || fail options
unsetopt shwordsplit ksharrays globsubst
unalias local
zmodload -e zdraw && fail 'loader activated module'
typeset -A zdraw_ui_canvas zdraw_ui_canvas_raster before
typeset -a reply bits=(1 2 4 64 8 16 32 128)
typeset -i x y i mask
typeset bad key
same() {
  local -A actual=("$@")
  [[ ${#actual} == ${#before} ]] || fail 'changed size'
  for key in "${(@k)before}"; do [[ ${actual[$key]-} == "$before[$key]" ]] || fail "changed $key"; done
}
# Exercise every dot position using a world that exactly matches one cell.
for (( x=0; x<2; x++ )); do
  for (( y=0; y<4; y++ )); do
    check zdraw-canvas-init 0 0 1 3
    check zdraw-canvas-add point "$x" "$((3-y))"
    check zdraw-canvas-raster 1 1
    [[ $zdraw_ui_canvas_raster[1,mask] == $bits[$((x*4+y+1))] && $zdraw_ui_canvas_raster[pixels] == 1 ]] || fail 'dot mapping'
    check zdraw-canvas-rows ascii
    [[ $reply == '#' ]] || fail 'ASCII export'
    check zdraw-canvas-rows auto X
    [[ $reply == X ]] || fail 'headless auto fallback'
  done
done
check zdraw-canvas-add point 1 0
check zdraw-canvas-raster 1 1
[[ $zdraw_ui_canvas_raster[pixels] == 1 ]] || fail 'collision duplicated pixel'
check zdraw-canvas-add point 1 0 erase
check zdraw-canvas-raster 1 1
[[ $zdraw_ui_canvas_raster[pixels] == 0 ]] || fail erase
check zdraw-canvas-clear
[[ $zdraw_ui_canvas[count] == 0 && $zdraw_ui_canvas[xmax] == 1 ]] || fail clear
check zdraw-canvas-add fill 1 3 0 0
check zdraw-canvas-raster 1 1
[[ $zdraw_ui_canvas_raster[1,mask] == 255 ]] || fail 'reversed filled rectangle'
check zdraw-canvas-add point 1 0 erase
check zdraw-canvas-raster 1 1
[[ $zdraw_ui_canvas_raster[1,mask] == 127 ]] || fail 'partial erase lost neighboring dots'
check zdraw-canvas-add fill 0 0 1 3 erase
check zdraw-canvas-raster 1 1
[[ $zdraw_ui_canvas_raster[pixels] == 0 ]] || fail 'filled erase'
check zdraw-canvas-clear
check zdraw-canvas-add line -32767 3 32767 3
check zdraw-canvas-raster 1 1
[[ $zdraw_ui_canvas_raster[1,mask] == 9 ]] || fail 'extreme horizontal clipping'
check zdraw-canvas-clear
check zdraw-canvas-add rect -1 -1 2 4
check zdraw-canvas-raster 1 1
[[ $zdraw_ui_canvas_raster[pixels] == 0 ]] || fail 'outline invented border at clip edge'
check zdraw-canvas-clear
check zdraw-canvas-add fill -32767 -32767 32767 32767
check zdraw-canvas-raster 1 1
[[ $zdraw_ui_canvas_raster[1,mask] == 255 ]] || fail 'filled clipping'
check zdraw-canvas-init -10 -10 10 10
check zdraw-canvas-add line -20 -20 20 20
check zdraw-canvas-raster 3 7
before=("${(@kv)zdraw_ui_canvas_raster}")
check zdraw-canvas-clear
check zdraw-canvas-add line 20 20 -20 -20
check zdraw-canvas-raster 3 7
same "${(@kv)zdraw_ui_canvas_raster}"
# Reversal remains equivalent after clipping in every octant, including ties.
for x in -20 -9 0 9 20; do
  for y in -20 -9 0 9 20; do
    check zdraw-canvas-clear
    check zdraw-canvas-add line -3 2 "$x" "$y"
    check zdraw-canvas-raster 3 7
    before=("${(@kv)zdraw_ui_canvas_raster}")
    check zdraw-canvas-clear
    check zdraw-canvas-add line "$x" "$y" -3 2
    check zdraw-canvas-raster 3 7
    same "${(@kv)zdraw_ui_canvas_raster}"
  done
done
check zdraw-canvas-clear
check zdraw-canvas-add line 0 0 0 0
check zdraw-canvas-raster 3 7
[[ $zdraw_ui_canvas_raster[pixels] == 1 ]] || fail 'degenerate line'
check zdraw-canvas-raster 8 20
[[ $zdraw_ui_canvas[count] == 1 && $zdraw_ui_canvas_raster[pixels] == 1 ]] || fail 'resize retained source'
before=("${(@kv)zdraw_ui_canvas}")
for bad in '' '+1' '1.0' '--1' '32768' '-32768' 'evil=1' 'x[evil=1]' '$((1))'; do
  reject zdraw-canvas-add point "$bad" 0
  same "${(@kv)zdraw_ui_canvas}"
  reject zdraw-canvas-init "$bad" 0 10 10
  same "${(@kv)zdraw_ui_canvas}"
done
reject zdraw-canvas-add line 1 2
reject zdraw-canvas-add unknown 1 2
reject zdraw-canvas-add point 1 2 toggle
reject zdraw-canvas-init 0 0 0 1
same "${(@kv)zdraw_ui_canvas}"
before=("${(@kv)zdraw_ui_canvas_raster}")
reject zdraw-canvas-raster 0 10
reject zdraw-canvas-raster 257 1
reject zdraw-canvas-raster 65 65
reject zdraw-canvas-raster 'evil=1' 10
same "${(@kv)zdraw_ui_canvas_raster}"
zdraw_ui_canvas[1,x0]='evil=1'
reject zdraw-canvas-raster 1 1
same "${(@kv)zdraw_ui_canvas_raster}"
(( ! ${+evil} )) || fail injection
check zdraw-canvas-init 0 0 1 1
for (( i=0; i<256; i++ )); do check zdraw-canvas-add point 0 0; done
reject zdraw-canvas-add point 0 0
check zdraw-canvas-raster 1 1
[[ $zdraw_ui_canvas_raster[pixels] == 1 && $zdraw_ui_canvas_raster[writes] == 256 ]] || fail 'command limit/collisions'
# Pixel work is bounded independently of scene and raster storage.
check zdraw-canvas-clear
for (( i=0; i<9; i++ )); do check zdraw-canvas-add fill 0 0 1 1; done
before=("${(@kv)zdraw_ui_canvas_raster}")
reject zdraw-canvas-raster 64 64
same "${(@kv)zdraw_ui_canvas_raster}"
reply=(sentinel)
zdraw_ui_canvas_raster[1,mask]='evil=1'
reject zdraw-canvas-rows ascii
[[ $reply == sentinel ]] || fail 'invalid raster mutated output'
() {
  local -A zdraw_ui_canvas zdraw_ui_canvas_raster
  local -a reply
  check zdraw-canvas-init 0 0 1 1
  check zdraw-canvas-add point 0 0
  check zdraw-canvas-raster 1 1
  check zdraw-canvas-rows ascii
  [[ $reply == '#' ]] || fail 'local outputs'
}
() {
  local -Ar zdraw_ui_canvas=(keep yes)
  reject zdraw-canvas-init 0 0 1 1
  reject zdraw-canvas-clear
}
zmodload -e zdraw && fail 'headless operations loaded module'
print -r -- 'UI CANVAS PASS'
