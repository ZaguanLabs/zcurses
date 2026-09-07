.PHONY: build test patch

build:
	zsh -df scripts/build.zsh

test: build
	zsh -dfn scripts/build.zsh
	zsh -dfn tests/geometry.zsh
	python3 tests/test_geometry.py

# One focused patch against the recorded upstream files.
patch:
	@diff -u --label a/Src/Modules/curses.c --label b/Src/Modules/curses.c upstream/curses.c Src/Modules/curses.c; result=$$?; test $$result -le 1
	@diff -u --label a/Doc/Zsh/mod_curses.yo --label b/Doc/Zsh/mod_curses.yo upstream/mod_curses.yo Doc/Zsh/mod_curses.yo; result=$$?; test $$result -le 1
