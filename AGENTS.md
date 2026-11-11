# Working on LUI

This file preserves development guidance and maintenance context independently
of the human-facing README. Consult the code and current test results for exact
APIs and platform support; historical measurements are not current guarantees.

## Project constraints and conventions

- Keep `src/` below 10,200 physical lines. Examples, tests, and generated output
  are outside that budget. Prefer simplicity over artificial compression; flag
  any tradeoff that would reduce lines by making the implementation harder to
  understand. `make loc` reports cloc counts; also check physical line totals.
  The user approved exceeding this cap for the ECL/Emscripten web backend.
- This is a work-in-progress API. When replacing an API, remove the retired form
  and migrate its in-tree callers and documentation. Do not retain compatibility
  shims for obsolete APIs.
- Use structures with typed slots and `lui.fn:fn` with explicit return types for
  implementation functions. Do not reintroduce `destruct*` or an alternate
  structure API; use standard `defstruct`.
- Collection APIs use vectors with declared element types: wrapped strings,
  events, layout children, contours, and colors. Configuration plists, control
  alists, Lisp forms, and internal pending-event queues can remain lists.
- Prefer one package per source file. Implementation packages may use `:use`.
  Demos and examples must use only Common Lisp in `:use`; qualify their LUI API
  references. Keep local variables and structure slot names ordinary local
  symbols. Qualify or explicitly import other external API symbols.
- Side-effect-only functions declare `(values)` and end with `(values)`,
  including early function exits; reserve `null` for an actual NIL result.
- Declare public API symbols in `lui`'s `defpackage`; implementation packages
  import them explicitly. Do not mutate exports through private macros.
- Normally wrap Lisp code at 78 columns; use keyword LOOP clauses.
- Lint with `mallet src --strict --disable no-package-use --disable
  error-without-custom-condition` (one shell command). Those disabled rules
  conflict with the internal-package `:use` and structure-based conventions.
- Do not add dependencies as part of simplification work without discussing
  the dependency tradeoff with the user.

## Finishing updates

Work on the current branch by default. Do not create a new branch unless the
user explicitly asks for one.

After completing an update, run `make docs-pages` and commit any resulting
changes to `docs/index.html` along with the update. Commit as work is completed
and push finished updates, as requested by the user. Run checks appropriate to
the change and report material limitations instead of claiming untested support.

## Source organization

- Keep portable source files numbered in dependency order (`01-fn.lisp`
  through `09-debug.lisp`). The debugger remains an optional ASDF system.
- Keep each platform in `backend-<platform>.lisp`; share rendering and font
  support in `backend-common.lisp`, OpenGL in `backend-common-gl.lisp`, and
  browser rendering/input in `backend-common-web.lisp`.
- ECL Lisp interop belongs in `backend-ecl-emscripten.lisp`; C/JavaScript
  build support belongs in `scripts/ecl-web.c` and `scripts/ecl-web.js`.
  Update ASDF, both browser build manifests, and the portable test runner
  when moving code.

## Architecture and contracts

- LUI is an immediate-mode Common Lisp UI library. Applications own their model
  state; `lui:run` owns the backend lifecycle. The same gallery and widget logic
  run on native windows, the browser, and the terminal. Avoid demo-only fixes
  for behavior that should apply to all applications.
- `lui/core` is dependency-free. All terminal output, including plain snapshots,
  belongs to `lui/terminal` and requires Plisp/uncursed. Uncursed owns cell storage,
  Unicode widths, ANSI styles, and incremental screen updates; LUI owns layout,
  widget presentation, input translation, and lifecycle. Snapshots are escape-free.
- Native backends use LUI's own Xlib/GLX, libwayland/EGL, Win32/GDI+, and Cocoa
  bindings. X11 shares one display connection for windowing and direct GL
  rendering. The CLX/Wayflan/FTW migration experiments were reverted; uncursed
  was retained. There is no application software pixel renderer.
