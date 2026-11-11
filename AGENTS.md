# Working on LUI

This file is the project guidance and maintenance reference. Consult the code
and current test results for exact APIs and platform support; historical
measurements are not current guarantees.

**Do not edit `README.md`. It is intentionally empty.** Keep project guidance
in `AGENTS.md` and application documentation in docstrings and
`examples/docs.lisp`; regenerate `docs/index.html` through the docs build.

## Project constraints and conventions

- Keep `src/` below 10,200 physical lines. Examples, tests, and generated output
  are outside that budget. Prefer simplicity over artificial compression; flag
  any tradeoff that would reduce lines by making the implementation harder to
  understand. `make loc` reports cloc counts; also check physical line totals.
  The user approved exceeding this cap for the ECL/Emscripten web backend.
- This is a work-in-progress API. When replacing an API, remove the retired form
  and migrate its in-tree callers and documentation. Do not retain compatibility
  shims for obsolete APIs.
- Annotate FN parameters explicitly; use OR unions for nullable or multi-type
  inputs. Use `object-id` for widget identities; it intentionally expands to T.
- Use structures with typed slots and `lui.fn:fn` with explicit return types for
  implementation functions. Do not reintroduce `destruct*` or an alternate
  structure API; use standard `defstruct`.
- Use precise vector element types in declarations and constructors. Keep T
  only for genuinely heterogeneous contents, such as unrestricted widget IDs.
- Collection APIs use vectors with declared element types: wrapped strings,
  events, layout children, contours, and colors. Configuration plists, control
  alists, Lisp forms, and internal pending-event queues can remain lists.
- Use one package per core source file; backend files may group related
  packages. Implementation packages may use `:use`.
  Demos and examples must use only Common Lisp in `:use`; qualify their LUI API
  references. Keep local variables and structure slot names ordinary local
  symbols. Qualify or explicitly import other external API symbols.
- Side-effect-only functions declare `(values)` and end with `(values)`,
  including early function exits; reserve `null` for an actual NIL result.
- Declare public API symbols in `lui`'s `defpackage`; implementation packages
  import them explicitly. Do not mutate exports through private macros.
- Access other LUI packages through exported symbols; declare shared internals
  in their owning package exports instead of using double-colon references.
- Normally wrap Lisp code at 78 columns; use keyword LOOP clauses.
- Run `make lint` to normalize FN declarations and check strict Mallet rules,
  complexity, function length, and missing docstrings. Only `no-package-use`
  is disabled. Keep the defaults for all other rule thresholds.
- Use documented custom conditions for explicit LUI failures. Conditions use
  standard `define-condition`; ordinary application data still uses structures.
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
  through `14-debug.lisp`). The debugger remains an optional ASDF system.
- Each core file owns one matching package. Ignore numeric prefixes and map
  package dots to filename hyphens. Tests use `lui.tests.` and gallery packages
  use `lui.example.`; script packages also follow their filenames.
- Backend files may group related packages. Keep each platform in
  `backend-<platform>.lisp`; share font/drawing support in `backend-common.lisp`,
  OpenGL in `backend-common-gl.lisp`, and browser rendering/input in
  `backend-common-web.lisp`.
- Built-in graphical painters and registrations belong in `paint-<toolkit>.lisp`
  (`lui.paint-<toolkit>`), loaded after the shared renderer. Keep toolkit names
  out of backend dispatch; backdrop effects are shared rendering capabilities.
- ECL Lisp interop belongs in `backend-ecl-emscripten.lisp`; C/JavaScript
  build support belongs in `scripts/ecl-web.c` and `scripts/ecl-web.js`.
  Update ASDF, both browser build manifests, and the portable test runner
  when moving code.

## Architecture and contracts

- LUI is an immediate-mode Common Lisp UI library. Applications own their model
  state; value controls retain local state unless OPT :value is supplied.
  `lui:run` owns the backend lifecycle. The same gallery and widget logic
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
- Widgets accept `:position :automatic` or `(lui:make-point :x x :y y)` in
  logical client-surface coordinates. Explicit positions remain fixed under
  ancestor scrolling but obey ancestor clips. `lui:parent-scroll-position`
  returns the current parent's retained offsets for explicit compensation.
- `:reserve-space-p` defaults to T, independently of position. Absolute
  rectangles displace automatic direct siblings forward along their row or
  column; there is no wrapping/backtracking. Fixed/grow bounds may overflow.
  NIL excludes a child from flow sizing and reservation. Table tracks retain
  shared widths; put manually positioned widgets inside cells.
- Horizontal sizing precedes width-dependent measurement and vertical layout.
  Percentages exclude padding and inter-child gaps. Fixed sizes and minimum
  bounds may overflow rather than silently shrink.
