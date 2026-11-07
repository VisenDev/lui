.DEFAULT_GOAL := help
.DELETE_ON_ERROR:
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

SBCL ?= sbcl
SBCL_FLAGS ?= --noinform --non-interactive
RUNNER ?=
RUN_ARGS ?=
PYTHON ?= python3
JSCL ?= $(HOME)/clone/jscl
PORT ?= 8000
BENCH_FRAMES ?= 240
WARMUP ?= 30
export BENCH_FRAMES WARMUP
PLATFORM ?= $(shell if [ "$(OS)" = Windows_NT ]; then echo win32; \
	elif [ "$$(uname -s)" = Darwin ]; then echo cocoa; \
	elif [ -n "$$WAYLAND_DISPLAY" ]; then echo wayland; \
	elif [ -n "$$DISPLAY" ]; then echo x11; else echo terminal; fi)
export PLATFORM
# Separate cached objects from other development sessions and CFFI versions.
ASDF_OUTPUT_TRANSLATIONS ?= (:output-translations (t ("$(CURDIR)/build/cache/" :implementation)) :ignore-inherited-configuration)
export ASDF_OUTPUT_TRANSLATIONS

NATIVE_PLATFORMS := terminal x11 wayland win32 cocoa
TEST_PLATFORMS := $(NATIVE_PLATFORMS) web core native gl
SOURCES := $(wildcard src/*.lisp examples/*.lisp) lui.asd \
	scripts/setup.lisp scripts/build.lisp
SUFFIX := $(if $(filter win32,$(PLATFORM)),.exe,)
DEMO := build/bin/demo-$(PLATFORM)$(SUFFIX)

DOC_SOURCES := $(wildcard src/*.lisp) examples/docs.lisp lui.asd
DOC_DATA := build/docs-data.lisp
DOC_BIN := build/bin/docs-$(PLATFORM)$(SUFFIX)

.PHONY: docs docs-html docs-pages test-docs test-terminal-parity help check-platform build demo pdf pdf-demo test test-platform \
	test-core test-native test-macos test-executables web-build web-demo terminal-demo loc benchmark benchmark-platform
help:
	@echo 'make docs                 Build and open the native documentation browser'
	@echo 'make docs-html            Build standalone build/docs.html with JSCL'
	@echo 'make docs-pages           Refresh docs/index.html from the standalone page'
	@echo 'make demo                 Build and run the tabbed demo executable'
	@echo 'make build                Save the demo executable in build/bin/'
	@echo 'make pdf                  Build and open build/pdf-demo.pdf'
	@echo 'make test                 Test platform; progress/results in build/logs/'
	@echo 'make test-terminal-parity Compare uncursed terminal cells/styles against the old backend (SBCL)'
	@echo 'make test-macos           Run Cocoa checks and saved executable smoke'
	@echo 'make benchmark            Measure throughput and frame times'
	@echo 'make loc                  Report source line counts with cloc'
	@echo 'make web-demo             Build and serve the browser demo at /'
	@echo 'make terminal-demo        Build and run the terminal demo'
	@echo 'make web-build            Build the JSCL browser demo'
	@echo 'PLATFORM=terminal|x11|wayland|win32|cocoa|web (auto-detected by default)'
	@echo 'Test-only platforms: core native gl. Options: SBCL, SBCL_FLAGS, JSCL, PYTHON'

check-platform:
	@case ' $(TEST_PLATFORMS) ' in *' $(PLATFORM) '*) ;; \
	  *) echo 'Unknown PLATFORM=$(PLATFORM)' >&2; exit 2;; esac

ifeq ($(PLATFORM),web)
build: web-build
demo: web-demo
else
build: $(DEMO)
demo: $(DEMO)
	$(RUNNER) "$(DEMO)" $(RUN_ARGS)
endif

pdf pdf-demo: build/pdf-demo.pdf
ifeq ($(OS),Windows_NT)
	MSYS2_ARG_CONV_EXCL='*' cmd.exe /d /c start "" "build\pdf-demo.pdf"
else ifeq ($(shell uname -s),Darwin)
	open "$<"
else
	xdg-open "$<"
endif

build/pdf-demo.pdf: examples/pdf-demo.lisp scripts/setup.lisp lui.asd $(wildcard src/*.lisp)
	@mkdir -p build
	$(SBCL) $(SBCL_FLAGS) --load examples/pdf-demo.lisp

$(DEMO): $(SOURCES) | check-platform
	@mkdir -p build/bin
	LUI_OUTPUT="$@" $(SBCL) $(SBCL_FLAGS) --load scripts/build.lisp

docs: $(DOC_BIN)
	$(RUNNER) "$(DOC_BIN)" $(RUN_ARGS)

test-docs: build/docs.html
	LUI_DOCS_LIBRARY_ONLY=1 $(SBCL) $(SBCL_FLAGS) --load scripts/setup.lisp \
		--load scripts/docs-data.lisp --load tests/docs-data.lisp \
		--eval '(lui.tests.docs-data:run-tests)' \
		--eval '(asdf:load-system "lui/debug")' \
		--load examples/docs.lisp --load tests/docs.lisp \
		--eval '(lui.tests.docs:run-tests)'
	$(PYTHON) -u tests/docs-web.py

docs-html: build/docs.html

docs-pages: build/docs.html
	@mkdir -p docs
	@cmp -s "$<" docs/index.html || cp "$<" docs/index.html

$(DOC_DATA): scripts/docs-data.lisp scripts/setup.lisp $(DOC_SOURCES)
	@mkdir -p build
	$(SBCL) $(SBCL_FLAGS) --load scripts/setup.lisp --load scripts/docs-data.lisp

build/jscl.js: $(JSCL)/dist/jscl.js
	@mkdir -p build
	cp "$<" "$@"

build/docs.html: $(DOC_DATA) $(DOC_SOURCES) scripts/build-docs-web.lisp \
		build/jscl.js $(JSCL)/dist/jscl-node.js
	node "$(JSCL)/dist/jscl-node.js" scripts/build-docs-web.lisp

$(DOC_BIN): $(DOC_DATA) $(DOC_SOURCES) scripts/build-docs.lisp
	@mkdir -p build/bin
	LUI_OUTPUT="$@" $(SBCL) $(SBCL_FLAGS) --load scripts/build-docs.lisp

test-macos:
	$(MAKE) --no-print-directory test PLATFORM=cocoa

terminal-demo:
	$(MAKE) --no-print-directory demo PLATFORM=terminal

web-build: build/jscl.js
	@mkdir -p build
	node "$(JSCL)/dist/jscl-node.js" scripts/build-web.lisp
	sed 's#../build/##g' examples/web.html > build/index.html

web-demo: web-build
	@echo 'Open http://localhost:$(PORT)/'
	$(PYTHON) -m http.server $(PORT) --bind 127.0.0.1 --directory build

test benchmark: check-platform
	@mkdir -p build/logs
	@log="build/logs/$@-$(PLATFORM)-$$(date +%Y%m%d-%H%M%S)-$$$$.log"; \
	{ echo "START $@ platform=$(PLATFORM) log=$$log"; \
	  $(MAKE) --no-print-directory loc; \
	  if $(MAKE) --no-print-directory $@-platform; then \
	    echo 'RESULT PASS platform=$(PLATFORM)'; \
	  else status=$$?; echo "RESULT FAIL platform=$(PLATFORM) exit=$$status"; \
	    exit "$$status"; fi; } 2>&1 | tee "$$log"

test-core:
	@echo '[core] RUN'
	LUI_TEST=core $(SBCL) $(SBCL_FLAGS) --load scripts/test.lisp
	@echo '[core] PASS'

test-native:
	@echo '[native] RUN'
	LUI_TEST=native $(SBCL) $(SBCL_FLAGS) --load scripts/test.lisp
	@echo '[native] PASS'

test-terminal-parity:
	$(PYTHON) -u tests/terminal-parity.py

test-platform: check-platform
ifeq ($(PLATFORM),web)
	@echo '[JSCL core] RUN'
	node "$(JSCL)/dist/jscl-node.js" tests/run.lisp
	@echo '[JSCL core] PASS'
	$(MAKE) --no-print-directory web-build
	@echo '[browser] RUN'
	$(PYTHON) -u tests/web.py
	@echo '[browser] PASS'
else
	$(MAKE) --no-print-directory test-core
ifneq ($(filter $(PLATFORM),x11 wayland win32 cocoa gl native),)
	$(MAKE) --no-print-directory test-native
endif
ifeq ($(PLATFORM),terminal)
ifeq ($(OS),Windows_NT)
	@echo '[terminal PTY] SKIP: POSIX-only; portable core tested'
else
	@echo '[terminal PTY] RUN (installed SBCL)'
	$(PYTHON) -u tests/terminal.py --lisp sbcl
	@echo '[terminal PTY] PASS'
endif
else ifeq ($(PLATFORM),x11)
	@echo '[X11 windows] RUN (installed SBCL)'
	$(PYTHON) -u tests/x11.py
	@echo '[X11 windows] PASS'
else ifneq ($(filter $(PLATFORM),wayland win32 cocoa gl),)
	@echo '[$(PLATFORM)] RUN'
	LUI_TEST=$(PLATFORM) $(SBCL) $(SBCL_FLAGS) --load scripts/test.lisp
	@echo '[$(PLATFORM)] PASS'
endif
ifneq ($(filter $(PLATFORM),$(NATIVE_PLATFORMS)),)
ifeq ($(PLATFORM)-$(shell uname -s),cocoa-Linux)
	@echo '[saved executables] SKIP: AppKit requires macOS'
else
	$(MAKE) --no-print-directory test-executables
endif
endif
endif

# Test restored executables too: source-loading cannot catch stale C pointers.
test-executables: build
	@echo '[saved executables] RUN'
	$(RUNNER) "$(DEMO)" --smoke-test
	@echo '[saved executables] PASS'

loc:
	@mkdir -p build/logs
	cloc src --by-file --report-file=build/logs/src-loc.txt
	@cat build/logs/src-loc.txt

benchmark-platform: check-platform
ifeq ($(PLATFORM),web)
	$(MAKE) --no-print-directory web-build
	$(PYTHON) -u tests/benchmark-web.py
else
	$(SBCL) $(SBCL_FLAGS) --load scripts/benchmark.lisp
endif
