# Shared example policy: explicit requests, one at a time, with legacy fallback.
# Caller owns example_protocol_queue, example_protocol_current, protocol_note,
# and the event association. Sourcing does not load a module or touch a terminal.
function example-protocol-next {
  emulate -L zsh
  local next
  example_protocol_current=''
  while (( ${#example_protocol_queue} )); do
    next=$example_protocol_queue[1]
    example_protocol_queue[1]=()
    if zdraw query on && zdraw query request "$next" 1000; then
      example_protocol_current=$next
      protocol_note="Querying $next; legacy input remains available."
      return 0
    fi
    protocol_note="No query available for $next; keeping legacy input."
  done
  return 0
}
function example-protocol-event {
  emulate -L zsh
  [[ ${event[type]-} == capability && ${event[name]-} == $example_protocol_current &&
     ${event[phase]-} == (reply|timeout) ]] || return 1
  local operation=focus
  [[ $example_protocol_current == keyboard_events ]] && operation=keyboard
  if [[ $event[phase] == reply ]] && zdraw "$operation" on 2>/dev/null; then
    [[ $operation == keyboard ]] && example_keyboard_active=1
    protocol_note="$operation reporting enabled."
  else
    protocol_note="$operation reporting unavailable; keeping legacy input."
  fi
  example-protocol-next
}