- Toolkits must remain independently definable. Rendering and geometry are
  registered toolkit callbacks, not hard-coded toolkit cases in backends or
  generic drawing dispatch. Built-ins may reuse shared painting primitives.
- Shared toolkit geometry governs measurement, text painting, caret placement,
  and selection. Keep those paths consistent, including padding and pressed
  offsets. A widget's own painter takes precedence over its toolkit painter.
- Palettes are independent of geometry. Each widget captures its resolved
  palette; explicit widget color options take precedence over defaults. Do not
  override a requested background inside the painter (the macOS white-surface
  shortcut previously made white Styles labels invisible). Dynamic palette
  providers and changes within a frame must keep working.
- Demo and docs start in Qt, with independent toolkit and palette switching.
  macOS styling is Ventura-inspired, not the retired classic double-outline
  appearance. The presets are Default, Light, Dark, Ocean, and Forest.
- Terminal border characters are toolkit settings, independent of graphical
  corner radius: top-left, top-right, bottom-left, bottom-right, horizontal,
  vertical. Preserve Unicode borders. Restore terminal attributes, mouse modes,
  cursor visibility, and the alternate screen on normal exit and Lisp errors;
  retain the line-input fallback for redirected/non-TTY input.

### Frame and layout contract

- `with-frame` executes the application body once and returns its solved root.
  Input is routed against the previous completed layout. IDs use `equal`:
  keep them stable and do not mutate compound IDs after declaration. Duplicate
  non-NIL IDs are errors.
- Resize invalidates old pointer geometry. Removed widgets lose focus/capture;
  an aborted frame invalidates geometry. Layout structures are frame-local and
  should not be mutated after completion.
- Measurement receives `(widget available-content-width)` and returns width
  and height. NIL width requests intrinsic measurement. Dimensions must be
  nonnegative; measured leaves cannot have children.
- Horizontal sizing precedes width-dependent measurement and vertical layout.
  Percentages exclude padding and inter-child gaps. Fixed sizes and minimum
  bounds may overflow rather than silently shrink.
- Value widgets return the new value and a changed flag. Preserve release
  activation, pointer capture, disabled behavior, and keyboard-only focus rings.
- `cell` is selectable text; general tables use `table`, `table-row`, and
  `table-cell` for arbitrary contents. Columns share widths across rows; column
  spanning is supported, row spanning is not.
- Searchable comboboxes accept arbitrary strings and show autocomplete choices
  in overlays without reshuffling layout. Date pickers are date-only, open from
  the whole field, accept MM/DD/YYYY, and return YYYY-MM-DD or NIL.
- The debugger reads the previous completed frame and is excluded from its own
  tree. Closing it should stop tree collection and formatting.

### Browser behavior and performance

- The browser uses JSCL or ECL/Emscripten and one high-DPI Canvas 2D surface per window, with
  read-only native HTML labels for selection/accessibility. Preserve native
  text selection, normal browser context menus, and accessible control actions.
  Occluded labels may be painted on canvas; a shared textarea handles editing,
  composition, and clipboard events.
- Toolkit `:paint`, `:geometry`, and `:native-labels` policies inherit. Overriding
  paint or geometry defaults to canvas labels unless native-label support is
  explicitly declared. Do not assume arbitrary custom painters support overlays.
- Touch-first standalone apps without an explicit height default to page
  scrolling. `lui:mount` shares that behavior. `:scroll-mode :viewport`
  selects a bounded embedded view; `:page` expands on any device. Paint the next
  canvas viewport before moving the page to avoid blank areas during scrolling.
- Preserve DOM label reuse and avoid needless style/layout work. Profile before
  optimizing; do not sacrifice selection or accessibility to improve FPS.
- JSCL's general LOOP expansions can use expensive exception-based jumps.
  Indexed `dotimes` loops and direct traversal are useful in measured hot paths.
  Fixed polygon vectors use `typed-vector` to avoid expensive generic
  `make-array :initial-contents` traversal while retaining element types.
