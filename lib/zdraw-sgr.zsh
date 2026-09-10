# Source once after loading zdraw. Caller-owned state and reply are dynamically
# scoped, so independent streams can use separate enclosing function locals.
_zdraw_sgr_emit() {
  emulate -L zsh
  local _za _zstyle=''
  if [[ -n $_zs[text] ]]; then
    (( ${#_zr} < 6144 )) || return 1
    for _za in bold dim underline blink reverse; do
      [[ $_zs[$_za] == 1 ]] && _zstyle+="${_za},"
    done
    if [[ $_zs[fg] != default || $_zs[bg] != default ]]; then
      _zstyle+="$_zs[fg]/$_zs[bg]"
    else
      _zstyle=${_zstyle%,}
    fi
    _zr+=(text "$_zstyle" "$_zs[text]")
    _zs[text]=''
  fi
  if [[ $1 != text ]]; then
    (( ${#_zr} < 6144 )) || return 1
    _zr+=("$1" '' '')
  fi
}

_zdraw_sgr_style() {
  emulate -L zsh
  local -a _zp=("${(@s:;:)_zs[seq]}")
  local -A _zold=("${(@kv)_zs}")
  local _zv _ztarget _zcolor
  local -i _zi _zn _zrval _zgval _zbval
  (( ${#_zp} )) || _zp=(0)
  for _zv in "${_zp[@]}"; do
    [[ -z $_zv || ( $_zv == <-> && ${#_zv} -le 3 ) ]] || return 0
  done
  for (( _zi=1; _zi<=${#_zp}; _zi++ )); do
    _zn=$(( 10#${_zp[$_zi]:-0} ))
    case $_zn in
      0) _zs[fg]=default _zs[bg]=default
         for _zv in bold dim underline blink reverse; do _zs[$_zv]=0; done ;;
      1) _zs[bold]=1 ;; 2) _zs[dim]=1 ;; 4) _zs[underline]=1 ;;
      5) _zs[blink]=1 ;; 7) _zs[reverse]=1 ;;
      22) _zs[bold]=0 _zs[dim]=0 ;; 24) _zs[underline]=0 ;;
      25) _zs[blink]=0 ;; 27) _zs[reverse]=0 ;;
      39) _zs[fg]=default ;; 49) _zs[bg]=default ;;
      38|48)
        [[ $_zn == 38 ]] && _ztarget=fg || _ztarget=bg
        if [[ ${_zp[$(( _zi + 1 ))]:-} == 5 ]] && (( _zi + 2 <= ${#_zp} )); then
          _zn=$(( 10#${_zp[$(( _zi + 2 ))]:-0} ))
          if (( _zn > 255 )); then _zs=("${(@kv)_zold}"); return 0; fi
          _zs[$_ztarget]=$_zn
          _zi=$(( _zi + 2 ))
        elif [[ ${_zp[$(( _zi + 1 ))]:-} == 2 ]] && (( _zi + 4 <= ${#_zp} )); then
          _zrval=$(( 10#${_zp[$(( _zi + 2 ))]:-0} ))
          _zgval=$(( 10#${_zp[$(( _zi + 3 ))]:-0} ))
          _zbval=$(( 10#${_zp[$(( _zi + 4 ))]:-0} ))
          if (( _zrval > 255 || _zgval > 255 || _zbval > 255 )); then
            _zs=("${(@kv)_zold}"); return 0
          fi
          printf -v _zcolor '#%02x%02x%02x' "$_zrval" "$_zgval" "$_zbval"
          _zs[$_ztarget]=$_zcolor
          _zi=$(( _zi + 4 ))
        else
          _zs=("${(@kv)_zold}"); return 0
        fi ;;
      *)
        if (( _zn >= 30 && _zn <= 37 )); then _zs[fg]=$(( _zn - 30 ))
        elif (( _zn >= 40 && _zn <= 47 )); then _zs[bg]=$(( _zn - 40 ))
        elif (( _zn >= 90 && _zn <= 97 )); then _zs[fg]=$(( _zn - 90 + 8 ))
        elif (( _zn >= 100 && _zn <= 107 )); then _zs[bg]=$(( _zn - 100 + 8 ))
        fi ;;
    esac
  done
  return 0
}

zdraw-sgr-feed() {
  emulate -L zsh
  [[ $# == 1 || ( $# == 2 && $2 == final ) ]] || return 1
  (( ${+zdraw_sgr_state} && ${+reply} )) || return 1
  # Ordinary caller-owned parameters only. No evaluation or indirect setters.
  [[ ${(t)zdraw_sgr_state} == association* && ${(t)zdraw_sgr_state} != *readonly* &&
     ${(t)zdraw_sgr_state} != *special* && ${(t)reply} == array* &&
     ${(t)reply} != *readonly* && ${(t)reply} != *special* ]] || return 1
  local -A _zs=("${(@kv)zdraw_sgr_state}") _zcheck
  local -a _zr
  local _zchunk=$1 _zchar _zrun _zmulti=off
  [[ -o multibyte ]] && _zmulti=on
  local -i _zi _zlen
  if (( ! ${#_zs} )); then
    _zs=(format zdraw-sgr-1 mode text text '' seq '' fg default bg default
         bold 0 dim 0 underline 0 blink 0 reverse 0)
  fi
  [[ ${_zs[format]:-} == zdraw-sgr-1 ]] || return 1
  unsetopt multibyte
  _zlen=${#_zchunk}
  (( _zlen <= 65536 && ${#_zs[text]} <= 65536 && ${#_zs[seq]} <= 64 )) || return 1
  for (( _zi=1; _zi<=_zlen; _zi++ )); do
    _zchar=$_zchunk[$_zi]
    case $_zs[mode] in
      text)
        case $_zchar in
          $'\e') _zdraw_sgr_emit text || return; _zs[mode]=escape ;;
          $'\n') _zdraw_sgr_emit newline || return ;;
          $'\r') _zdraw_sgr_emit carriage_return || return ;;
          $'\t') _zdraw_sgr_emit tab || return ;;
          [$'\x00'-$'\x1f'$'\x7f']) ;; # Other controls never become drawing text.
          *) _zrun=${_zchunk[$_zi,-1]}
             _zrun=${_zrun%%[$'\x00'-$'\x1f'$'\x7f']*}
             _zs[text]+=$_zrun
             _zi=$(( _zi + ${#_zrun} - 1 ))
             (( ${#_zs[text]} <= 65536 )) || return 1 ;;
        esac ;;
      escape)
        case $_zchar in
          '[') _zs[mode]=csi _zs[seq]='' ;;
          ']') _zs[mode]=osc ;;
          P|X|'^'|'_') _zs[mode]=string ;;
          $'\e') ;;
          [\ -/]) _zs[mode]=escape_intermediate ;;
          *) _zs[mode]=text ;;
        esac ;;
      escape_intermediate)
        [[ $_zchar == [0-~] ]] && _zs[mode]=text ;;
      csi)
        if [[ $_zchar == [@-~] ]]; then
          [[ $_zchar == m ]] && _zdraw_sgr_style
          _zs[mode]=text _zs[seq]=''
        elif [[ $_zchar == [\ -\?] ]]; then
          _zs[seq]+=$_zchar
          (( ${#_zs[seq]} <= 64 )) || { _zs[seq]=''; _zs[mode]=csi_discard; }
        elif [[ $_zchar == $'\e' ]]; then
          _zs[mode]=escape _zs[seq]=''
        else
          _zs[mode]=csi_discard _zs[seq]=''
        fi ;;
      csi_discard) [[ $_zchar == [@-~] ]] && _zs[mode]=text ;;
      osc|string)
        if [[ $_zchar == $'\e' ]]; then
          _zs[mode]="$_zs[mode]_escape"
        elif [[ $_zs[mode] == osc && $_zchar == $'\a' ]]; then
          _zs[mode]=text
        fi ;;
      osc_escape|string_escape)
        if [[ $_zchar == '\' || ( $_zs[mode] == osc_escape && $_zchar == $'\a' ) ]]; then
          _zs[mode]=text
        elif [[ $_zchar != $'\e' ]]; then
          _zs[mode]=${_zs[mode]%_escape}
        fi ;;
      *) return 1 ;;
    esac
  done
  if [[ ${2:-} == final ]]; then
    _zdraw_sgr_emit text || return
  fi
  [[ $_zmulti == on ]] && setopt multibyte
  for (( _zi=1; _zi<=${#_zr}; _zi+=3 )); do
    if [[ $_zr[$_zi] == text ]]; then
      zdraw textinfo _zcheck "$_zr[$(( _zi + 2 ))]" 2>/dev/null || return 1
    fi
  done
  [[ ${2:-} == final ]] && _zs=()
  zdraw_sgr_state=("${(@kv)_zs}")
  reply=("${_zr[@]}")
  return 0
}
