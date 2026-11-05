.DEFAULT_GOAL := help
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

SBCL ?= sbcl
SBCL_FLAGS ?= --noinform --non-interactive
RUNNER ?=
RUN_ARGS ?=
PYTHON ?= python3
JSCL ?= $(HOME)/clone/jscl
PORT ?= 8000
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
SOURCES := $(wildcard src/*.lisp) lui.asd scripts/setup.lisp scripts/build.lisp
SUFFIX := $(if $(filter win32,$(PLATFORM)),.exe,)
DEMO := build/bin/demo-$(PLATFORM)$(SUFFIX)
SHOWCASE := build/bin/showcase-$(PLATFORM)$(SUFFIX)

.PHONY: help check-platform build demo example showcase test test-platform \
	test-core test-native test-executables web-build
help:
	@echo 'make demo | example       Build and run the shared demo executable'
	@echo 'make showcase             Build and run the showcase executable'
	@echo 'make build                Save both executables in build/bin/'
	@echo 'make test                 Test platform; progress/results in build/logs/'
	@echo 'make web-build            Build JSCL browser demo and showcase'
	@echo 'PLATFORM=terminal|x11|wayland|win32|cocoa|web (auto-detected by default)'
	@echo 'Test-only platforms: core native gl. Options: SBCL, SBCL_FLAGS, JSCL, PYTHON'

check-platform:
	@case ' $(TEST_PLATFORMS) ' in *' $(PLATFORM) '*) ;; \
	  *) echo 'Unknown PLATFORM=$(PLATFORM)' >&2; exit 2;; esac

ifeq ($(PLATFORM),web)
build: web-build
demo example: web-build
	PORT=$(PORT) LUI_EXAMPLE=demo node scripts/serve-web.mjs
showcase: web-build
	PORT=$(PORT) LUI_EXAMPLE=showcase node scripts/serve-web.mjs
else
build: $(DEMO) $(SHOWCASE)
demo example: $(DEMO)
	$(RUNNER) "$(DEMO)" $(RUN_ARGS)
showcase: $(SHOWCASE)
	$(RUNNER) "$(SHOWCASE)" $(RUN_ARGS)
endif

$(DEMO): $(SOURCES) examples/demo.lisp | check-platform
	@mkdir -p build/bin
	LUI_EXAMPLE=demo LUI_OUTPUT="$@" $(SBCL) $(SBCL_FLAGS) --load scripts/build.lisp

$(SHOWCASE): $(SOURCES) examples/showcase.lisp | check-platform
	@mkdir -p build/bin
	LUI_EXAMPLE=showcase LUI_OUTPUT="$@" $(SBCL) $(SBCL_FLAGS) --load scripts/build.lisp

web-build:
	@mkdir -p build
	node "$(JSCL)/dist/jscl-node.js" scripts/build-web.lisp
	cp "$(JSCL)/dist/jscl.js" build/jscl.js

test: check-platform
	@mkdir -p build/logs
	@log="build/logs/$(PLATFORM)-$$(date +%Y%m%d-%H%M%S)-$$$$.log"; \
	{ echo "START platform=$(PLATFORM) log=$$log"; \
	  if $(MAKE) --no-print-directory test-platform; then \
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
	$(RUNNER) "$(SHOWCASE)" --smoke-test
	@echo '[saved executables] PASS'
