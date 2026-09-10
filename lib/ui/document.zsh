# These helpers populate scratch state owned by the document compiler.
function _zdraw_ui_document_bytes {
  emulate -L zsh
  local LC_ALL=C
  REPLY=${#1}
}

function _zdraw_ui_document_line {
  emulate -L zsh
  (( _zui_line < 4096 )) || return 1
  (( _zui_line++ ))
  _zui_doc[$_zui_line,text]=$1 _zui_doc[$_zui_line,role]=$2
  _zui_doc[$_zui_line,block]=$_zui_block
  _zui_doc[$_zui_line,byte_start]=$3 _zui_doc[$_zui_line,byte_end]=$4
}

function zdraw-document-init {
  emulate -L zsh
  [[ $# -ge 1 && ${(t)zdraw_ui_document} == (association|association-local) ]] || return 1
  _zdraw_ui_uint "$1" || return 1
  (( 10#$1 > 0 && ($# - 1) % 3 == 0 && $# <= 385 )) || return 1
  local -i _zui_columns=$((10#$1)) _zui_count=$((($# - 1)/3)) _zui_block=0 _zui_line=0
  local -i _zui_offset _zui_end _zui_total=0 _zui_budget _zui_first _zui_more _zui_cut
  local -A _zui_doc=(format zdraw-document-1 columns "$_zui_columns" count "$_zui_count" first 1)
  local -A _zui_ids _zui_info _zui_pos
  local _zui_id _zui_kind _zui_source _zui_remaining _zui_logical _zui_rest _zui_prefix _zui_piece _zui_soft REPLY
  shift
  while (( $# )); do
    _zui_id=$1 _zui_kind=$2 _zui_source=$3
    [[ ${#_zui_id} -le 48 && $_zui_id == [A-Za-z_]* && $_zui_id != *[^A-Za-z0-9_-]* ]] || return 1
    [[ ! -v "_zui_ids[$_zui_id]" ]] || return 1
    [[ $_zui_kind == (heading|subheading|paragraph|bullet|quote|code|separator) ]] || return 1
    [[ $_zui_kind != separator || -z $_zui_source ]] || return 1
    _zdraw_ui_document_bytes "$_zui_source"
    (( REPLY <= 32767 )) || return 1
    (( _zui_total += REPLY ))
    (( _zui_total <= 65536 )) || return 1
    (( _zui_block++ ))
    _zui_ids[$_zui_id]=1
    _zui_doc[b,$_zui_block,id]=$_zui_id _zui_doc[b,$_zui_block,kind]=$_zui_kind
    _zui_doc[b,$_zui_block,text]=$_zui_source _zui_doc[b,$_zui_block,line]=$((_zui_line+1))
    _zui_offset=0 _zui_first=1 _zui_remaining=$_zui_source
    while true; do
      _zui_more=0 _zui_logical=$_zui_remaining
      if [[ $_zui_remaining == *$'\n'* ]]; then
        _zui_logical=${_zui_remaining%%$'\n'*}
        _zui_remaining=${_zui_remaining#*$'\n'} _zui_more=1
      fi
      # All controls except the explicitly split line feeds remain invalid data.
      zdraw textinfo _zui_info "$_zui_logical" || return
      _zui_rest=$_zui_logical
      while true; do
        _zui_prefix=''
        if (( _zui_columns >= 3 )); then
          case $_zui_kind in
            bullet) if (( _zui_first )); then _zui_prefix='- '; else _zui_prefix='  '; fi ;;
            quote) _zui_prefix='| ' ;;
            code) _zui_prefix='  ' ;;
          esac
        fi
        _zui_budget=$((_zui_columns-${#_zui_prefix}))
        zdraw textinfo _zui_info "$_zui_rest" "$_zui_budget" || return
        _zui_piece=$_zui_info[text]
        # A whole wide unit cannot fit. Leave the previous document untouched.
        [[ -n $_zui_piece || -z $_zui_rest ]] || return 2
        if [[ $_zui_kind != code && $_zui_info[truncated] == 1 && $_zui_piece == *' '* ]]; then
          _zui_soft="${_zui_piece% *} "
          _zdraw_ui_document_bytes "$_zui_soft"
          _zui_cut=$REPLY
          zdraw textpos _zui_pos "$_zui_rest" byte "$_zui_cut" || return
          # A space followed by combining marks is one indivisible unit too.
          (( _zui_pos[byte_start] == _zui_cut )) && _zui_piece=$_zui_soft
        fi
        _zdraw_ui_document_bytes "$_zui_piece"
        _zui_end=$((_zui_offset+REPLY))
        _zdraw_ui_document_line "$_zui_prefix$_zui_piece" "$_zui_kind" "$_zui_offset" "$_zui_end" || return
        _zui_offset=$_zui_end _zui_first=0
        [[ $_zui_piece == "$_zui_rest" ]] && break
        _zui_rest=${_zui_rest[${#_zui_piece}+1,-1]}
      done
      (( _zui_more )) || break
      (( _zui_offset++ ))  # Original source byte occupied by the line feed.
    done
    shift 3
    # Consecutive bullets form a compact list; other blocks have a breathing row.
    if (( $# )) && [[ $_zui_kind != bullet || $2 != bullet ]]; then
      _zdraw_ui_document_line '' spacer "$_zui_offset" "$_zui_offset" || return
    fi
  done
  _zui_doc[line_count]=$_zui_line
  zdraw_ui_document=("${(@kv)_zui_doc}")
}

function _zdraw_ui_document_state {
  emulate -L zsh
  [[ ${(t)zdraw_ui_document} == association* && ${zdraw_ui_document[format]-} == zdraw-document-1 ]] || return 1
  local _zui_key
  for _zui_key in columns count first line_count; do
    _zdraw_ui_uint "${zdraw_ui_document[$_zui_key]-}" || return 1
  done
  (( 10#$zdraw_ui_document[columns] > 0 && 10#$zdraw_ui_document[count] <= 128 &&
     10#$zdraw_ui_document[line_count] <= 4096 && 10#$zdraw_ui_document[first] > 0 &&
     (10#$zdraw_ui_document[first] <= 10#$zdraw_ui_document[line_count] ||
      (10#$zdraw_ui_document[first] == 1 && 10#$zdraw_ui_document[line_count] == 0)) ))
}

# Compile from retained source, locating the previous top source byte afterward.
function zdraw-document-reflow {
  emulate -L zsh
  [[ $# == 1 && ${(t)zdraw_ui_document} == (association|association-local) ]] || return 1
  _zdraw_ui_document_state || return
  local -A _zui_reflow
  local -a _zui_blocks
  local -i _zui_i _zui_top=$((10#$zdraw_ui_document[first])) _zui_block=0 _zui_byte=0
  if (( 10#$zdraw_ui_document[line_count] )); then
    _zdraw_ui_uint "${zdraw_ui_document[$_zui_top,block]-}" &&
      _zdraw_ui_uint "${zdraw_ui_document[$_zui_top,byte_start]-}" || return 1
    _zui_block=$((10#$zdraw_ui_document[$_zui_top,block]))
    _zui_byte=$((10#$zdraw_ui_document[$_zui_top,byte_start]))
  fi
  for (( _zui_i=1; _zui_i<=10#$zdraw_ui_document[count]; _zui_i++ )); do
    _zui_blocks+=("${zdraw_ui_document[b,$_zui_i,id]-}" "${zdraw_ui_document[b,$_zui_i,kind]-}" "${zdraw_ui_document[b,$_zui_i,text]-}")
  done
  () {
    local -A zdraw_ui_document
    zdraw-document-init "$@" || return
    _zui_reflow=("${(@kv)zdraw_ui_document}")
  } "$1" "${_zui_blocks[@]}" || return
  for (( _zui_i=1; _zui_i<=_zui_reflow[line_count]; _zui_i++ )); do
    if (( _zui_reflow[$_zui_i,block] == _zui_block && _zui_reflow[$_zui_i,byte_start] <= _zui_byte )); then
      _zui_reflow[first]=$_zui_i
    fi
  done
  zdraw_ui_document=("${(@kv)_zui_reflow}")
}

function zdraw-document-scroll {
  emulate -L zsh
  [[ $# -ge 2 && $# -le 3 && ${(t)zdraw_ui_document} == (association|association-local) ]] || return 1
  _zdraw_ui_document_state && _zdraw_ui_uint "$1" || return 1
  [[ $2 == (keep|up|down|page-up|page-down|home|end|next-heading|previous-heading|anchor) ]] || return 1
  [[ ( $2 == anchor && $# == 3 ) || ( $2 != anchor && $# == 2 ) ]] || return 1
  local -i _zui_first=$((10#$zdraw_ui_document[first])) _zui_visible=$((10#$1)) _zui_max _zui_step _zui_i _zui_target=0 _zui_line
  local _zui_kind
  _zui_step=$((_zui_visible > 1 ? _zui_visible-1 : 1))
  _zui_max=$((10#$zdraw_ui_document[line_count] - (_zui_visible > 0 ? _zui_visible : 1) + 1))
  (( _zui_max < 1 )) && _zui_max=1
  case $2 in
    up) (( _zui_first-- )) ;; down) (( _zui_first++ )) ;;
    home) _zui_first=1 ;; end) _zui_first=$_zui_max ;;
    page-up) (( _zui_first-=_zui_step )) ;; page-down) (( _zui_first+=_zui_step )) ;;
    next-heading|previous-heading|anchor)
      for (( _zui_i=1; _zui_i<=10#$zdraw_ui_document[count]; _zui_i++ )); do
        _zdraw_ui_uint "${zdraw_ui_document[b,$_zui_i,line]-}" || return 1
        _zui_line=$((10#$zdraw_ui_document[b,$_zui_i,line]))
        _zui_kind=${zdraw_ui_document[b,$_zui_i,kind]-}
        if [[ $2 == anchor ]]; then
          [[ ${zdraw_ui_document[b,$_zui_i,id]-} == "$3" ]] && _zui_target=$_zui_line
        elif [[ $_zui_kind == (heading|subheading) ]]; then
          if [[ $2 == next-heading ]] && (( _zui_line > _zui_first && _zui_target == 0 )); then _zui_target=$_zui_line
          elif [[ $2 == previous-heading ]] && (( _zui_line < _zui_first )); then _zui_target=$_zui_line; fi
        fi
      done
      [[ $2 != anchor || $_zui_target -gt 0 ]] || return 1
      (( _zui_target )) && _zui_first=$_zui_target ;;
  esac
  (( _zui_first < 1 )) && _zui_first=1
  (( _zui_first > _zui_max )) && _zui_first=$_zui_max
  zdraw_ui_document[first]=$_zui_first
}

function zdraw-document {
  emulate -L zsh
  (( $# >= 6 )) || return 1
  _zdraw_ui_document_state || return
  local _zui_win=$1 _zui_states=$6 _zui_role _zui_text
  local -i _zui_y _zui_x _zui_h _zui_w _zui_i _zui_row
  local -A zdraw_ui_style _zui_styles _zui_info
  _zdraw_ui_rect "$1" "$2" "$3" "$4" "$5" || return
  (( _zui_w == 10#$zdraw_ui_document[columns] )) || return 1
  # Resolve every role before painting, including roles outside the viewport.
  local -a _zui_defaults=(fg=text bg=surface heading:fg=accent heading:bold
    subheading:fg=accent subheading:bold quote:fg=muted code:bg=canvas separator:fg=border)
  for _zui_role in heading subheading paragraph bullet quote code separator spacer; do
    zdraw-ui-style "$_zui_states,$_zui_role" "${_zui_defaults[@]}" "${@:7}" || return
    [[ $zdraw_ui_style[border] == none && $zdraw_ui_style[px] == 0 && $zdraw_ui_style[py] == 0 && $zdraw_ui_style[align] == left ]] || return 1
    _zui_styles[$_zui_role]=$zdraw_ui_style[style]
  done
  for (( _zui_i=1; _zui_i<=10#$zdraw_ui_document[line_count]; _zui_i++ )); do
    _zui_role=${zdraw_ui_document[$_zui_i,role]-}
    [[ $_zui_role == (heading|subheading|paragraph|bullet|quote|code|separator|spacer) ]] || return 1
    zdraw textinfo _zui_info "${zdraw_ui_document[$_zui_i,text]-}" || return
    (( _zui_info[width] <= _zui_w )) || return 1
  done
  zdraw fill "$_zui_win" "$_zui_y" "$_zui_x" "$_zui_h" "$_zui_w" "$_zui_styles[paragraph]" ' ' || return
  for (( _zui_row=0, _zui_i=10#$zdraw_ui_document[first]; _zui_row<_zui_h && _zui_i<=10#$zdraw_ui_document[line_count]; _zui_row++, _zui_i++ )); do
    _zui_role=$zdraw_ui_document[$_zui_i,role] _zui_text=${zdraw_ui_document[$_zui_i,text]-}
    if [[ $_zui_role == separator ]]; then
      zdraw fill "$_zui_win" "$((_zui_y+_zui_row))" "$_zui_x" 1 "$_zui_w" "$_zui_styles[$_zui_role]" '-' || return
    else
      zdraw fill "$_zui_win" "$((_zui_y+_zui_row))" "$_zui_x" 1 "$_zui_w" "$_zui_styles[$_zui_role]" ' ' || return
      _zdraw_ui_row "$_zui_win" "$((_zui_y+_zui_row))" "$_zui_x" "$_zui_w" left "$_zui_text" "$_zui_styles[$_zui_role]" || return
    fi
  done
  return 0
}
