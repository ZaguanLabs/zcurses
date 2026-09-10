# Byte encoding is shared by screen serialization and the explicit replay runner.
# REPLY is scratch storage supplied by the enclosing caller.
function _zdraw_screen_hex {
  emulate -L zsh
  local LC_ALL=C piece char
  REPLY=''
  for char in "${(@s::)1}"; do
    [[ -n $char ]] || continue
    printf -v piece '%02x' "'$char" || return
    REPLY+=$piece
  done
  [[ -n $REPLY ]] || REPLY=-
  return 0
}

function _zdraw_screen_unhex {
  emulate -L zsh
  local LC_ALL=C value=$1 piece
  local -i i
  REPLY=''
  [[ $value == - ]] && return 0
  [[ -n $value && $value != *[^0-9a-f]* && ${#value} -le 4096 ]] || return 1
  (( ${#value} % 2 == 0 )) || return 1
  for (( i=1; i<=${#value}; i+=2 )); do
    piece=$value[$i,$((i+1))]
    [[ $piece != 00 ]] || return 1
    printf -v piece '%b' "\\x$piece" || return
    REPLY+=$piece
  done
}

# zdraw_screen_data is an ordinary caller-owned scalar, assigned only on success.
function zdraw-screen-save {
  emulate -L zsh
  [[ $# == 1 && ${(t)zdraw_screen_data} == (scalar|scalar-local) ]] || return 1
  local -A pixels
  local REPLY result style text
  local -i r c
  zdraw snapshot "$1" pixels occupancy || return
  (( pixels[rows] <= 64 && pixels[columns] <= 64 )) || return 1
  result="zdraw-screen-1 $pixels[rows] $pixels[columns] $pixels[cursor_row] $pixels[cursor_column]"
  for (( r=0; r<pixels[rows]; r++ )); do
    for (( c=0; c<pixels[columns]; c++ )); do
      [[ $pixels[$r,$c,occupancy] == single && $pixels[$r,$c,style_supported] == yes ]] || return 2
      style=${pixels[$r,$c,attributes]// /,}
      if [[ $pixels[$r,$c,color] != unknown ]]; then
        [[ -z $style ]] || style+=,
        style+=$pixels[$r,$c,color]
      elif [[ $pixels[$r,$c,pair] != 0 ]]; then
        return 2
      fi
      _zdraw_screen_hex "$style" || return
      style=$REPLY
      _zdraw_screen_hex "$pixels[$r,$c,text]" || return
      text=$REPLY
      (( ${#text} <= 4096 && ${#style} <= 4096 )) || return 1
      result+=$'\n'"$style:$text"
      (( ${#result} <= 1048576 )) || return 1
    done
  done
  zdraw_screen_data=$result
}

# Fully validate and prepare before touching the destination. Temporary native
# rows belong to this invocation, and are released on every exit path.
function zdraw-screen-restore {
  emulate -L zsh
  [[ $# == 2 && ${#2} -le 1048576 ]] || return 1
  local -a lines header geometry batch owned
  local -A measure rowinfo
  local REPLY line style text name value
  local -i rows cols cy cx r c index=2 candidate=0
  lines=("${(@f)2}")
  header=("${(@s: :)lines[1]}")
  [[ ${#header} == 5 && $header[1] == zdraw-screen-1 ]] || return 1
  for value in "${header[@]:1}"; do
    [[ $value == <-> && ${#value} -le 2 && ( $value == 0 || $value != 0* ) ]] || return 1
  done
  rows=$header[2] cols=$header[3] cy=$header[4] cx=$header[5]
  (( rows >= 1 && rows <= 64 && cols >= 1 && cols <= 64 && cy < rows && cx < cols && ${#lines} == 1+rows*cols )) || return 1
  zdraw position "$1" geometry || return
  (( geometry[5] == rows && geometry[6] == cols )) || return 1
  {
    for (( r=0; r<rows; r++ )); do
      batch=()
      for (( c=0; c<cols; c++ )); do
        line=$lines[$index]
        (( index++ ))
        [[ $line == *:* && ${line#*:} != *:* ]] || return 1
        _zdraw_screen_unhex "${line%%:*}" || return
        style=$REPLY
        _zdraw_screen_unhex "${line#*:}" || return
        text=$REPLY
        zdraw textinfo measure "$text" || return
        (( measure[width] == 1 )) || return 2
        batch+=("$style" "$text")
      done
      while true; do
        (( candidate < 8192 )) || return 1
        name=zdraw_screen_${$}_${candidate}
        (( candidate++ ))
        zdraw rowinfo "$name" rowinfo 2>/dev/null || break
      done
      zdraw prepare "$name" "${batch[@]}" || return
      owned+=("$name")
    done
    for (( r=0; r<rows; r++ )); do
      zdraw draw "$1" "$r" 0 "$owned[$((r+1))]" || return
    done
    zdraw move "$1" "$cy" "$cx" || return
  } always {
    for name in "${owned[@]}"; do
      zdraw unprepare "$name"
    done
  }
}
