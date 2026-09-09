ZSH_BIN ?= zsh
PYTHON ?= python3

.PHONY: build test clean patch

build:
	+ZDRAW_MAKE="$(MAKE)" "$(ZSH_BIN)" -df scripts/build.zsh

test: build
	"$(ZSH_BIN)" -dfn scripts/build.zsh
	"$(ZSH_BIN)" -dfn tests/geometry.zsh
	"$(ZSH_BIN)" -dfn tests/drawing.zsh
	"$(ZSH_BIN)" -dfn tests/colorinfo.zsh
	"$(ZSH_BIN)" -dfn tests/cellinfo.zsh
	"$(ZSH_BIN)" -dfn tests/snapshot.zsh
	"$(ZSH_BIN)" -dfn tests/fill.zsh
	"$(ZSH_BIN)" -dfn tests/spans.zsh
	"$(ZSH_BIN)" -dfn tests/truecolor.zsh
	"$(ZSH_BIN)" -dfn tests/textinfo.zsh
	"$(ZSH_BIN)" -dfn tests/textpos.zsh
	"$(ZSH_BIN)" -dfn tests/events.zsh
	"$(ZSH_BIN)" -dfn tests/presentation.zsh
	"$(ZSH_BIN)" -dfn tests/prepared.zsh
	"$(ZSH_BIN)" -dfn tests/clipping.zsh
	"$(ZSH_BIN)" -dfn benchmarks/spans.zsh
	"$(ZSH_BIN)" -dfn benchmarks/fill.zsh
	"$(ZSH_BIN)" -dfn examples/events.zsh
	"$(ZSH_BIN)" -dfn examples/hit-test.zsh
	"$(ZSH_BIN)" -dfn examples/borders.zsh
	"$(ZSH_BIN)" -dfn examples/colors.zsh
	"$(ZSH_BIN)" -dfn examples/cell-inspection.zsh
	"$(ZSH_BIN)" -dfn examples/snapshot-diff.zsh
	"$(ZSH_BIN)" -dfn examples/regions.zsh
	"$(ZSH_BIN)" -dfn examples/truecolor.zsh
	"$(ZSH_BIN)" -dfn examples/clipping.zsh
	ZDRAW_MAKE="$(MAKE)" "$(PYTHON)" -m unittest discover -s tests -v

# Keep downloaded/extracted sources and other files under .build intact.
clean:
	rm -rf .build/zsh .build/modules .build/source-root

# Export an additive Zsh integration patch, leaving zsh/curses untouched.
patch:
	@cat patches/zdraw-build.patch
	@for file in Src/Modules/zdraw.c Src/Modules/zdraw.mdd Src/Modules/zdraw_keys.awk Doc/Zsh/mod_zdraw.yo; do \
	  diff -u --label /dev/null --label b/$$file /dev/null $$file; result=$$?; \
	  test $$result -le 1 || exit $$result; \
	done