- The JSCL-only standard `defstruct` expansion override in `src/01-fn.lisp` omits
  generated constructor/writer slot checks but retains slot metadata and
  initializer checks. Native Lisp builds use their standard `defstruct`.

## Build and validation workflow

Run commands from the repository root. GNU Make, Bash, and SBCL drive the
launchers; Python 3 drives integration tests. `PYTHON`, `SBCL`, and `SBCL_FLAGS`
are configurable. `cloc` is needed for source reports and aggregate test and
benchmark targets. Scripts discover optional dependency checkouts under
`build/deps/`; direct ASDF callers must register dependencies themselves.

| Task | Command / notes |
| --- | --- |
| Core and native drawing | `make test-core test-native` |
| Portable source runner | `sbcl --script tests/run.lisp`, `clisp -q -q tests/run.lisp`, `ecl -shell tests/run.lisp` |
| JSCL source runner | `node /path/to/jscl/dist/jscl-node.js tests/run.lisp` |
| Browser build / serve | `make web-build` / `make web-demo`; `JSCL` defaults to `~/clone/jscl`, `PORT` to 8000 |
| ECL browser | `make web-ecl-build` / `make web-ecl-demo`; see README for the matching non-threaded host ECL and wasm toolchain |
| Browser tests | `make test PLATFORM=web` or, after building, `python3 tests/web.py`; requires Playwright and Chromium |
| Docs | `make docs-pages`; `make test-docs` checks extraction, examples, and offline browser behavior |
| Native executable | `make demo PLATFORM=x11` (or another backend); `RUN_ARGS=--smoke-test` renders one frame and exits |
| Terminal | `make test PLATFORM=terminal`; `python3 tests/terminal.py --lisp sbcl` runs POSIX PTY checks |
| Terminal parity | `make test-terminal-parity`; requires historical commit `16f79dd`, compares reconstructed styled cells and I/O against current layout/widgets/examples |
| X11 | `python3 tests/x11.py`; needs a real X display, SBCL, Pillow, and backend libraries |
| Cocoa runtime | `make test-macos` on macOS |
| PDF | `make pdf` generates and opens the document; `make build/pdf-demo.pdf` only generates; `(asdf:test-system "lui/pdf")` tests the backend |

`PLATFORM` defaults to Win32 on Windows, Cocoa on macOS, otherwise Wayland when
`WAYLAND_DISPLAY` is set, X11 when `DISPLAY` is set, then terminal. It does not
start a display server. `core`, `native`, and `gl` are non-windowed test targets.
`make test` also tests saved native executables: source loading alone cannot
detect stale foreign pointers. `RUNNER` can prefix launches (e.g. Wine); Make
does not install a Windows Lisp, Wine, or dependencies. PTY/X11 harnesses launch
installed SBCL themselves rather than honoring a custom `SBCL` command prefix.

The docs reference is generated from signatures/docstrings and an explicit
public-symbol allowlist in `scripts/docs-data.lisp`. Internal exports used
between modules are not automatically public documentation. Reexports belong
under their application-facing package. `build/docs.html` uses ECL/Emscripten
and embeds the WebAssembly runtime and app for offline use; `docs/index.html` is its committed Pages copy.

### Dependencies and platform limits

- Native measurement/painting requires CFFI, zpb-ttf, and an available TrueType
  font. Set font configuration before opening a window. Saved executables accept
  `LUI_FONT` and `LUI_FONT_DIR`; font faces are cached and closed with the base
  font. Browser measurement and painting must use matching family/weight.
- Uncursed requires CFFI grovel and a C compiler; Unix terminal support uses
  terminfo. Recorded tested revision: `89f9cb6f21bc7e981a04ce0d6361ae73dde49c4f`.