- Control macros use quoted call-site IDs, combined with WITH-KEY scopes and
  OPT :id instance keys (including numbers). OPT :default-value initializes
  owned values once; absent widgets lose owned state after a completed frame.
  Value widgets return the new value, a changed flag, and resolved ID.
  Preserve release
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
| ECL browser | `make web-ecl-build` / `make web-ecl-demo`; see ECL/WebAssembly setup below for the matching host and wasm toolchain |
| Browser tests | `make test PLATFORM=web` or, after building, `python3 tests/web.py`; requires Playwright and Chromium |
| Docs | `make docs-pages`; `make test-docs` checks extraction, examples, and offline browser behavior |
| Manual-only demo | `make manual-demo` (or `PLATFORM=x11`, `terminal`, etc.); all widgets use explicit positions and no reservations; heights fit measured content |
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
- Use uncursed 0.7.0 or later; Quicklisp 0.3.0 is too old. Its source is
  https://github.com/Plisp/uncursed. It requires CFFI grovel and a C compiler;
  Unix terminal support uses
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
  Historical timings were machine-specific and often used older backends;
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

## Application API maintenance notes

- Load `lui` for host backends, `lui/core` for dependency-free use, and
  `lui/demo` for the gallery. Optional systems include `lui/debug`, `lui/native`,
  `lui/terminal`, `lui/pdf`, `lui/gl`, `lui/x11`, `lui/wayland`, `lui/win32`, and
  `lui/cocoa`. `lui:available-backends` lists loaded backends; `lui:run :backend`
  chooses one. Width/height use backend coordinates; omission uses defaults.
- Public application APIs use `lui:`; optional systems supply their functions
  when loaded. Control macros cannot be passed to FUNCALL/APPLY. Toolkit
  overrides remain functions receiving resolved IDs, positional arguments, and
  an options list. `lui:control` invokes a registered custom control.
- Each control call site has a stable ID. Instance keys are combined with that
  site, so different control sites may share a key. Use stable item keys rather
  than indices when rows can move. Repeated unkeyed sites or duplicate instance
  keys signal `configuration-error` before state is reused. Recompiling a call
  site creates a new identity. IDs are scoped to a context and may be any object.
- `widget-id` resolves a unique key in the current key scope; ambiguous keys
  signal `configuration-error`. `widget-key` extracts the declared key;
  `focus-widget` requests focus; `reset-editor` resets owned text and caret.
  Use the third returned control value when a resolved ID is needed.
- `with-key`, `with-toolkit`, `with-palette`, and `with-frame` are thin macros
  over `call-with-` functions. The first three functions take the scope value
  and a zero-argument function and preserve its return values.
  `(lui:call-with-frame context width height draw :events events)` calls DRAW
  once and returns the solved root. Preserve cleanup on errors/nonlocal exits.
- Buttons return activation. Value controls return value, changed flag, and ID.
  `:default-value` initializes owned state once; `:value` supplies an external
  model each frame. Radio controls take their own choice and a shared `:value`.
  Button clicks preserve keyboard focus; fields acquire editing focus on click.
  Tab groups wrap Left/Right, support Home/End, and skip disabled tabs.
- Combobox Up/Down selects suggestions; Enter accepts a highlighted suggestion.
  Enter without a highlight, Escape, and Tab preserve typed text. Suggestions
  are overlays; `:max-results` bounds their count.
- Table columns use the widest content across rows. Extra width is shared;
  narrow tables shrink columns proportionally before row-height measurement.
  Short rows may omit trailing cells. `:column-gap` belongs to the table and
  `:column-span` to a cell; table option forms may be expressions or stored lists.
- `:password-p t` masks built-in painting, copied selections, accessibility,
  and debugger values with one asterisk per character. Storage is not encrypted;
  custom painters still receive the original value.
- Custom toolkits use `register-toolkit` with optional parent, defaults, controls,
  paint, geometry, and native-label policy. Geometry callbacks return text
  insets, minimum size, alignment, and pressed displacement. `text-box` exposes
  the same text area to custom painters. `shape`, `outline`, and `paint-text`
  use the active renderer. `renderer-backdrop-effect` is an optional callback
  taking bounds, corner radius, and blur radius; paint the tint afterward.
- Palette presets are returned by `available-palettes` as a vector. `with-palette`
  accepts preset names/constants or `make-palette` instances, not raw plists.
  Palette slots are read-only; NIL slots inherit. Toolkit defaults contain a
  palette plist, and `widget-color` resolves its roles. Keep disabled, selection,
  on-accent, border, light/shadow, track, bevel, and cell colors consistent.
