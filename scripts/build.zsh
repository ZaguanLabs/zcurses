#!/usr/bin/env zsh
# Use the matching configured Zsh build without modifying it or installing files.
emulate -R zsh
setopt errexit nounset pipefail
typeset project_root=${0:A:h:h}
typeset source_root=${ZSH_BUILD_ROOT:?Set ZSH_BUILD_ROOT to the matching configured Zsh source tree}
source_root=${source_root:A}
typeset build_root=$project_root/.build/zsh
[[ -f $source_root/config.h && -f $source_root/Src/Modules/Makefile ]] || {
  print -u2 -r -- 'ZSH_BUILD_ROOT must contain a configured, built Zsh tree.'
  exit 1
}
# This first harness deliberately supports the recorded baseline only.
cmp -s "$source_root/Src/Modules/curses.c" "$project_root/upstream/curses.c" || {
  print -u2 -r -- 'Source differs from the recorded curses baseline.'
  exit 1
}
mkdir -p "$project_root/.build"
if [[ ! -d $build_root ]]; then
  cp -a "$source_root" "$build_root"
  print -r -- "$source_root" > "$project_root/.build/source-root"
fi
[[ -f $project_root/.build/source-root && $(<"$project_root/.build/source-root") == $source_root ]] || {
  print -u2 -r -- 'Build cache belongs to another source tree; remove .build and retry.'
  exit 1
}
cp "$project_root"/Src/Modules/{curses.c,curses.mdd,curses_keys.awk} "$build_root/Src/Modules/"
cp "$project_root/Doc/Zsh/mod_curses.yo" "$build_root/Doc/Zsh/"
make -C "$build_root/Src/Modules" curses.so
mkdir -p "$project_root/.build/modules/zsh"
cp "$build_root/Src/Modules/curses.so" "$project_root/.build/modules/zsh/curses.so"
print -r -- "Built $project_root/.build/modules/zsh/curses.so"
