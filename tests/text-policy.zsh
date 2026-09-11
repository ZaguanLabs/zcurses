#!/usr/bin/env zsh
emulate -R zsh
setopt nounset
module_path=("$1")
zmodload zdraw || exit 1
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { "$@" || fail "$*"; }
reject() {
  local expected=$1
  shift
  "$@" 2>/dev/null
  (( $? == expected )) || fail "expected $expected: $*"
}
typeset policy=unicode-17.0.0-egc-wcwidth-sum-attach-zero
typeset unsupported=unicode-17.0.0-egc-max-wcwidth-emoji2
typeset -A info snap before after cell
typeset -a pos
typeset -i width budget col i
typeset text reconstructed token huge=''
if [[ ${2:-wide} == unavailable ]]; then
  reject 2 zdraw textpolicy info "$policy"
  check zdraw init
  {
    check zdraw addwin sample 2 12 1 1
    check zdraw string sample sentinel
    check zdraw snapshot sample before
    reject 2 zdraw spans sample 0 0 "policy=$policy" '' X
    reject 2 zdraw spansclip sample 0 0 1 "policy=$policy" '' X
    reject 2 zdraw string sample X "policy=$policy"
    check zdraw snapshot sample after
    [[ "${(j:|:)${(@kv)before}}" == "${(j:|:)${(@kv)after}}" ]] || fail 'unsupported drawing changed window'
  } always {
    zdraw end || exit 1
  }
  print -r -- 'TEXT POLICY PASS'
  exit 0