- `:terminal-label` is a widget-to-string callback. `:terminal-border` is a
  six-character string; Glass uses "╭╮╰╯─│", other built-ins use "++++-|".
  Terminal button delimiters follow widget radius. Backdrop rendering differs:
  Canvas uses clipped blur; GL adds approximate edge refraction; Win32 uses
  filtered blur without refraction; Cocoa's AppKit fallback uses tint only.
- The gallery covers Controls, Editing, Layout, Scroll, Styles, and all 7GUIs.
  Its A0:Z99 sheet uses a safe formula parser and incremental dependencies.
  FPS includes pacing; layout time is a 30-frame rolling average including
  measurement but excluding construction, painting, presentation, and pacing.
  `1000 / layout-ms` is only a layout throughput ceiling.

### Editing and debugger behavior

Readline-style editing is shared across backends: Ctrl-A/E moves to line ends,
Ctrl-B/F by character, Alt-B/F or Ctrl-Left/Right by word, Ctrl-D/H deletes,
Ctrl-K/U kills to line end/start, Ctrl-W or Alt-D kills a word, Ctrl-Y yanks,
and Ctrl-T transposes. Shift-arrows extend selection; Ctrl-Shift-A selects all
(Command-A also works on macOS). Consecutive kills combine in a per-field
buffer. Ctrl-P/N navigates existing lines where supported, not command history.
Terminal modifiers require distinguishable key sequences. Tab/Shift-Tab moves
focus; Enter/Space activates controls; Space inserts text in editors. Ctrl-Q/C
exits terminal mode; Ctrl-D deletes. Redirected input uses `:next`, empty-line
activation, text edits, and `:quit`.

The debugger attaches to the current context through `set-debugger-enabled`;
subsequent frames draw it automatically. Tree rows are virtualized, and hover
highlights bounds/clip without intercepting input. Stable IDs preserve selection;
anonymous nodes use paths under the closest ID, so identical reordered siblings
have positional identity. Removed selections clear. Clip/offscreen badges are
geometry information, not errors; duplicate-ID failures cannot yield a completed
frame for inspection. Drag the left sidebar edge or use Left/Right/Home/End on
its separator; `debugger-state-width` uses LUI spacing units. Drag the property
pane's top edge or use Up/Down/Home/End on its divider. Dragging to the bottom,
End, the close button, or reselecting its row dismisses the properties.

### Setup and build details

For direct ASDF use, load `lui.asd` or add
`(:directory "/absolute/path/to/lui/")` to
`~/.config/common-lisp/source-registry.conf.d/lui.conf`. Register optional
checkouts too. With Quicklisp, load `scripts/setup.lisp` and then
`(ql:quickload "lui")` for host dependencies. A missing `zpb-ttf` component means
the dependency must be installed/registered, not that the backend is broken.

Native builds use `scripts/build.lisp` and `save-lisp-and-die` to produce
`build/bin/demo-PLATFORM` (`.exe` on Windows). `make build` saves it; `make demo`
runs it; `RUN_ARGS=--smoke-test` renders one frame. `make terminal-demo` selects
the terminal. `make docs` opens the native documentation browser;
`make docs-html` produces the standalone HTML; `make docs-pages` copies changed
output into `docs/index.html`. GitHub Pages serves the repository's `/docs` folder.
`make loc` writes `build/logs/src-loc.txt`. Strict lint requires Mallet and writes
`build/logs/mallet-normalized.json`, failing on informational findings as well
as warnings. Logs are timestamped; Bash pipefail preserves pipeline failures.

For fonts, set `*font-path*` for the base face, `*font-paths*` for exact
family/weight overrides, and `*font-directories*`/`*font-names*` for ordered
search. Directory strings should end in a slash. Supported families are
`:sans-serif`/`:monospace`, weights `:normal`/`:bold`. PDF uses points (72/inch),
defaults to 612×792, and renders one display-free frame. Use `render-pdf` directly
or bind `*pdf-output*` (default `lui.pdf`) and run with `:backend :pdf`.

JSCL builds need Node.js and a built JSCL checkout. `make web-demo` serves
`build/index.html` from localhost (`PORT`, default 8000); open its printed root
URL and stop with Ctrl-C. `make web-build` builds without starting a server.
Windows testing can prefix launches with `RUNNER=wine` and an existing Windows
SBCL command/core in `SBCL`; configure WINEPREFIX and ASDF dependencies first.
`scripts/test-win32.lisp` is the direct Windows SBCL test launcher. Portable
Wayland callback checks live in `tests/wayland.lisp`; load `lui/wayland` and
`lui/demo` first. Offscreen GL checks similarly use `lui/gl`, `lui/demo`, and
`tests/gl.lisp`. Ensure `build/` exists.

### ECL/WebAssembly setup

