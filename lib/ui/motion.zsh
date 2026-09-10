# All scheduling belongs to the caller. State updates work without a module/TTY.
function _zdraw_motion_valid {
  emulate -L zsh
  [[ ${(t)zdraw_ui_motion} == (association|association-local) && ${#zdraw_ui_motion} == 7 &&
     ${zdraw_ui_motion[format]-} == zdraw-motion-1 &&
     ${zdraw_ui_motion[kind]-} == (activity|settle) &&
     ${zdraw_ui_motion[mode]-} == (on|reduced|off) &&
     ${zdraw_ui_motion[phase]-} == (running|paused|complete|cancelled) &&
     ${zdraw_ui_motion[frame]-} == [0-3] &&
     ${zdraw_ui_motion[visible]-} == [01] && ${zdraw_ui_motion[changed]-} == [01] ]] || return 1
  if [[ $zdraw_ui_motion[kind] == settle ]]; then
    [[ $zdraw_ui_motion[frame] != 3 ]] || return 1
    if [[ $zdraw_ui_motion[phase] == (complete|cancelled) ]]; then
      [[ $zdraw_ui_motion[frame] == 2 ]] || return 1
    else
      [[ $zdraw_ui_motion[mode] == on && $zdraw_ui_motion[frame] != 2 ]] || return 1
    fi
  fi
}

function zdraw-motion-init {
  emulate -L zsh
  [[ $# == 2 && ${(t)zdraw_ui_motion} == (association|association-local) &&
     $1 == (activity|settle) && $2 == (on|reduced|off) ]] || return 1
  local _zui_phase=running _zui_frame=0
  [[ $1 == settle && $2 != on ]] && { _zui_phase=complete; _zui_frame=2; }
  zdraw_ui_motion=(format zdraw-motion-1 kind "$1" mode "$2" phase "$_zui_phase"
                   frame "$_zui_frame" visible 1 changed 1)
}

function zdraw-motion-action {
  emulate -L zsh
  [[ $# == 1 ]] && _zdraw_motion_valid || return 1
  local -A _zui_next=("${(@kv)zdraw_ui_motion}")
  local _zui_key
  _zui_next[changed]=0
  case $1 in
    advance)
      if [[ $_zui_next[visible] == 1 && $_zui_next[phase] == running && $_zui_next[mode] == on ]]; then
        if [[ $_zui_next[kind] == activity ]]; then
          _zui_next[frame]=$(( (_zui_next[frame]+1)%4 ))
        else
          _zui_next[frame]=$(( _zui_next[frame]+1 ))
          [[ $_zui_next[frame] == 2 ]] && _zui_next[phase]=complete
        fi
      fi ;;
    pause) [[ $_zui_next[phase] == running ]] && _zui_next[phase]=paused ;;
    resume) [[ $_zui_next[phase] == paused ]] && _zui_next[phase]=running ;;
    cancel|finish)
      [[ $1 == cancel ]] && _zui_next[phase]=cancelled || _zui_next[phase]=complete
      [[ $_zui_next[kind] == settle ]] && _zui_next[frame]=2 || _zui_next[frame]=0 ;;
    hide) _zui_next[visible]=0 ;;
    show) _zui_next[visible]=1 ;;
    on|reduced|off)
      _zui_next[mode]=$1
      if [[ $1 != on ]]; then
        _zui_next[frame]=0
        if [[ $_zui_next[kind] == settle ]]; then
          _zui_next[frame]=2
          [[ $_zui_next[phase] == cancelled ]] || _zui_next[phase]=complete
        fi
      fi ;;
    restart)
      _zui_next[frame]=0 _zui_next[phase]=running
      if [[ $_zui_next[kind] == settle && $_zui_next[mode] != on ]]; then
        _zui_next[frame]=2 _zui_next[phase]=complete
      fi ;;
    *) return 1 ;;
  esac
  for _zui_key in phase mode frame visible; do
    [[ $_zui_next[$_zui_key] == "$zdraw_ui_motion[$_zui_key]" ]] || _zui_next[changed]=1
  done
  zdraw_ui_motion=("${(@kv)_zui_next}")
}

# One-column activity marker, styled with the existing utility vocabulary.
function zdraw-activity {
  emulate -L zsh
  (( $# >= 4 )) && _zdraw_motion_valid || return 1
  [[ $zdraw_ui_motion[kind] == activity ]] || return 1
  [[ $zdraw_ui_motion[visible] == 1 ]] || return 0
  local -a _zui_frames=('|' '/' '-' '\') _zui_tokens
  local _zui_token _zui_glyph='*'
  local -A zdraw_ui_style _zui_info
  local -i _zui_y _zui_x _zui_h _zui_w
  for _zui_token in "${@:5}"; do
    case $_zui_token in
      glyphs=ascii) _zui_frames=('|' '/' '-' '\') ;;
      glyphs=dots) _zui_frames=('⠋' '⠙' '⠹' '⠸') ;;
      glyphs=*) return 1 ;;
      *) _zui_tokens+=("$_zui_token") ;;
    esac
  done
  case $zdraw_ui_motion[phase] in
    complete) _zui_glyph='+' ;;
    cancelled) _zui_glyph=x ;;
    paused) _zui_glyph='=' ;;
    running) [[ $zdraw_ui_motion[mode] == on ]] && _zui_glyph=$_zui_frames[$((zdraw_ui_motion[frame]+1))] ;;
  esac
  _zdraw_ui_rect "$1" "$2" "$3" 1 1 || return
  zdraw textinfo _zui_info "$_zui_glyph" || return
  [[ $_zui_info[width] == 1 ]] || return 1
  zdraw-ui-style "$4" fg=accent bg=surface "${_zui_tokens[@]}" || return
  [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[px] == 0 && $zdraw_ui_style[py] == 0 ]] || return 1
  zdraw fill "$1" "$_zui_y" "$_zui_x" 1 1 "$zdraw_ui_style[style]" "$_zui_glyph"
}

# Finite emphasis: bold -> underline -> caller's base style. No RGB interpolation.
# The caller owns a uniformly styled rectangle and redraws after moving/resizing it.
function zdraw-settle {
  emulate -L zsh
  (( $# >= 6 )) && _zdraw_motion_valid || return 1
  [[ $zdraw_ui_motion[kind] == settle ]] || return 1
  [[ $zdraw_ui_motion[visible] == 1 ]] || return 0
  local -A zdraw_ui_style
  local -a _zui_emphasis
  local -i _zui_y _zui_x _zui_h _zui_w
  _zdraw_ui_rect "$1" "$2" "$3" "$4" "$5" || return
  (( _zui_h * _zui_w <= 4096 )) || return 1
  if [[ $zdraw_ui_motion[phase] == (running|paused) && $zdraw_ui_motion[mode] == on ]]; then
    case $zdraw_ui_motion[frame] in
      0) _zui_emphasis=(bold) ;;
      1) _zui_emphasis=(underline) ;;
    esac
  fi
  zdraw-ui-style "$6" fg=text bg=surface "${@:7}" "${_zui_emphasis[@]}" || return
  [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[px] == 0 && $zdraw_ui_style[py] == 0 ]] || return 1
  zdraw restyle "$1" "$_zui_y" "$_zui_x" "$_zui_h" "$_zui_w" "$zdraw_ui_style[style]"
}