- X11 needs Xlib and GLX/OpenGL; Wayland needs libwayland, xkbcommon, EGL/OpenGL,
  and a compositor. Win32 uses User32/GDI32/Kernel32/GDI+. Cocoa is SBCL-only
  and requires AppKit/Objective-C. PDF uses cl-pdf and native font outlines;
  exported text is vector outlines, not selectable/searchable text.
- Native IME/clipboard coverage, Wayland text-input support, shaping, and full
  terminal grapheme handling remain incomplete. Do not infer support from a
  successful build. A browser long-press check can skip when the engine also
  fails to select an ordinary HTML paragraph; report that limitation.

### Cocoa auto-hide crash safeguard

Do not remove the temporary empty-stacktrace guard as cosmetic compatibility
code. The user confirmed that without it the application crashes at startup
when macOS menu-bar auto-hide is enabled. The reported failure reaches
`HIPrintBacktrace` / `MenuBarInstance::IsAutoShowHideAllowed` and raises an
empty-array `NSRangeException`.

The guard substitutes one diagnostic entry only for an empty
`NSThread.callStackSymbols` result, preserves real traces, and restores the
original method on exit. It must not change the user's system preferences.
Cocoa also masks floating-point traps at native initialization, event handling,
cleanup, and callback boundaries, restoring the caller's full settings on exit.
Relevant upstream reports: https://github.com/MakieOrg/Makie.jl/issues/2629 and
https://github.com/python/cpython/issues/101067.

`tests/cocoa.lisp` checks ABI, UTF-8, event routing, callback safety, FP state,
and isolated null/empty/nonempty stacktrace behavior. On Linux it compiles a
test-only Objective-C ABI double with `cc` (`CC` overrides it); that fixture must
never be linked into applications or loaded into an AppKit test process.
Passing Linux ABI tests or saving an executable does not establish macOS runtime
success. Use the real macOS smoke test and retain its OS/Lisp-version log.
Cocoa uses a double-buffered OpenGL view and the shared GL renderer, requesting
a zero swap interval. If an accelerated pixel format is unavailable, it warns
and falls back to AppKit drawing; test the actual path rather than assuming GL.

## Performance evidence

- Use matching toolkit/page, viewport, sample count, warmup, and pacing settings.
  Historical README timings were machine-specific and often used older backends;
  they are not targets or evidence about the current checkout.
- `make benchmark PLATFORM=...` writes timestamped logs under `build/logs/`.
  Native/core use `BENCH_CASE` (e.g. `garnet/seven/cells`); web uses
  `BENCH_TOOLKITS` and `BENCH_PAGES`. `BENCH_WIDTH`, `BENCH_HEIGHT`, `BENCH_FRAMES`,
  and `WARMUP` make workloads reproducible. The web default has 60 cases across
  five toolkits; 1200 measured and 240 warmup frames give 20 samples per case.
- Web timings measure active redraw work plus a browser layout flush, excluding
  GPU rasterization; idle animation ticks are not rendering FPS. Use
  `7GUIs/Cells-scroll` to verify actual wheel movement. `BENCH_DETAIL=1` adds
  phase timings, `BENCH_OUTPUT=path.json` saves results. Frame/layout/measurement
  timings are nested and overlap; do not sum them as independent costs.
- Native window results include event processing, presentation, and pacing.
  Offscreen GL uses `glFinish`; core uses deterministic metrics; terminal uses
  snapshot output. Do not compare these as equivalent display FPS. The gallery's
  frame interval also includes idle/pacing time.
- SBCL allocation counters are process-wide; GC CPU time is not a wall-clock
  pause. Unrelated threads can contribute. Foreign/GPU allocations are excluded;
  exact per-frame GC counts are unsupported. Unsupported implementations should
  report that fact, not zero. Browser retained-heap deltas are not allocations.
- Interactive runners default to 1 idle FPS and 240 maximum active FPS; input
  wakes rendering and animation deadlines schedule work. Confirm benchmark
  settings instead of attributing a pacing limit to rendering cost.
