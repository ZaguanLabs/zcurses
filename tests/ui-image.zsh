#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
typeset root=${0:A:h:h}
module_path=("$1")
source "$root/lib/zdraw-image.zsh" || exit 1
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() { "$@" 2>/dev/null && fail "unexpected success: $*"; return 0; }
typeset -A zdraw_ui_image zdraw_ui_theme before after info resources_before resources_after
typeset -a reply=(sentinel) position
typeset packet=$'zdraw-image-1 2 4\n0000\n0000\nffff\nffff' key saved
check zdraw-image-load "$packet" 'Black and white sample'
check zdraw-image-rows
[[ $reply[1] == '    ' && $reply[2] == '@@@@' ]] || fail 'ASCII density'
saved="${(j:|:)${(@kv)zdraw_ui_image}}"
for packet in $'zdraw-image-1 1 2\n00\n0g' $'zdraw-image-1 1 2\n00\n00\nextra' $'zdraw-image-1 x=1 2\n00\n00' $'zdraw-image-1 1 2\n0\n00' $'zdraw-image-1 1 2\n00\n\e['; do
  reject zdraw-image-load "$packet" Sample
  [[ "${(j:|:)${(@kv)zdraw_ui_image}}" == "$saved" ]] || fail 'load not atomic'
done
reject zdraw-image-load $'zdraw-image-1 1 1\n0\n0' $'bad\e'
key=''
reject zdraw-image-load $'zdraw-image-1 1 1\n0\n0' "${(pl:100::界:)key}"
check zdraw-ui-theme dark 16
check zdraw init
{
  check zdraw addwin sample 8 24 1 1
  check zdraw attr sample underline 2/0
  check zdraw move sample 7 22
  check zdraw-image-draw sample 0 0 3 6 normal palette=ascii colors=theme
  check zdraw snapshot sample before
  [[ $before[0,0,text] == ' ' && $before[1,0,text] == @ && $before[2,0,text] == ' ' && $before[1,4,text] == ' ' ]] || fail 'draw extent'
  check zdraw-image-draw sample 4 0 1 2 normal palette=auto
  check zdraw snapshot sample after
  if [[ $2 == wide ]]; then
    [[ $after[4,0,text] == ▀ && $after[4,0,color] == 0/0 ]] || fail "block draw: $after[4,0,text] / $after[4,0,color]"
  else [[ $after[4,0,text] == ' ' ]] || fail 'ASCII-only fallback'; fi
  check zdraw resourceinfo resources_before
  check zdraw-image-draw sample 4 0 1 2 normal palette=auto
  check zdraw resourceinfo resources_after
  [[ $resources_before[cached_color_pairs] == $resources_after[cached_color_pairs] ]] || fail 'redraw color growth'
  check zdraw snapshot sample before
  reject zdraw-image-draw sample 0 0 1 1 normal palette=invalid
  reject zdraw-image-draw sample 0 0 1 1 normal border=rounded
  zdraw_ui_image[1,pixels]='evil'
  reject zdraw-image-draw sample 0 0 1 1 normal
  (( ! ${+evil} )) || fail injection
  check zdraw snapshot sample after
  for key in "${(@k)before}"; do [[ $after[$key] == "$before[$key]" ]] || fail "changed $key"; done
  check zdraw-image-load $'zdraw-image-1 1 2\nff\nff' Sample
  check zdraw-ui-theme dark mono
  check zdraw-image-draw sample 5 0 1 1 normal palette=auto
  check zdraw snapshot sample after
  [[ $after[5,0,text] == @ && $after[5,0,pair] == 0 ]] || fail 'monochrome fallback'
  check zdraw position sample position
  [[ $position[1] == 7 && $position[2] == 22 ]] || fail cursor
  check zdraw char sample X
  check zdraw move sample 7 22
  check zdraw cellinfo sample info
  [[ $info[color] == 2/0 && $info[attributes] == underline ]] || fail 'style changed'
  check zdraw refresh sample
  check zdraw suspend
  check zdraw resume
  check zdraw-image-draw sample 5 0 1 1 normal palette=auto
  () {
    local LC_ALL=C
    check zdraw-image-draw sample 5 0 1 1 normal palette=auto
  }
  # Every ordered palette pair is bounded; subsequent frames reuse all pairs.
  check zdraw-ui-theme dark 16
  packet='zdraw-image-1 16 16'
  for key in 0 1 2 3 4 5 6 7 8 9 a b c d e f; do
    saved=''
    packet+=$'\n'"${(pl:16::$key:)saved}"$'\n0123456789abcdef'
  done
  check zdraw-image-load "$packet" 'All palette pairs'
  check zdraw addwin palette 16 16 0 30
  check zdraw resourceinfo resources_before
  check zdraw-image-draw palette 0 0 16 16 normal palette=auto
  check zdraw resourceinfo resources_after
  (( resources_after[cached_color_pairs]-resources_before[cached_color_pairs] <= 256 )) || fail 'palette limit'
  resources_before=("${(@kv)resources_after}")
  check zdraw-image-draw palette 0 0 16 16 normal palette=auto
  check zdraw resourceinfo resources_after
  [[ $resources_before[cached_color_pairs] == $resources_after[cached_color_pairs] ]] || fail 'palette redraw growth'
  check zdraw delwin palette
  # Extended image colors preserve dark surfaces, independent of ANSI colors.
  packet=$'zdraw-image-2 2 4\npalette=234,236,255,16,16,16,16,16,16,16,16,16,16,16,16,16\n0000\n0000\n2222\n2222'
  check zdraw-image-load "$packet" 'Dark surface and light footer'
  check zdraw-image-rows
  [[ $reply[1] == '    ' && $reply[2] == '%%%%' ]] || fail 'adaptive ASCII luminance'
  check zdraw-image-draw sample 0 0 1 2 normal fit=contain palette=auto
  check zdraw snapshot sample after
  if [[ $2 == wide ]]; then
    [[ $after[0,0,color] == 234/255 ]] || fail 'contain lost lower image half or adaptive colors'
  else [[ $after[0,0,text] == = ]] || fail 'adaptive ASCII fallback'; fi
  check zdraw-image-draw sample 0 0 4 8 normal fit=contain palette=ascii colors=theme
  check zdraw snapshot sample before
  [[ $before[2,2,text] == % && $before[2,5,text] == % && $before[2,1,text] == ' ' && $before[3,2,text] == ' ' ]] || fail 'contain centering'
  saved="${(j:|:)${(@kv)zdraw_ui_image}}"
  for key in '234,236' '234,236,999,16,16,16,16,16,16,16,16,16,16,16,16,16' '234,236,x=1,16,16,16,16,16,16,16,16,16,16,16,16,16'; do
    reject zdraw-image-load "${packet/234,236,255,16,16,16,16,16,16,16,16,16,16,16,16,16/$key}" Sample
    [[ "${(j:|:)${(@kv)zdraw_ui_image}}" == "$saved" ]] || fail 'adaptive load not atomic'
  done
  reject zdraw-image-draw sample 0 0 1 2 normal fit=invalid
  zdraw_ui_image[palette]='evil'
  reject zdraw-image-draw sample 0 0 1 2 normal
  check zdraw snapshot sample after
  for key in "${(@k)before}"; do [[ $after[$key] == "$before[$key]" ]] || fail "invalid palette changed $key"; done
  check zdraw-image-load $'zdraw-image-1 1 2\nff\nff' Sample
} always {
  zdraw end
}
check zmodload -u zdraw
check zdraw-image-rows
[[ $reply == '@@' ]] || fail 'retained data after unload'
print -r -- 'UI IMAGE PASS'
