ZSH_BIN ?= zsh
PYTHON ?= python3

.PHONY: build test clean patch

build:
	+ZCURSES_MAKE="$(MAKE)" "$(ZSH_BIN)" -df scripts/build.zsh

test: build
	"$(ZSH_BIN)" -dfn scripts/build.zsh
	"$(ZSH_BIN)" -dfn tests/geometry.zsh
	"$(PYTHON)" tests/test_geometry.py

# Keep downloaded/extracted sources and other files under .build intact.
clean:
	rm -rf .build/zsh .build/modules .build/source-root

# One focused patch against the recorded upstream files.
patch:
	@diff -u --label a/Src/Modules/curses.c --label b/Src/Modules/curses.c upstream/curses.c Src/Modules/curses.c; result=$$?; test $$result -le 1
	@diff -u --label a/Doc/Zsh/mod_curses.yo --label b/Doc/Zsh/mod_curses.yo upstream/mod_curses.yo Doc/Zsh/mod_curses.yo; result=$$?; test $$result -le 1
