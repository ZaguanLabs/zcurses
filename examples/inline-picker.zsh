# Source into the matching interactive Zsh, then explicitly call setup and bind
# zdraw-inline-pick. This is a bounded ZLE experiment, not a curses inline API.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases

  function zdraw-inline-setup {
    emulate -L zsh
    [[ -o interactive ]] || return 1
    zmodload zdraw && zmodload zsh/system && zmodload zsh/zleparameter && zmodload zsh/zutil || return
    [[ ${widgets[zdraw-inline-pick]-} == user:_zdraw_inline_pick ]] && return 0
    [[ -z ${widgets[zdraw-inline-pick]-} ]] || return 1
    autoload -Uz add-zle-hook-widget
    zle -N zdraw-inline-pick _zdraw_inline_pick
  }

  function zdraw-inline-teardown {
    emulate -L zsh
    [[ ${_zinline_active:-0} == 0 ]] || return 1
    [[ ${widgets[zdraw-inline-pick]-} == user:_zdraw_inline_pick ]] || return 1
    zle -D zdraw-inline-pick
  }

  function _zdraw_inline_text {
    emulate -L zsh
    local -A _zinline_measure
    [[ -n $1 && ${#1} -le 256 ]] || return 1
    zdraw textpos _zinline_measure "$1" byte 0 || return
    (( _zinline_measure[total_bytes] <= 256 && _zinline_measure[total_width] > 0 ))
  }

  function _zdraw_inline_draw {
    emulate -L zsh
    local -A _zinline_clip
    local -i _zinline_width=$(( COLUMNS > 3 ? COLUMNS-3 : 0 ))
    local -i _zinline_count=$(( LINES > 6 ? 5 : (LINES > 2 ? LINES-2 : 0) ))
    local -i _zinline_first _zinline_i
    local _zinline_line
    _zinline_columns=$COLUMNS _zinline_lines=$LINES
    # Bound every physical line, reserving a column to avoid automatic wrap.
    (( _zinline_width > 120 )) && _zinline_width=120
    POSTDISPLAY=''
    region_highlight=("${(@)region_highlight:#*memo=zdraw-inline}")
    (( _zinline_width > 0 && _zinline_count > 0 )) || { zle -R; return; }
    _zinline_first=$(( _zinline_selected > _zinline_count ? _zinline_selected-_zinline_count+1 : 1 ))
    for (( _zinline_i=_zinline_first; _zinline_i<=${#_zinline_items} && _zinline_i<_zinline_first+_zinline_count; _zinline_i++ )); do
      zdraw textinfo _zinline_clip "$_zinline_items[$_zinline_i]" "$_zinline_width" || return
      _zinline_line="  $_zinline_clip[text]"
      if (( _zinline_i == _zinline_selected )); then
        _zinline_line="> $_zinline_clip[text]"
        region_highlight+=("$((${#BUFFER}+${#POSTDISPLAY}+1)) $((${#BUFFER}+${#POSTDISPLAY}+1+${#_zinline_line})) standout memo=zdraw-inline")
      fi
      POSTDISPLAY+=$'\n'"$_zinline_line"
    done
    zdraw textinfo _zinline_clip "$_zinline_notice" "$_zinline_width" || return
    POSTDISPLAY+=$'\n'"$_zinline_clip[text]"
    zle -R
  }

  function _zdraw_inline_redraw {
    emulate -L zsh
    [[ ${_zinline_active:-0} == 1 ]] || return 0
    if (( COLUMNS != _zinline_columns || LINES != _zinline_lines )); then
      _zdraw_inline_draw
    fi
    return 0
  }

  function _zdraw_inline_move {
    emulate -L zsh
    [[ ${_zinline_active:-0} == 1 ]] || return 1
    case $WIDGET in
      $_zinline_prefix-up) (( _zinline_selected > 1 )) && (( _zinline_selected-- )) ;;
      $_zinline_prefix-down) (( _zinline_selected < ${#_zinline_items} )) && (( _zinline_selected++ )) ;;
      *) return 1 ;;
    esac
    _zdraw_inline_draw
  }

  function _zdraw_inline_paste {
    emulate -L zsh
    local _zinline_paste
    # Let the existing ZLE paste owner consume the packet without editing BUFFER.
    zle .bracketed-paste _zinline_paste || return
    _zdraw_inline_draw
  }

  function _zdraw_inline_accept {
    emulate -L zsh
    (( _zinline_selected > 0 && _zinline_selected <= ${#_zinline_items} )) || return 1
    _zinline_value=$_zinline_items[$_zinline_selected]
    _zinline_accepted=1
    zle .accept-line
  }

  function _zdraw_inline_close {
    emulate -L zsh
    if (( _zinline_fd >= 0 )); then
      (( _zinline_watching )) && zle -F "$_zinline_fd"
      _zinline_watching=0
      exec {_zinline_fd}<&-
      _zinline_fd=-1
    fi
  }

  function _zdraw_inline_async {
    emulate -L zsh
    [[ ${_zinline_active:-0} == 1 && $WIDGET == $_zinline_prefix-async && $1 == $_zinline_fd ]] || return 0
    local _zinline_chunk _zinline_line
    local -i _zinline_status _zinline_bytes _zinline_changed=0
    # One read per callback; readiness never implies a complete record.
    sysread -i "$_zinline_fd" -s 1024 -t 0 -c _zinline_bytes _zinline_chunk
    _zinline_status=$?
    case $_zinline_status in
      0)
        (( _zinline_total += _zinline_bytes ))
        _zinline_pending+=$_zinline_chunk
        if (( _zinline_total > 16384 )); then
          _zinline_changed=1
          _zinline_notice='Source exceeded its byte limit'
          _zdraw_inline_close
        else
          while [[ $_zinline_pending == *$'\n'* ]]; do
            _zinline_line=${_zinline_pending%%$'\n'*}
            _zinline_pending=${_zinline_pending#*$'\n'}
            if [[ $_zinline_line == done && -z $_zinline_pending ]]; then
              _zinline_changed=1
              _zinline_notice='Source complete / Enter select / Esc cancel'
              _zdraw_inline_close
              break
            elif [[ $_zinline_line == item$'\t'* ]] && (( ${#_zinline_items} < 32 )) &&
                 _zdraw_inline_text "${_zinline_line#*$'\t'}" 2>/dev/null; then
              _zinline_changed=1
              _zinline_items+=("${_zinline_line#*$'\t'}")
              (( _zinline_selected == 0 )) && _zinline_selected=1
            else
              _zinline_changed=1
              _zinline_notice='Invalid source record / Esc cancel'
              _zdraw_inline_close
              break
            fi
          done
        fi ;;
      4) return 0 ;;
      5)
        _zinline_changed=1
        _zinline_notice='Source closed without done / Esc cancel'
        _zdraw_inline_close ;;
      *)
        _zinline_changed=1
        _zinline_notice='Source read failed / Esc cancel'
        _zdraw_inline_close ;;
    esac
    (( _zinline_changed )) && _zdraw_inline_draw
    return 0
  }

  function _zdraw_inline_pick {
    emulate -L zsh
    [[ ${_zinline_active:-0} == 0 && ${(t)zdraw_inline_items} == array* && ${#zdraw_inline_items} -le 32 &&
       ${(t)zdraw_inline_result} == (scalar|scalar-local) ]] || return 1
    # Never share a terminal with an initialized/suspended curses session.
    local -A _zinline_cap
    zdraw capabilities _zinline_cap || return
    [[ $_zinline_cap[session] == inactive ]] || return 2
    local _zinline_item
    for _zinline_item in "${zdraw_inline_items[@]}"; do _zdraw_inline_text "$_zinline_item" || return; done
    local -a _zinline_items=("${zdraw_inline_items[@]}") _zinline_widgets
    local -i _zinline_active=1 _zinline_selected=$(( ${#_zinline_items} ? 1 : 0 ))
    local -i _zinline_fd=-1 _zinline_watching=0 _zinline_total=0 _zinline_columns=0 _zinline_lines=0 _zinline_hook=0 _zinline_map=0 _zinline_accepted=0 _zinline_edit_status=1 _zinline_serial
    local _zinline_pending='' _zinline_notice='Enter select / Esc cancel' _zinline_value=''
    local _zinline_prefix _zinline_name _zinline_old_map=$KEYMAP _zinline_old_post=$POSTDISPLAY
    local _zinline_old_buffer=$BUFFER
    local -i _zinline_old_cursor=$CURSOR _zinline_old_mark=$MARK _zinline_old_region=$REGION_ACTIVE
    local -a _zinline_old_highlights=("${region_highlight[@]}")
    for (( _zinline_serial=0; _zinline_serial<64; _zinline_serial++ )); do
      _zinline_prefix=zdraw-inline-$_zinline_serial
      [[ -n ${keymaps[(Ie)$_zinline_prefix]} && ${keymaps[(Ie)$_zinline_prefix]} != 0 ]] && continue
      for _zinline_name in up down accept async paste redraw; do
        [[ -z ${widgets[$_zinline_prefix-$_zinline_name]-} ]] || break
      done
      [[ $_zinline_name == redraw && -z ${widgets[$_zinline_prefix-redraw]-} ]] && break
    done
    (( _zinline_serial < 64 )) || return 1
    {
      bindkey -N "$_zinline_prefix" || return
      _zinline_map=1
      for _zinline_name in up down accept async paste redraw; do
        case $_zinline_name in
          up|down) zle -N "$_zinline_prefix-$_zinline_name" _zdraw_inline_move ;;
          accept) zle -N "$_zinline_prefix-accept" _zdraw_inline_accept ;;
          async) zle -N "$_zinline_prefix-async" _zdraw_inline_async ;;
          paste) zle -N "$_zinline_prefix-paste" _zdraw_inline_paste ;;
          redraw) zle -N "$_zinline_prefix-redraw" _zdraw_inline_redraw ;;
        esac || return
        _zinline_widgets+=("$_zinline_prefix-$_zinline_name")
      done
      bindkey -M "$_zinline_prefix" '^P' "$_zinline_prefix-up"
      bindkey -M "$_zinline_prefix" '^N' "$_zinline_prefix-down"
      bindkey -M "$_zinline_prefix" $'\e[A' "$_zinline_prefix-up"
      bindkey -M "$_zinline_prefix" $'\e[B' "$_zinline_prefix-down"
      bindkey -M "$_zinline_prefix" $'\eOA' "$_zinline_prefix-up"
      bindkey -M "$_zinline_prefix" $'\eOB' "$_zinline_prefix-down"
      bindkey -M "$_zinline_prefix" '^[[200~' "$_zinline_prefix-paste"
      bindkey -M "$_zinline_prefix" '^M' "$_zinline_prefix-accept"
      bindkey -M "$_zinline_prefix" '^J' "$_zinline_prefix-accept"
      bindkey -M "$_zinline_prefix" '^[' .send-break
      bindkey -M "$_zinline_prefix" '^C' .send-break
      bindkey -M "$_zinline_prefix" '^G' .send-break
      bindkey -M "$_zinline_prefix" '^Z' .send-break
      add-zle-hook-widget line-pre-redraw "$_zinline_prefix-redraw" || return
      _zinline_hook=1
      if [[ -n ${zdraw_inline_source_fd:-} ]]; then
        [[ $zdraw_inline_source_fd == <-> && ${#zdraw_inline_source_fd} -le 5 ]] || return 1
        (( 10#$zdraw_inline_source_fd >= 3 && 10#$zdraw_inline_source_fd <= 32767 )) || return 1
        exec {_zinline_fd}<&$zdraw_inline_source_fd || return
        zle -F -w "$_zinline_fd" "$_zinline_prefix-async" || return
        _zinline_watching=1
        _zinline_notice='Loading / Enter select / Esc cancel'
      fi
      REGION_ACTIVE=0
      zle -K "$_zinline_prefix" || return
      _zdraw_inline_draw || return
      zle .recursive-edit
      _zinline_edit_status=$?
    } always {
      _zdraw_inline_close
      (( _zinline_hook )) && add-zle-hook-widget -d line-pre-redraw "$_zinline_prefix-redraw"
      _zinline_active=0
      zle -K "$_zinline_old_map"
      (( ${#_zinline_widgets} )) && zle -D "${_zinline_widgets[@]}"
      (( _zinline_map )) && bindkey -D "$_zinline_prefix"
      BUFFER=$_zinline_old_buffer CURSOR=$_zinline_old_cursor MARK=$_zinline_old_mark REGION_ACTIVE=$_zinline_old_region
      POSTDISPLAY=$_zinline_old_post
      region_highlight=("${_zinline_old_highlights[@]}")
      zle -R
    }
    (( _zinline_accepted && _zinline_edit_status == 0 )) || return 1
    zdraw_inline_result=$_zinline_value
  }
}
