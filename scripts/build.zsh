#!/usr/bin/env zsh
# Build against supplied Zsh sources without modifying them or installing files.
emulate -R zsh
setopt errexit nounset pipefail
typeset project_root=${0:A:h:h}
typeset source_root=${ZSH_BUILD_ROOT:?Set ZSH_BUILD_ROOT to an extracted Zsh release or configured in-tree build; see README.md}
source_root=${source_root:A}
typeset build_root=$project_root/.build/zsh
typeset make_command=${ZCURSES_MAKE:-make}
[[ -f $source_root/configure && -f $source_root/Src/zsh.h &&
   -f $source_root/Src/Modules/curses.mdd ]] || {
  print -u2 -r -- 'ZSH_BUILD_ROOT must contain Zsh sources with a configure script.'
  exit 1
}
[[ $source_root != $build_root && $source_root != $build_root/* &&
   $build_root != $source_root/* ]] || {
  print -u2 -r -- 'ZSH_BUILD_ROOT must be separate from the .build/zsh working copy.'
  exit 1
}
# Configured builds must use relative in-tree source paths so their copied
# makefiles cannot regenerate files in the supplied source tree.
if [[ -f $source_root/config.status ]]; then
  [[ -f $source_root/config.h && -f $source_root/Src/Makefile &&
     -f $source_root/Src/Modules/Makefile ]] &&
    awk '/^sdir[ \t]*=/ { if ($3 == ".") ok = 1 } END { exit !ok }' \
      "$source_root/Src/Modules/Makefile" || {
    print -u2 -r -- 'Use an extracted release or a configured in-tree build with relative source paths.'
    exit 1
  }
fi
mkdir -p "$project_root/.build"
if [[ ! -d $build_root ]]; then
  # -R -P -p works with both POSIX/BSD and GNU cp.
  cp -R -P -p "$source_root" "$build_root"
  print -r -- "$source_root" > "$project_root/.build/source-root"
fi
[[ -f $project_root/.build/source-root && $(<"$project_root/.build/source-root") == $source_root ]] || {
  print -u2 -r -- 'Build cache belongs to another source tree; run make clean and retry.'
  exit 1
}
cp "$project_root"/Src/Modules/{curses.c,curses.mdd,curses_keys.awk} "$build_root/Src/Modules/"
cp "$project_root/Doc/Zsh/mod_curses.yo" "$build_root/Doc/Zsh/"
# Add the drawing function checks using Zsh's own configure machinery.
# Only the disposable working copy is patched, including for configured inputs.
typeset configure_patch=$project_root/patches/configure-wide-borders.patch
typeset configure_stamp=$build_root/.zcurses-configure-patch
if [[ ! -f $configure_stamp ]]; then
  (
    cd "$build_root"
    patch -p1 < "$configure_patch"
    autoconf
    autoheader
    if [[ -f config.status ]]; then
      ./config.status --recheck
      ./config.status
    fi
  )
  cp "$configure_patch" "$configure_stamp"
elif ! cmp -s "$configure_patch" "$configure_stamp"; then
  print -u2 -r -- 'Configuration patch changed; run make clean and retry.'
  exit 1
fi
if [[ ! -f $build_root/config.status ]]; then
  ( cd "$build_root"; ./configure --enable-dynamic )
fi
[[ -f $build_root/config.h ]] || {
  print -u2 -r -- 'Zsh configuration is incomplete; run make clean and retry.'
  exit 1
}
awk '$1 == "name=zsh/curses" { for (i = 2; i <= NF; i++) if ($i == "link=dynamic") ok = 1 }
     END { exit !ok }' "$build_root/config.modules" || {
  print -u2 -r -- 'Zsh must enable dynamic zsh/curses; install curses development headers/libraries, then run make clean and retry.'
  exit 1
}
# Build the shell as well, so tests have a host with the same configuration/ABI.
# Building Src avoids the documentation-generation toolchain.
"$make_command" -C "$build_root/Src"
typeset module_extension
module_extension=$(awk '$1 == "DL_EXT" && $2 == "=" { print $3; exit }' "$build_root/Src/Makefile")
[[ -n $module_extension && -f $build_root/Src/Modules/curses.$module_extension ]] || {
  print -u2 -r -- 'Zsh did not produce a loadable curses module.'
  exit 1
}
mkdir -p "$project_root/.build/modules/zsh"
cp "$build_root/Src/Modules/curses.$module_extension" "$project_root/.build/modules/zsh/"
print -r -- "Built $project_root/.build/modules/zsh/curses.$module_extension"