fi
check zdraw textpolicy info "$policy"
[[  $info[grapheme_available] == 1 && $info[style_policy] == first-scalar ]] || fail discovery
check zdraw init
{
  check zdraw addwin sample 4 32 1 1
  check zdraw addwin target 4 32 6 1
  # Each corpus item is a single clipping unit; verify every possible budget
  # against real retained native cells, not a second measurement helper.
  for text in $'e\u0301' '👍🏽' '👩‍💻' '👨‍👩‍👧‍👦' '🇳🇴' '1️⃣' '❤️' '각' 'क्ष' 'का' $'a\u200b'; do
    check zdraw textinfo info "$text" 32 "$policy"
    width=$info[width]
    for (( budget=0; budget<=width+1; budget++ )); do
      check zdraw clear sample
      check zdraw move sample 3 31
      check zdraw spansclip sample 0 1 "$budget" "policy=$policy" bold "${text}X"
      check zdraw snapshot sample snap occupancy
      check zdraw position sample pos
      [[ $pos[1] == 3 && $pos[2] == 31 ]] || fail 'spans moved cursor'
      check zdraw textinfo info "${text}X" "$budget" "$policy"
      reconstructed=''
      for (( col=1; col<=info[width]; col++ )); do
        [[ $snap[0,$col,occupancy] != unknown ]] || fail 'ambiguous native occupancy'
        if [[ $snap[0,$col,occupancy] != continuation ]]; then
          reconstructed+=$snap[0,$col,text]
          [[ $snap[0,$col,attributes] == bold ]] || fail 'lost style'
        fi
      done
      [[ $reconstructed == "$info[text]" && $snap[0,$((info[width]+1)),text] == ' ' ]] || fail "clip $text at $budget"
    done
    check zdraw clear sample
    check zdraw move sample 0 1
    check zdraw attr sample underline
    check zdraw string sample "${text}X" "policy=$policy"
    check zdraw position sample pos
    [[ $pos[1] == 0 && $pos[2] == $((width+2)) ]] || fail "cursor $text"
    # Padding starts at the measured native end. Full-region copy and staged
    # presentation must leave native text, style and occupancy unchanged.
    check zdraw fill sample 0 "$pos[2]" 1 2 '' '.'
    check zdraw snapshot sample before occupancy
    [[ $before[0,$((width+1)),text] == X && $before[0,$((width+2)),text] == . ]] || fail padding
    check zdraw copy sample 0 0 target 0 0 4 32
    check zdraw stage sample target
    check zdraw present
    check zdraw snapshot target after occupancy
    for token in "${(@k)before}"; do
      [[ $token == cursor_* ]] && continue
      [[ $before[$token] == "$after[$token]" ]] || fail "retained copy $text $token"
    done
    check zdraw snapshot sample after occupancy
    [[ "${(j:|:)${(@kv)before}}" == "${(j:|:)${(@kv)after}}" ]] || fail 'presentation changed retained cells'
  done
  check zdraw suspend
  check zdraw textpolicy info "$policy"
  check zdraw resume
  check zdraw snapshot sample after occupancy
  [[ "${(j:|:)${(@kv)before}}" == "${(j:|:)${(@kv)after}}" ]] || fail 'resume changed retained cells'
  check zdraw resizewin sample 4 34
  check zdraw snapshot sample after
  [[ $after[0,1,text] == $'a\u200b' && $after[0,2,text] == X ]] || fail 'resize lost text'
  check zdraw resizewin sample 4 32
  # Boundaries between styles must not reset segmentation or double count.
  check zdraw clear sample
  check zdraw spans sample 0 1 "policy=$policy" bold,red/black '👩' underline $'\u200d' reverse,blue/black '💻X'
  check zdraw spans sample 1 1 "policy=$policy" bold e underline $'\u0301X'
  check zdraw snapshot sample snap
  [[ $snap[0,1,text] == $'👩\u200d' && $snap[0,3,text] == '💻' && $snap[0,5,text] == X &&
     $snap[0,1,color] == red/black && $snap[0,3,color] == red/black && $snap[0,5,color] == blue/black &&
     $snap[0,1,attributes] == bold && $snap[0,3,attributes] == bold && $snap[0,5,attributes] == reverse &&
     $snap[1,1,text] == $'e\u0301' && $snap[1,1,attributes] == bold && $snap[1,2,attributes] == underline ]] || fail 'first scalar style'
  check zdraw spansclip sample 2 1 2 "policy=$policy" bold,red/black '👩' underline $'\u200d💻X'
  check zdraw snapshot sample snap
  [[ $snap[2,1,text] == ' ' && $snap[2,2,text] == ' ' ]] || fail 'cross-style clip'
  # Window edge is also a clipping budget, and string failure is preflighted.
  check zdraw spansclip sample 2 30 32 "policy=$policy" '' '👩‍💻'
  check zdraw move sample 3 30
  check zdraw snapshot sample before
  reject 1 zdraw string sample '👩‍💻' "policy=$policy"
  reject 1 zdraw string sample AB "policy=$policy"
  reject 2 zdraw spans sample 0 0 "policy=$unsupported" '' X
  reject 2 zdraw spansclip sample 0 0 2 "policy=$unsupported" '' X
  reject 2 zdraw string sample X "policy=$unsupported"
  reject 2 zdraw spansclip sample 0 0 0 "policy=$policy" '' $'a\u0301\u0301\u0301\u0301\u0301'
  reject 1 zdraw spansclip sample 0 0 0 "policy=$policy" '' $'ok\n'
  reject 1 zdraw spansclip sample 0 0 0 "policy=$policy" '' ok bogus X
  typeset -a excessive_spans=()
  repeat 4097; do excessive_spans+=('' ''); done
  reject 1 zdraw spansclip sample 0 0 0 "policy=$policy" "${excessive_spans[@]}"
  reject 1 zdraw spansclip sample 0 0 0 "policy=$policy" '' "${(pl:1048577::x:)huge}"
  reject 1 zdraw spans sample 0 0 "policy=$policy" '' $'\xc3' '' $'\xa9'
  check zdraw snapshot sample after
  [[ "${(j:|:)${(@kv)before}}" == "${(j:|:)${(@kv)after}}" ]] || fail 'rejection mutated window'
  check zdraw move sample 2 28
  check zdraw string sample '👩‍💻' "policy=$policy"
  check zdraw position sample pos
  [[ $pos[1] == 3 && $pos[2] == 0 ]] || fail 'exact-edge cursor'
  # Explicit strings preserve current attributes and background; spaces in
  # this path are literal cells, just as they are in spans.
  check zdraw bg sample '@#' reverse
  check zdraw attr sample bold
  check zdraw move sample 1 10
  check zdraw string sample ' X' "policy=$policy"
  check zdraw snapshot sample snap
  [[ $snap[1,10,text] == ' ' && $snap[1,11,text] == X && $snap[1,11,attributes] == 'bold reverse' ]] || fail "safe string style: $snap[1,10,text] $snap[1,11,text] $snap[1,11,attributes]"
  check zdraw string sample ' '
  check zdraw snapshot sample snap
  [[ $snap[1,12,text] == '#' && $snap[1,12,attributes] == 'bold reverse' ]] || fail 'background or current style changed'
} always {
  zdraw end || exit 1
}
check zdraw textpolicy info "$policy"
print -r -- 'TEXT POLICY PASS'
