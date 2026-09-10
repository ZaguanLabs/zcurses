#!/usr/bin/env zsh
# Launch a disposable interactive configuration; never edit the user's startup files.
emulate -R zsh
setopt errexit
[[ $# == 0 ]] || { print -ru2 -- 'usage: inline-shell.zsh'; exit 1; }
typeset inline_root=${0:A:h:h} inline_dotdir
typeset -i inline_status=0
[[ -x $inline_root/.build/zsh/Src/zsh && -f $inline_root/.build/functions/add-zle-hook-widget ]] || {
  print -ru2 -- 'Build zdraw against public Zsh sources first.'; exit 1
}
inline_dotdir=$(mktemp -d "$inline_root/.build/inline-shell.XXXXXXXX")
{
  cat > "$inline_dotdir/.zshrc" <<'RC'
module_path=("$ZDRAW_INLINE_ROOT/.build/modules")
fpath=("$ZDRAW_INLINE_ROOT/.build/functions" "${fpath[@]}")
source "$ZDRAW_INLINE_ROOT/examples/inline-picker.zsh" || return
zdraw-inline-setup || return
typeset -a zdraw_inline_items=('local cache' 'remote index' 'release notes' '界面')
typeset zdraw_inline_result=''
# Opt in to insertion at a shell-word boundary; selection itself returns data.
function zdraw-inline-insert {
  emulate -L zsh
  [[ -z $RBUFFER && ( -z $LBUFFER || $LBUFFER == *[[:space:]] ) ]] || {
    zle -M 'Place the cursor after whitespace at the end of the command.'; return 1
  }
  if zle zdraw-inline-pick; then
    LBUFFER+="${(q)zdraw_inline_result}"
  fi
}
zle -N zdraw-inline-insert
bindkey -M emacs '^X^I' zdraw-inline-insert
bindkey -M viins '^X^I' zdraw-inline-insert
PROMPT='inline%# '
print -r -- 'Inline picker experiment: Ctrl-X Tab opens; arrows select; Enter returns; Esc cancels.'
print -r -- 'Try: print -r -- <Ctrl-X Tab>. Exit this shell when finished.'
RC
  if ZDRAW_INLINE_ROOT=$inline_root ZDOTDIR=$inline_dotdir "$inline_root/.build/zsh/Src/zsh" -di; then
    inline_status=0
  else
    inline_status=$?
  fi
} always {
  rm -rf -- "$inline_dotdir"
}
exit $inline_status
