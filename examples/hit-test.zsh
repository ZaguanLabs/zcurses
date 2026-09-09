#!/usr/bin/env zsh
# Run with the matching built shell; --mouse explicitly enables mouse reporting.
emulate -R zsh
setopt errexit nounset
module_path=("${0:A:h:h}/.build/modules")
typeset -a input_options dimensions
if (( $# )); then
  [[ $# == 1 && $1 == --mouse ]] || { print -ru2 -- 'Usage: hit-test.zsh [--mouse]'; exit 1; }
  input_options=(mouse)
fi
zmodload zdraw
(( ${zdraw_features[(Ie)text_positions]} && ${zdraw_features[(Ie)prepared_rows]} ))
if (( ${zdraw_features[(Ie)norefresh_events]} )); then
  input_options+=(norefresh)
fi
typeset text='A sample line to select'
if (( ${zdraw_features[(Ie)wide_spans]} && ${zdraw_features[(Ie)wide_text]} )); then
  # Fall back to ASCII when run in a non-Unicode locale.
  typeset -A probe
  if zdraw textinfo probe 'Café 界 ă' 2>/dev/null; then
    text='Café 界 ă'
  fi
fi
typeset -A event hit visible
typeset -i column=0 dirty=1 available=0
typeset label
zdraw init
{
  zdraw prepare heading bold 'Text positions - arrows or mouse; q quits'
  zdraw timeout stdscr 100
  while true; do
    if (( dirty )); then
      zdraw position stdscr dimensions
      zdraw clear stdscr
      available=0
      if (( dimensions[5] >= 7 && dimensions[6] >= 8 )); then
        zdraw draw stdscr 0 0 heading "$dimensions[6]"
        zdraw textinfo visible "$text" "$(( dimensions[6] - 2 ))"
        available=$visible[width]
        (( column < available )) || column=$(( available > 0 ? available - 1 : 0 ))
        zdraw textpos hit "$visible[text]" column "$column"
        zdraw spans stdscr 2 1 '' "$hit[prefix]" reverse "$hit[text]" '' "$hit[remainder]"
        label="Bytes [$hit[byte_start], $hit[byte_end]); columns [$hit[column_start], $hit[column_end])"
        zdraw spansclip stdscr 4 0 "$dimensions[6]" '' "$label"
        zdraw spansclip stdscr 5 0 "$dimensions[6]" '' 'Offsets start at zero; range ends are exclusive.'
      fi
      zdraw refresh
      dirty=0
    fi
    if zdraw event stdscr event "${input_options[@]}"; then
      case $event[type] in
        character) [[ $event[text] == q ]] && break ;;
        key)
          if [[ $event[key] == LEFT ]] && (( column > 0 )); then
            (( --column )) || true
            dirty=1
          elif [[ $event[key] == RIGHT ]] && (( column + 1 < available )); then
            (( ++column ))
            dirty=1
          fi ;;
        mouse)
          if (( event[y] == 2 && event[x] >= 1 && event[x] <= available )); then
            column=$(( event[x] - 1 ))
            dirty=1
          fi ;;
        resize)
          if (( ${zdraw_features[(Ie)resize]} )); then
            zdraw resize "$event[rows]" "$event[columns]" nosave
          fi
          dirty=1 ;;
      esac
    fi
  done
} always {
  zdraw end
}
