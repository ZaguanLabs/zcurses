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
	"$(ZSH_BIN)" -dfn tests/copy.zsh
	"$(ZSH_BIN)" -dfn tests/restyle.zsh
	"$(ZSH_BIN)" -dfn tests/pads.zsh
	"$(ZSH_BIN)" -dfn tests/resizepad.zsh
	"$(ZSH_BIN)" -dfn tests/windows.zsh
	"$(ZSH_BIN)" -dfn tests/window-presentation.zsh
	"$(ZSH_BIN)" -dfn tests/pad-presentation.zsh
	"$(ZSH_BIN)" -dfn tests/spans.zsh
	"$(ZSH_BIN)" -dfn tests/truecolor.zsh
	"$(ZSH_BIN)" -dfn tests/textinfo.zsh
	"$(ZSH_BIN)" -dfn tests/textpos.zsh
	"$(ZSH_BIN)" -dfn tests/textwrap.zsh
	"$(ZSH_BIN)" -dfn tests/events.zsh
	"$(ZSH_BIN)" -dfn tests/session.zsh
	"$(ZSH_BIN)" -dfn tests/session-errors.zsh
	"$(ZSH_BIN)" -dfn tests/sgr.zsh
	"$(ZSH_BIN)" -dfn lib/zdraw-sgr.zsh
	"$(ZSH_BIN)" -dfn lib/zdraw-run.zsh
	"$(ZSH_BIN)" -dfn lib/zdraw-fixture.zsh
	"$(ZSH_BIN)" -dfn tests/visual.zsh
	@for file in lib/zdraw-ui.zsh lib/zdraw-panel.zsh lib/zdraw-list.zsh lib/zdraw-layout.zsh lib/zdraw-table.zsh lib/zdraw-tabs.zsh lib/zdraw-meter.zsh lib/zdraw-badge.zsh lib/zdraw-help.zsh lib/zdraw-input.zsh lib/zdraw-form.zsh lib/zdraw-document.zsh lib/zdraw-chart.zsh lib/zdraw-sparkline.zsh lib/zdraw-bars.zsh lib/zdraw-canvas.zsh lib/ui/*.zsh tests/ui*.zsh tests/gallery.zsh tests/composition.zsh tests/capabilities.zsh tests/job-control.zsh scripts/portability/terminal.zsh examples/capabilities.zsh examples/gallery.zsh examples/list-detail.zsh examples/table-inspector.zsh examples/task-monitor.zsh examples/form.zsh examples/document.zsh examples/canvas.zsh benchmarks/canvas.zsh; do \
	  "$(ZSH_BIN)" -dfn "$$file" || exit; \
	done
	"$(ZSH_BIN)" -dfn tests/presentation.zsh
	"$(ZSH_BIN)" -dfn tests/prepared.zsh
	"$(ZSH_BIN)" -dfn tests/clipping.zsh
	"$(ZSH_BIN)" -dfn benchmarks/spans.zsh
	"$(ZSH_BIN)" -dfn benchmarks/fill.zsh
	"$(ZSH_BIN)" -dfn examples/events.zsh
	"$(ZSH_BIN)" -dfn examples/streams.zsh
	"$(ZSH_BIN)" -dfn examples/hit-test.zsh
	"$(ZSH_BIN)" -dfn examples/wrapping.zsh
	"$(ZSH_BIN)" -dfn examples/borders.zsh
	"$(ZSH_BIN)" -dfn examples/colors.zsh
	"$(ZSH_BIN)" -dfn examples/cell-inspection.zsh
	"$(ZSH_BIN)" -dfn examples/snapshot-diff.zsh
	"$(ZSH_BIN)" -dfn examples/regions.zsh
	"$(ZSH_BIN)" -dfn examples/copy.zsh
	"$(ZSH_BIN)" -dfn examples/restyle.zsh
	"$(ZSH_BIN)" -dfn examples/viewports.zsh
	"$(ZSH_BIN)" -dfn examples/windows.zsh
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