The ECL browser build compiles Lisp to C, then links with Emscripten; it does not
use JSCL. `build/web-ecl/index.html` embeds its loader and WebAssembly and opens
as one static file without a server. `examples/web-ecl.html` is the development
template, not the standalone artifact. Browser interaction support is shared,
but performance and coverage must be validated separately for ECL and JSCL.

On a fresh Linux host, install Git, GNU Make, Bash, Python 3, a native C/C++
toolchain, and ECL's native prerequisites; SBCL generates the docs reference.
Run `make web-ecl-toolchain`, then `make web-ecl-build` or `make docs-pages`.
Setup downloads tested tools into `build/deps/`, makes no system-wide changes,
and preserves existing source checkouts when rerun. Other setup hosts remain
untested. The tested source is ECL `855f93431` with Emscripten `4.0.12`.
ECL needs `compile-file :target` support and a matching non-threaded host build
(`--disable-threads`); the same version string alone is insufficient. Host/target
structure macro behavior must match. Upstream references:
https://gitlab.com/embeddable-common-lisp/ecl/-/blob/develop/INSTALL and
https://ecl.common-lisp.dev/static/manual/System-building.html.

To reuse tools, set `ECL_SOURCE=/path/to/ecl` and
`EMSDK_ENV=/path/to/emsdk/emsdk_env.sh` before `make web-ecl-toolchain`.
`JOBS` sets parallelism; `ECL_WASM` selects the
installed target prefix (default `build/deps/ecl-wasm`), `ECL_TARGET_INFO` its
optional target-info override, and `EMCC` the compiler. Subsequent builds activate
`build/deps/emsdk/emsdk_env.sh` when emcc is missing; external SDKs require
EMSDK_ENV again or shell activation. Explicit EMCC overrides are respected;
compiler paths recorded in target info must remain available.

Application C and final WebAssembly use `-O3 -g0`; Lisp uses speed 3, safety 2.
Prebuilt ECL/GMP/GC libraries retain their toolchain settings. Preserve the
pointer-spilling linker pass, larger stack, and persistent callback runtime.
The interop bridge transfers numbers, Unicode strings, and object identities
through imports; separate argument frames permit synchronous DOM reentrancy
without JavaScript generation or Lisp text parsing. Set
`ECL_WEB_APP=/absolute/path/start.lisp` for an application entry that calls
`lui:run`. `make web-ecl-demo` serves the standalone output on localhost.

### Additional performance workflows

- Default benchmark dimensions: native/GL 720×520, web 900×700, core/terminal
  100×40 cells. The general 240-frame/30-warmup default spans 60 cases; require
  at least 60 measured frames and nonnegative warmup. Per-case results include
  mean, median, p95, maximum, and FPS.
- `make benchmark-web-parity` compares existing JSCL/ECL builds with matching
  viewports and steady redraws. BENCH_FRAMES/WARMUP are per case for this target,
  unlike the general benchmark. `PROFILE=1` saves ECL CPU profiles under
  `build/profiles/`. `make benchmark PLATFORM=web-ecl` builds both first.
  These are steady redraw measurements, not input-latency or scroll benchmarks.
- `python3 tests/profile-docs.py --output build/profiles/docs` profiles mobile
  docs scrolling with the debugger open/closed at normal speed and 6× CPU
  slowdown. `--bundle` selects saved HTML. Match viewport, wheels, warmup, and
  slowdown, and compare work per wheel if redraw counts differ. CPU throttling
  does not reproduce phone GPU/memory behavior.
- Measurement/caption reuse is limited to matching previous-frame inputs.
  Geometry callbacks still execute; custom context measurement callbacks are
  not cached. Text, font, width, and resolved geometry changes invalidate reuse.
- Allocation regression checks: set `LUI_BENCH_LIBRARY_ONLY=1`, load
  `scripts/benchmark.lisp` and `tests/benchmark.lisp` with SBCL, then call
  `(lui.tests.benchmark:run-tests)`. ALLOC rows report bytes total/mean/p95 and GC
  CPU milliseconds, with unsupported GC counts explicitly marked.
- Historical performance logs include `build/profile-wayland-before.log`,
  `profile-wayland-after.log`, `benchmark-wayland-after.log`,
  `benchmark-gl-after.log`, `web-raw-before.log`, and `web-final-benchmark.log`.
  The removed README's historical tables remain in Git history; do not present
  their machine-specific numbers as current results.

### Condition handling

`lui-error` inherits `simple-error` formatting and exposes `error-operation`.
`configuration-error` exposes `error-setting`/`error-value`; `backend-error`
exposes `error-backend`; its `font-error` subtype adds `error-font-request`.
`frame-state-error` indicates an operation requiring a completed frame. Catch
specific conditions and configure missing capabilities before retrying. Cleanup
still runs on unwinding. Invalid-argument assertions and application callback
errors retain their own condition types; do not wrap them indiscriminately.
