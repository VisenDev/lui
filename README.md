# LUI

LUI is an immediate-mode Common Lisp UI library under development. The same
[shared example](examples/demo.lisp) runs unchanged in a browser, native windows,
and a terminal. Applications own their state; `lui:run` owns the backend lifecycle.

All terminal rendering and interactive control use
[Plisp/uncursed](https://github.com/Plisp/uncursed). Native graphical backends
use LUI's own platform bindings: Xlib/GLX, libwayland/EGL, Win32/GDI+, and
Cocoa. X11 uses one display connection for windowing and direct OpenGL rendering.

Load the library with `(asdf:load-system "lui")` to register the backends for
your host. Use `lui/core` for the portable core with no external dependencies.
Native graphical backends add CFFI, zpb-ttf, and system rendering libraries. Browser output uses
JSCL or ECL/Emscripten and one high-DPI Canvas 2D surface per window. There is no application software pixel renderer; Vulkan remains future
work.

## Layout and widgets

- Rows, columns, fit/grow/fixed/percentage sizing, minimum/maximum bounds, padding,
  gaps, alignment, clipping, scrolling, and floating elements.
- Width-dependent text wrapping: horizontal sizing precedes measurement of height
  and vertical positioning. Percentage sizes exclude padding and inter-child gaps.
  Fixed sizes and minimum bounds may overflow instead of silently shrinking.
- Glass, Motif, Garnet, Ventura-inspired macOS, and Qt-inspired toolkits with labels, buttons, checkboxes, sliders, text
  fields, tabs, single-selection rows, progress gauges, circle canvases, and
  styled layout panels. Toolkits share interaction logic.
- Stable IDs, pointer capture, release activation, hover feedback, and keyboard
  navigation. Button clicks preserve existing keyboard focus; focus rings appear
  for keyboard navigation. Text fields acquire editing focus on click.
- Tabs support Left/Right wrapping and Home/End navigation, skipping disabled
  tabs. Widgets return current-frame values and activation results.

A draw function describes the current frame. Control macros generate stable
IDs for each call site, so ordinary forms need no explicit IDs. For example,
this application runs with any loaded backend:

```lisp
(defun counter (&optional (toolkit :qt))
  (let ((count 0))
    (lui:run
     (lambda ()
       (lui:with-toolkit (toolkit)
         (lui:panel (lui:opt :padding (lui:units 1))
           (when (lui:button "Count")
             (incf count))
           (lui:label (format nil "Count: ~D" count))))))))
```

`with-toolkit` evaluates its argument once and scopes ordinary widget calls.
`panel` attaches its body as children; the layout macros `lui:row` and
`lui:column` group children without painting a panel. Buttons return
activation; fields, sliders, and checkboxes return the current value and a
second value indicating a change, plus their resolved ID as the third value.
Widget values are retained by default. `:default-value` initializes a value
once; `:value` opts into application-owned state supplied every frame.

```lisp
(lui:run
 (lambda ()
   (let ((name (lui:text-field (lui:opt :default-value "Ada"))))
     (when (lui:button "Greet")
       (format t "Hello, ~A!~%" name)))))
```

For repeated controls, supply an instance key through `lui:opt :id`:

```lisp
(dotimes (i 10)
  (lui:text-field (lui:opt :id i))
  (lui:checkbox "Enabled" (lui:opt :id i :default-value t)))
```

Keys are combined with the call site, so the two controls can both use `i`.
Use stable item keys rather than indices when items can move or be deleted.
Repeating a control call site without distinct keys or scopes signals
`lui:configuration-error` with instructions for adding them. This is checked
when the second instance is declared, before it can reuse the first’s state.
Wrap repeated groups or reusable drawing functions in `(lui:with-key key ...)`.
IDs use `equal`; do not mutate compound keys after declaring them.
The public `lui:object-id` type names this identity contract and currently
expands to `t`, so arbitrary application objects remain valid IDs.

The scope macros delegate to functions: `call-with-key`, `call-with-toolkit`,
`call-with-palette`, and `call-with-frame`. The first three accept the scope
value and a zero-argument function, preserving its return values. For frames,
use `(lui:call-with-frame context width height draw :events events)`; it calls
`draw` once and returns the solved root. Bindings and cleanup follow the same
rules as the corresponding macros, including on errors and nonlocal exits.

Owned state is local to a UI context and is discarded when its widget is
absent from a completed frame. Recompiling a call site creates a new identity.
`lui:widget-id` resolves a unique declared key in the current key scope;
ambiguous keys signal `lui:configuration-error`. Use a control's third return
value when several call sites share a key. `lui:widget-key` extracts its declared
key, `lui:focus-widget` requests focus, and `lui:reset-editor` resets owned text
and its caret. Toolkit callbacks remain functions receiving resolved IDs;
public control macros cannot be passed to `funcall` or `apply`.

`lui:searchable-combobox` retains its editable string like `lui:text-field`.
Supply `:value` when the application owns it. Focusing the field shows suggestions in
an overlay, and typing filters them. Click a suggestion or highlight it with
Up/Down and press Enter to complete the field. Enter without a highlight,
Escape, and Tab keep the text you typed. `:max-results` limits suggestions.

```lisp
(setf country
      (lui:searchable-combobox '("Canada" "Japan" "United States") (lui:opt :id :country :value country :max-results 10)))
```

Radio controls can share one model value through `:value`. Each `lui:radio`
receives its own choice, then returns the updated value and a change flag:

```lisp
(setf size (lui:radio :small "Small" (lui:opt :id :small :value size)))
(setf size (lui:radio :large "Large" (lui:opt :id :large :value size)))
```

The public API is available through `lui:`. Optional systems add their API to
the same package when loaded: for example, `lui/debug` adds
`lui:set-debugger-enabled`, and `lui/web` adds `lui:mount`. Implementation
packages are for backend and library maintenance.

Qt is the default toolkit on every platform. Use `lui:with-toolkit` to select
a different appearance.

Use the optional final `lui:opt` form for widget customization. Its keyword
lambda list is visible to SLIME; layout keys such as `:gap` apply to panels,
whereas `:step` configures a slider. To change toolkit defaults, bind
`lui:*glass-defaults*`, `lui:*motif-defaults*`, `lui:*garnet-defaults*`,
`lui:*macos-defaults*`, or `lui:*qt-defaults*` for a
group. Options include foreground/background, radius, frost, opacity, accent,
font size, `:font-family` (`:sans-serif` or `:monospace`), and `:font-weight`
(`:normal` or `:bold`). Graphical
widgets also support a custom painter callback.

Palettes change colors independently of the toolkit's geometry. Both the demo
and docs start with Qt selected and have a **Cycle palette** control for Default, Light, Dark, Ocean, and
Forest. Default restores the chosen toolkit's colors; edited values survive
palette and toolkit changes. Applications can use the same presets:

```lisp
(lui:with-toolkit (:qt)
  (lui:with-palette (:ocean)
    (lui:button "Save" (lui:opt :id :save))))
```

`lui:available-palettes` returns a vector of preset names. `with-palette` also
accepts `lui:+palette-dark+`, `lui:+palette-light+`, `lui:+palette-ocean+`,
`lui:+palette-forest+`, and `lui:+palette-default+`. Custom palettes use
`lui:make-palette`; raw plists are not accepted. NIL color slots inherit the
enclosing scope or toolkit. Palette slots are read-only.
`:macos` evokes modern macOS controls;
`:qt` is Fusion-inspired. Both render through LUI's existing backends.

Toolkits choose terminal panel borders independently of graphical corner radius.
`:terminal-border` is a six-character string: top-left, top-right, bottom-left,
bottom-right, horizontal, and vertical. Glass uses `"╭╮╰╯─│"`; the other built-in toolkits
use `"++++-|"`. Custom toolkits can supply their own characters in their defaults.

User widgets can be ordinary functions composed from these controls. For
example, this adds a selectable badge to a toolkit and inherits the rest
of its controls from Motif:

```lisp
(defun badge (id text &optional options)
  (lui:button text (list* :id id (append options (lui:opt :foreground "#105030")))))

(lui:register-toolkit :paper :parent :motif
                      :defaults (lui:opt :background "#fff9ea")
                      :controls (list (cons :badge #'badge)))

;; Inside a draw function:
(lui:with-toolkit (:paper)
  (when (lui:control :badge :publish "Publish")
    (publish-document)))
```

Use `badge` directly when all toolkits share that definition. Use
`control` for toolkit-specific implementations of a new control; registration
can also replace standard controls such as `:button`. Overrides of a standard
control receive its positional arguments plus the options list (possibly NIL).
Compose another control or explicitly select a parent toolkit to delegate.
A toolkit can also provide its own graphical painter and intrinsic sizing for
new widget kinds. This toolkit draws a badge with a minimum intrinsic size.

```lisp
(lui:register-toolkit :ink
  :controls
  (list (cons :badge
    (lambda (id text &rest options)
      (apply #'lui:declare-widget :badge (lui:current-toolkit)
             id text options))))
  :geometry (lambda (widget)
              (declare (ignore widget))
              (lui:make-geometry :left 8 :right 8 :top 6 :bottom 6
                                      :min-width 96 :min-height 28))
  :paint (lambda (renderer node)
           (let ((box (lui:element-box node)))
             (lui:shape renderer box 4 "#183b35" 1)
             (lui:outline renderer box 4 "#367c6e" 1 1)
             (lui:paint-text renderer
               (lui:widget-text (lui:element-content node))
               (+ 8 (lui:box-x box))
               (+ 19 (lui:box-y box)) "#ffffff")))
  :native-labels nil)

(lui:with-toolkit (:ink)
  (lui:control :badge :ready "Ready"))
```

`:paint` receives the shared graphical renderer and element on desktop and web.
`:geometry` receives a widget and returns a `lui:geometry`: text insets,
minimum size, centering, and optional pressed displacement. Measurement, built-in
painting, caret placement, and text selection share this geometry. Custom painters
can use `lui:text-box` to obtain the same text area. These callbacks and the
`:native-labels` policy inherit from the parent toolkit. Overriding painting or
geometry selects canvas labels by default; set `:native-labels t` when the painter
supports the browser's native selectable labels. The exported `lui:shape`,
`lui:outline`, and `lui:paint-text` primitives use the current backend.
A widget's `:painter` callback takes precedence over the toolkit painter.
`:terminal-label` takes a widget and returns its text. Terminal panel borders
follow `:terminal-border`; button delimiters follow the widget’s radius.

Color themes are independent of toolkit geometry and painting. Toolkit defaults
contain a `:palette` plist; `lui:with-palette` overrides selected roles for controls
created in its scope, including nested scopes and mixed toolkits in one frame:

```lisp
(lui:with-toolkit (:motif)
  (lui:with-palette ((lui:make-palette :background "#202830" :foreground "#eeeeee"
                       :accent "#66bbee" :bevel-light "#708090"
                       :bevel-dark "#101820"))
    (lui:button "Save")))
```

`lui:widget-color` reads a resolved role from a widget. Besides foreground,
background and accent, roles cover disabled text, selection, on-accent text,
borders, light/shadow, tracks, disabled surfaces, bevel edges, and cell colors.
The remaining role keys are `:disabled`, `:selection`, `:on-accent`, `:border`,
`:outline`, `:light`, `:shadow`, `:track`, `:disabled-accent`, `:disabled-surface`,
`:bevel-light`, `:bevel-dark`, `:disabled-bevel-light`, `:disabled-bevel-dark`,
`:cell-background`, and `:cell-foreground`. Explicit widget color options take precedence. Each widget captures its palette,
so later drawing does not depend on a dynamic theme binding.

Collection APIs return vectors with declared element types: wrapped lines are
`(vector string)`, event batches are `(vector lui:event)`, and drawing
callbacks receive `lui:contours` (vectors of contours, each a vector of
X/Y cons pairs). Colors are four-element single-float vectors. Use `aref`,
sequence operations, or `loop ... across` to consume these results. Configuration
plists, control alists, Lisp forms, and internal pending-event queues remain lists.

There is one [demo gallery](examples/demo.lisp), with Controls, Editing, Layout,
Scroll, Styles, and 7GUIs pages. Its toolkit selector changes the toolkit for
the whole gallery, so each page uses one toolkit consistently. Style Preview
buttons select an interactive sample. Motif uses an opaque matching background,
beveled checkboxes, and visually distinct disabled buttons. Garnet uses bold
monospaced text, black hairlines, checker stipples, hard offset shadows, and X
checkboxes inspired by the original Garnet gadgets. Window backgrounds remain
opaque; Glass translucency composites within the application. The gallery also
displays actual FPS alongside average layout processing milliseconds per frame
in both the demo and docs. FPS includes idle/backend pacing. Layout time is a
rolling average of the last 30 frames, shown with one decimal place; it includes
measurement but excludes UI construction, painting, presentation, and pacing.
Dividing 1000 by this time gives a layout-only FPS ceiling, not end-to-end FPS.
Its sliders have tracks
and thumbs, colors distinguish selection from pointer hover, and text/clip edges
share cell rounding. Uncursed owns cell storage, Unicode widths, ANSI style encoding, and incremental
screen updates; LUI supplies widget layout and input translation. Plain snapshots remain
escape-free.

The 7GUIs page includes Counter, Temperature Converter, Flight Booker, Timer,
CRUD, Circle Drawer with undo/redo, and a virtual A0:Z99 spreadsheet. Formulas use
a small safe parser and incremental dependencies. Every page uses the same Lisp
code on all backends. The Glass Styles preview places stripes behind its sample,
so frost and opacity changes can be compared visibly without window transparency.

## Make commands

The Makefile uses GNU Make, Bash, and SBCL. Backend dependencies and display
requirements still apply. Python 3 runs browser serving and the existing
terminal/X11/browser integration tests; `cloc` is needed for source reports and
the test/benchmark targets. Run from the repository directory:

```sh
make docs                    # Build and open the native documentation browser
make docs-html               # Build the standalone page at build/docs.html
make docs-pages              # Update docs/index.html for GitHub Pages
make build                   # Save the native demo executable
make demo                    # Build and run the same executable
make terminal-demo           # Build and run in the terminal
make demo RUN_ARGS=--smoke-test
make test                    # Platform checks, executable smoke test, and log
make loc                     # cloc src, by file
make benchmark               # Throughput/frame-time measurements and log
```

The documentation browser contains a getting-started guide and a searchable
reference generated from the library's exported symbols, signatures, and
docstrings. `make docs` opens the native browser using SBCL. For an offline
HTML copy, run `make docs-html`. It compiles the application with
ECL/Emscripten and embeds WebAssembly and its loader in a single file. This
requires the same toolchain as `make web-ecl-build` (see the ECL browser setup
below). Run `make docs-pages` to build the HTML if needed and copy
it to `docs/index.html` when the contents differ. Commit that file to update
a GitHub Pages site configured to serve the repository’s `/docs` folder.

The reference covers application controls, layout and interaction helpers,
toolkit customization, inspection, browser embedding, and native painter/font
extensions. Its explicit symbol allowlist omits backend plumbing, raw context
and layout-tree management, wire protocols, compiler helpers, and adapter
runners; use `lui:run` to select a backend. Exports used only between implementation
modules are not public reference entries. Public reexports remain documented
under their application-facing package.

Native builds invoke SBCL with `--load scripts/build.lisp`, load the backend and
shared demo, then use `sb-ext:save-lisp-and-die` to save
`build/bin/demo-PLATFORM` (`.exe` on Windows). `make demo` runs that executable;
`RUN_ARGS=--smoke-test` renders one frame and exits. It can also be run directly:

```sh
make build PLATFORM=terminal
build/bin/demo-terminal --smoke-test
make demo PLATFORM=x11
```

`PLATFORM` defaults to Windows on Windows, Cocoa on macOS, then Wayland when
`WAYLAND_DISPLAY` is set, X11 when `DISPLAY` is set, or terminal otherwise.
Selection uses the environment; it does not start a display server. Override
with `terminal`, `x11`, `wayland`, `win32`, `cocoa`, or `web`. `core`, `native`,
and `gl` select tests without launching a native demo; `core` and `gl` also
support offscreen benchmarks.

`make test` runs core checks, native font/painter checks where applicable, and
the selected backend checks. Web tests use JSCL for the core. Native platforms
also build and smoke-test the saved executable; AppKit executable tests are
explicitly skipped on Linux. Tests print stage progress and a final PASS/FAIL
result. Timestamped test and benchmark logs go in `build/logs/`, including the
source count report. Bash `pipefail` preserves failures while `tee` displays and
records output. `make test-core` and `make test-native` run individual checks.
`make loc` counts `src/` with cloc and writes `build/logs/src-loc.txt`; generated
build files, examples, and test code are outside that source count.

`make benchmark` defaults to 240 measured frames total after 30 warmup frames,
spread across all five toolkits, five gallery pages, and every 7GUIs task
(60 cases; 4 measured frames per case by default). Use 1200 frames and 240
warmup frames for 20 samples per case. `BENCH_FRAMES` must be at least 60
and `WARMUP` nonnegative. Reports
include per-toolkit/page FPS, mean, median, 95th-percentile, and maximum frame
time, plus timer/settings information.

Windowed native results include event-loop, window-system, and presentation
pacing; browser results actively redraw the application and measure completed
frames plus application/layout/drawing work, rather than idle animation ticks. The
`core` benchmarks layout with deterministic text metrics; `terminal` measures
layout and terminal snapshot rendering through uncursed; `gl`
measures an offscreen pipeline with `glFinish`. These paths should not be
compared as equivalent screen FPS. Compare logged platform/settings and matching
toolkit/page rows:

```sh
make benchmark PLATFORM=core BENCH_FRAMES=240 WARMUP=30
make benchmark PLATFORM=gl
make benchmark PLATFORM=x11 BENCH_CASE=glass/controls
```

Native and core benchmarks accept `BENCH_CASE` to repeat just one page,
for example `glass/controls` or `garnet/seven/cells`. X11 timings include
buffer swaps and GPU completion.

The web benchmark can compare steady Cells redraws with continuous wheel
scrolling in the same viewport. The scrolling case checks that the sheet
moves and reports its travel in pixels.

```sh
BENCH_TOOLKITS=Glass BENCH_PAGES=7GUIs/Cells,7GUIs/Cells-scroll \
  make benchmark-platform PLATFORM=web BENCH_FRAMES=120 WARMUP=16
```

Set `BENCH_DETAIL=1 BENCH_OUTPUT=build/cells-profile.json` for per-phase
timings. Frame completion includes layout, and layout includes widget
measurement, so those nested timings overlap.

Graphical widget measurements and debugger captions reuse matching results
from the previous completed frame. Toolkit geometry callbacks still run on
every measurement; custom context measurement callbacks are not cached.
Changed text, fonts, available widths, or resolved geometry invalidate reuse.

To profile mobile docs scrolling with the debugger closed and open, at normal
speed and 6× CPU slowdown, use:

```sh
make docs-pages
python3 tests/profile-docs.py --output build/profiles/docs
```

The profiler saves frame samples and Chrome CPU profiles. Use `--bundle` with
a saved standalone HTML build for comparisons. Keep the viewport, wheel count,
warmup, and slowdown matched; compare work per wheel as well as work per frame
when redraw counts change. CPU throttling does not reproduce a phone's GPU or
memory, and these timings exclude GPU rasterization and presentation.

SBCL runs also print separate `ALLOC` rows per case and for `all/all`:
`bytes_total`, `bytes_mean`, and `bytes_p95` measure Lisp bytes allocated per
measured frame; `gc_cpu_ms` reports GC CPU time inside those frame intervals.
`gc_count=unsupported` is explicit: SBCL's public asynchronous GC hooks do not
provide an exact per-frame garbage collection count. This applies to Cocoa when
benchmarking with SBCL on macOS. Existing `RESULT` timing rows retain their format.

The counters are process-wide, using SBCL's documented `get-bytes-consed`
and `*gc-run-time*`. Warmup, case selection, sample storage, and reporting are
excluded from allocation samples;
small counter overhead can remain. Windowed samples include backend event
handling and presentation. GC CPU time is not a wall-clock pause measurement,
and unrelated threads can contribute to process-wide counters. Foreign/GPU
memory, including AppKit/C allocations, is outside the Lisp allocation counter.
Other Lisp implementations report `status=unsupported`, rather than a
misleading zero.
Browser reports currently measure frame work, not total JavaScript allocations;
a heap-size delta would describe retained heap, not allocated bytes.

`BENCH_WIDTH` and `BENCH_HEIGHT` reproduce the application size, including
large-window workloads. Defaults are 720×520 for native/GL, 900×700 for web,
and 100×40 cells for core/terminal; explicit settings override these defaults.
For example, on a Mac:

```sh
make benchmark PLATFORM=cocoa BENCH_WIDTH=1920 BENCH_HEIGHT=1000 \
  BENCH_FRAMES=720 WARMUP=144
```

Allocation accounting regression checks can be run independently:

```sh
LUI_BENCH_LIBRARY_ONLY=1 sbcl --noinform --non-interactive \
  --load scripts/benchmark.lisp --load tests/benchmark.lisp \
  --eval '(lui.tests.benchmark:run-tests)'
```

Override `SBCL` for its executable or command prefix and `SBCL_FLAGS` for its
flags (default `--noinform --non-interactive`). The POSIX terminal PTY and X11
harnesses launch installed SBCL themselves; those subprocesses do not use a
custom `SBCL` command. Raw-terminal PTY checks are skipped on Windows. `PYTHON`
selects the interpreter for Python tests and browser serving. `RUNNER` prefixes
saved executable launches, for example with Wine:

```sh
make test PLATFORM=win32 RUNNER=wine \
  SBCL='wine C:/sbcl/sbcl.exe --core C:/sbcl/sbcl.core'
```

Supply the appropriate existing `WINEPREFIX` and ASDF dependency configuration
for that Windows Lisp. Make does not install Wine, Lisp, or dependencies.

Browser builds need Node.js and a built JSCL checkout:

```sh
make test PLATFORM=web JSCL=/path/to/jscl
make web-demo JSCL=/path/to/jscl PORT=8080
make web-build JSCL=/path/to/jscl
```

`JSCL` defaults to `~/clone/jscl`. `make web-demo` builds the gallery and
`build/index.html`, prints its local URL, and runs `python3 -m http.server`
bound to localhost with `--directory build`. Open the printed root URL
(default [http://localhost:8000/](http://localhost:8000/)); it opens the app, not
a directory listing. `PORT` defaults to 8000. Stop the server with Ctrl-C.
`make web-build` only builds JavaScript. Browser tests additionally need
Playwright and Chromium.

### ECL / WebAssembly browser backend

`PLATFORM=web-ecl` compiles Lisp to C with ECL and links it to WebAssembly
with Emscripten. The generated `build/web-ecl/index.html` embeds both the
JavaScript loader and WebAssembly: one static HTML file, with no companion
assets or server required. JSCL is not used
in this build. Both browser builds share Canvas painting, DOM labels,
accessibility, text editing, and page/viewport scrolling. The new backend is
experimental; do not assume JSCL performance or browser coverage carries over.

Use an ECL source checkout with `compile-file :target` support, a matching
host compiler built with `--disable-threads`, and an installed Emscripten SDK.
An older release with the same ECL version string may lack cross-compilation
support. The development checkout used here is ECL `855f93431`, with
Emscripten `4.0.12`. See the upstream
[ECL build instructions](https://gitlab.com/embeddable-common-lisp/ecl/-/blob/develop/INSTALL)
and [cross-compilation manual](https://ecl.common-lisp.dev/static/manual/System-building.html).
The host must match the target's structure macro behavior as well as its version.

On a fresh machine, install Git, GNU Make, Bash, Python 3, a native C/C++
build toolchain, and ECL's native build prerequisites. SBCL is also needed
for generating the docs reference. Then run:

```sh
make web-ecl-toolchain  # Download tested versions and build both ECL variants
make web-ecl-build      # Standalone gallery
make docs-pages         # Standalone docs and published copy
```

Setup needs internet access and installs everything under `build/deps/`,
without system-wide changes. Subsequent builds activate the local SDK
automatically. The setup command can be rerun; existing source checkouts are
preserved and Emscripten 4.0.12 is selected in the local SDK. The workflow has
been validated on Linux; other build hosts remain untested.

To use existing tools instead of downloading them:

```sh
ECL_SOURCE=/path/to/ecl EMSDK_ENV=/path/to/emsdk/emsdk_env.sh \
  make web-ecl-toolchain
```

For subsequent builds with an external SDK, set `EMSDK_ENV` again or source
its environment script in your shell. `JOBS` controls build parallelism.
`ECL_WASM` selects the installed wasm ECL prefix (default
`build/deps/ecl-wasm`); `ECL_TARGET_INFO` can select its `target-info.lsp`
explicitly. `EMCC` selects the Emscripten compiler. The launcher activates
`build/deps/emsdk/emsdk_env.sh` automatically when `emcc` is missing from
`PATH`. Set `EMSDK_ENV=/path/to/emsdk/emsdk_env.sh` to activate another SDK,
or activate it in your shell. Explicit `EMCC` overrides are respected.
Keep the compiler paths recorded in target info available as well.
The build uses ECL's required pointer-spilling linker pass for garbage
collection, a larger stack, and a persistent runtime for browser callbacks.
Both docs and gallery builds compile application C and link WebAssembly with
`-O3`, stripping debug information with `-g0`. Lisp compilation uses speed 3
and retains safety 2. Prebuilt ECL/GMP/GC libraries retain their toolchain
compile settings; the final WebAssembly optimization also processes their
linked code.

Output is isolated in `build/web-ecl/`. Copy or open `index.html` on its own,
or serve the build directory over HTTP; `make web-ecl-demo` does this on
localhost using `PORT`. `examples/web-ecl.html` is the build template and
still references the generated loader for development. For an application
of your own, set `ECL_WEB_APP=/absolute/path/start.lisp` to a Lisp file that
defines your draw function and calls `lui:run` (optionally with
`:backend :web-ecl`). It is compiled and linked after the library. The
default entry file runs the shared gallery. The interop bridge transfers
numbers, Unicode strings, and object identities directly through WebAssembly
imports. Calls have separate argument frames so synchronous DOM events can
reenter Lisp safely. No JavaScript source generation or Lisp text parsing is
performed for browser calls.

To compare existing JSCL and ECL builds with the same redraw workload:

```sh
BENCH_TOOLKITS=Glass,Motif,Garnet,macOS,Qt \
BENCH_PAGES=Controls,Editing,Layout,Scroll,Styles,7GUIs/Cells \
BENCH_FRAMES=120 WARMUP=30 BENCH_OUTPUT=build/parity.json \
  make benchmark-web-parity
```

This target uses `BENCH_FRAMES` and `WARMUP` per toolkit/page case. It fixes
both viewports to `BENCH_WIDTH` × `BENCH_HEIGHT` (default 900×700), requests
steady redraws through the same resize notification, and measures the animation
callback plus a browser layout flush. Reported work times exclude GPU
rasterization; active FPS includes animation-frame pacing. `PROFILE=1` saves
ECL browser CPU profiles under `build/profiles/`. `make benchmark PLATFORM=web-ecl`
builds both implementations before running this comparison. These are steady
redraw measurements, not input latency or continuous-scroll benchmarks.

## Install and run

Start a Common Lisp implementation in the repository directory:

```lisp
(require :asdf)
(asdf:load-asd (truename "lui.asd"))
(asdf:load-system "lui/demo")
(asdf:load-system "lui/terminal")
(asdf:test-system "lui")
(lui:run (lui.example.demo:make-demo) :backend :terminal :interactive nil)
```

To make LUI discoverable from other directories, put the following in
`~/.config/common-lisp/source-registry.conf.d/lui.conf`, substituting the actual
absolute repository path:

```lisp
(:directory "/absolute/path/to/lui/")
```

Optional dependencies must also be discoverable through ASDF.
The makefile launchers also discover checkouts under `build/deps/`:

```sh
mkdir -p build/deps
git clone https://github.com/Plisp/uncursed.git build/deps/uncursed
git -C build/deps/uncursed checkout 89f9cb6f21bc7e981a04ce0d6361ae73dde49c4f
```

LUI requires uncursed 0.7.0 or later; Quicklisp's 0.3.0 release is too old.
The tested uncursed revision is:

| Library | Revision |
| --- | --- |
| uncursed | `89f9cb6f21bc7e981a04ce0d6361ae73dde49c4f` |

With Quicklisp installed, load `scripts/setup.lisp` and use
`(ql:quickload "lui")` to install the transitive dependencies for your host.
Applications loading through ASDF directly should register these checkouts in
their source registry. uncursed uses CFFI grovel and requires a C compiler.
No native rendering library is bundled. A TrueType font is required for native graphics: common system paths
are tried automatically, or set `lui:*font-path*` after loading the backend.
To use an installed or bundled font family, set these variables **before**
opening the window. For a saved executable, set `LUI_FONT` to the base TTF
path or `LUI_FONT_DIR` to an additional search directory at launch time.
`*font-directories*` lists directory pathnames (or strings
ending in a slash); `*font-names*` maps each family and weight to candidate
filenames. Lookup tries each filename across those directories in order.
For example, to search your own directory first:

```lisp
(push #p"/opt/my-app/fonts/" lui:*font-directories*)
(push '((:sans-serif :normal) "MySans.ttf") lui:*font-names*)
```

An exact face override takes precedence over directory search, and
`*font-path*` takes precedence for the base face.
Additional faces are cached and closed with the base font. Override their paths
with `lui:*font-paths*`, for example
`'(((:monospace :bold) . "/path/to/Mono-Bold.ttf"))`. Browser measurement and
painting use the same CSS family and weight.

| ASDF system | Purpose and system requirements |
| --- | --- |
| `lui` | Core and the backends supported on the host |
| `lui/core` | Dependency-free layout and widgets |
| `lui/terminal` | All terminal output via uncursed cells/styles and incremental rendering, plus input/lifecycle; terminfo on Unix |
| `lui/native` | Shared native measurement and outline painting; CFFI, zpb-ttf |
| `lui/pdf` | Single-page PDF output through cl-pdf and the native font renderer |
| `lui/x11` | Xlib and system OpenGL; an X display with GLX |
| `lui/gl` | EGL/OpenGL renderer; EGL and compatibility OpenGL libraries |
| `lui/wayland` | Wayland client/EGL, xkbcommon, EGL/OpenGL, a Wayland compositor |
| `lui/win32` | Windows User32, GDI32, Kernel32, and GDI+ |
| `lui/cocoa` | macOS AppKit and Objective-C runtime; SBCL only |

On Linux, the aggregate prefers a Wayland session with a socket, then X11
when `DISPLAY` is set, and otherwise uses the terminal.
Pass `:backend` to `lui:run` to choose a loaded backend explicitly.

To load a single graphical backend for the gallery:

```lisp
(asdf:load-system "lui/x11")
(asdf:load-system "lui/demo")
(let ((lui:*backend* :x11))
  (lui.example.demo:main))
```

Use `lui/wayland` with `:wayland`, `lui/win32` with `:win32`, or `lui/cocoa` with
`:cocoa` in the same launcher. `lui:available-backends` lists loaded backends.
Width and height are backend coordinates; omit them for backend defaults.

### PDF output

Install the optional dependency with `(ql:quickload "cl-pdf")`. A PDF export
draws one frame without a display. Dimensions are PDF points (72 per inch) and
default to US Letter, 612 × 792. The native painter draws text as vector
outlines, preserving the selected font and layout. The resulting text cannot
be selected or searched.

```lisp
(asdf:load-system "lui/pdf")
(lui:render-pdf (lambda () (lui:label "Quarterly report"
                                          (lui:opt :foreground "#17212b")))
                    #p"report.pdf" :width 595 :height 842 :background "#ffffff")
```

For existing `lui:run` callers, bind `lui:*pdf-output*` (default `lui.pdf`) and
pass `:backend :pdf`. Run `(asdf:test-system "lui/pdf")` to test the backend.
Run `make pdf` to open the worked example in your default PDF viewer.
For generation only, run `make build/pdf-demo.pdf`. The source in `examples/pdf-demo.lisp` shows a composed
one-page brief with panels, labels, and a table.

Text inputs share GNU Readline-style commands across backends:

| Shortcut | Action |
| --- | --- |
| Ctrl-A / Ctrl-E | Beginning / end of line |
| Ctrl-B / Ctrl-F | Backward / forward character |
| Alt-B / Alt-F, Ctrl-Left / Ctrl-Right | Backward / forward word |
| Ctrl-D / Ctrl-H | Delete forward / backspace |
| Ctrl-K / Ctrl-U | Kill to end / beginning of line |
| Ctrl-W / Alt-D | Kill previous / next word |
| Ctrl-Y / Ctrl-T | Yank killed text / transpose adjacent characters |
| Shift-arrows | Extend selection |
| Ctrl-Shift-A | Select all; Command-A also remains available on macOS |

Consecutive kills combine in a per-field kill buffer. Ctrl-P/N navigate existing
lines where supported; there is no command-history model. The browser uses a shared textarea for keyboard composition and clipboard events. Modifier reporting differs between terminal
emulators, so Ctrl-Shift-A requires a distinguishable terminal key sequence.

Run `make terminal-demo` for a real terminal, or load `lui/terminal` and
select `:terminal`. Tab and Shift-Tab move focus forward and backward. Enter and
Space activate buttons/tabs or toggle checkboxes; Space inserts text in editors.
Arrows adjust sliders, navigate tabs, or move the text cursor. SGR mouse clicks,
dragging, wheel scrolling, and terminal resizing are supported. Ctrl-Q or Ctrl-C
exits; Ctrl-D deletes text. Terminal attributes, mouse modes, cursor visibility,
and the alternate screen are restored on exit and Lisp errors. Other platforms
and non-TTY input retain line input: `:next`, an empty line to activate, text to
edit, and `:quit`. Noninteractive terminal output also requires `lui/terminal` and uncursed. Cell
widths approximate common CJK, emoji, and combining marks; full grapheme handling
is not implemented.

For the browser, `make web-demo JSCL=/path/to/jscl` compiles and serves the
same `examples/demo.lisp`. Open the root URL printed by the server;
it is not a separate browser application. `make web-build` builds the JavaScript
without launching a server.

On touch-first devices, a standalone web app with no explicit height grows
to fit its content. Swipe vertically to scroll the page. The canvas draws
the next scroll position before moving the page, and labels support browser
text selection. Direct calls to `lui:mount` use the same default.
Pass `:scroll-mode :viewport` for a fixed-height embedded view, or
`:scroll-mode :page` to expand into the page on any device.

## Rendering differences

Native text uses zpb-ttf metrics and TrueType outlines, including curved contours
and holes. Platform drawing libraries or OpenGL rasterize those outlines.
Appearance is backend-dependent:

| Backend | Glass presentation |
| --- | --- |
| Canvas 2D | Shared toolkit painters, clipped backdrop blur and browser text metrics |
| EGL/OpenGL / Wayland | Backdrop sampling, blur, and an edge refraction approximation |
| X11/GLX | Uses the same OpenGL glass shader, glyphs, and geometry cache as Wayland. |
| Win32 | Native filtered downsample/upsample backdrop blur, tint, and rim; no refraction |
| Cocoa | Shared OpenGL glass shader on accelerated windows; AppKit tint fallback |
| Terminal | Cell text and square/rounded panel outlines |

These effects are approximations, not identical implementations of a single
physical glass model.

The gallery and docs display the measured frame rate and frame interval.
The browser positions read-only labels as native HTML text. You can select and
copy them with the browser, and screen readers can read them in layout order.
Canvas paints the controls and any label that a later surface overlaps. A
shared text field handles keyboard composition. Buttons, list items, tabs,
checkboxes, and radio buttons expose named HTML controls that screen readers
can activate. Sliders and editable fields use the toolkit’s focus handling.

## Local performance evidence

In a 60-frame headless Chromium comparison, downsampling the Glass backdrop
reduced canvas draw time from 25.34 to 9.26 ms for Controls and from 61.01
to 37.94 ms for Cells. The former DOM renderer took 4.12 and 33.84 ms on
the same cases. Navigation through the first frame took about 492 ms on
both renderers. These timings include the shared Lisp layout work.

A November 5 full run covered all 36 toolkit/page/task combinations with
720 measured frames and 144 warmup frames per backend. Core layout/terminal
rendering averaged 0.266 ms; offscreen GL with `glFinish` averaged 2.569 ms
(389 FPS); the paced Wayland window averaged 6.029 ms (166 FPS, p95 5.946 ms).
The previous DOM backend averaged 9.452 ms of Lisp/DOM/layout work. Most browser cases reached
60 active FPS, but Cells reached 30–33 FPS and Glass Styles reached 43 FPS.
Browser per-case p95 values are reported; no pooled browser p95 was measured.
Cells click-to-visible latency improved from about 725 ms cold / 670–692 ms warm
to 152 ms cold / 112–125 ms warm. Native and browser timing paths measure
different work and should not be compared as equivalent FPS scores.

Short isolated Wayland runs used a 170 Hz monitor at 150% scale and a requested
720×520 window. Offscreen GL used 720×520; headless Chromium used a 900×700
viewport. These are machine-specific results, not performance guarantees.
Reproduce the measurement paths with:

```sh
make benchmark PLATFORM=wayland BENCH_FRAMES=60 WARMUP=10
make benchmark PLATFORM=gl BENCH_FRAMES=60 WARMUP=10
make benchmark PLATFORM=web BENCH_FRAMES=240 WARMUP=30
```

| Local run | FPS | Mean frame time | 95th percentile |
| --- | ---: | ---: | ---: |
| Wayland before optimization, profiled | 8.04 | 124.309 ms | 158.884 ms |
| Wayland after optimization, unprofiled | 170.22 | 5.875 ms | 5.978 ms |
| Wayland after optimization, profiled | 170.19 | 5.876 ms | 5.970 ms |
| Offscreen GL after optimization, `glFinish` | 397.94 | 2.513 ms | 6.510 ms |

The matched profiled Wayland runs show about a 21× throughput improvement;
the unprofiled result confirms the post-optimization timing. Wayland includes
compositor pacing, while offscreen GL has no screen presentation limit.
These numbers do not rank the backends against one another.

Browser timings measure completed application redraws plus a browser layout
flush, excluding GPU rasterization. The original idle-callback measurement is
not used. At 900×700, the same Glass gallery changed as follows (10 baseline
samples and 24 updated samples per page):

| Browser page | Before mean | After mean | After 95th percentile |
| --- | ---: | ---: | ---: |
| Controls | 79.180 ms | 4.679 ms | 6.000 ms |
| Scroll, 60 rows | 280.950 ms | 10.558 ms | 11.200 ms |

The recorded 240-frame run across Glass and Motif and all five pages completed at
59.65–60.45 FPS, with means of 3.97–10.56 ms. The benchmark also verifies that
wheel input over a row moves the content. Improvements come from cached text
measurements and unchanged DOM styles, lazy terminal strings, and direct layout
traversal. The JSCL build overrides standard `defstruct` expansion to omit
generated constructor and writer slot checks, retaining slot metadata and
initializer checks. Native builds use the implementation’s standard `defstruct`. Direct child traversal
also avoids JSCL's exception-based jumps in general LOOP expansions.

Recorded local evidence is in generated logs under `build/`:
`profile-wayland-before.log`, `profile-wayland-after.log`,
`benchmark-wayland-after.log`, `benchmark-gl-after.log`,
`web-raw-before.log`, and `web-final-benchmark.log`. Logs include the workload
and timing settings;
new `make benchmark` runs also record the current cloc source report.

## Layout debugger

The gallery's **Show debugger** button opens a Clay-style debugger in the current
widget toolkit. Expand or collapse the element tree, hover a row to highlight
its bounds and clipping rectangle, and select it for sizing, alignment, spacing,
scrolling, and widget details. Tree rows are virtualized. The highlight preserves
pointer input and terminal text; the debugger is excluded from its own tree.

Select a tree row to inspect its properties. Drag the pane’s top edge up or
down to resize it. With the divider focused, use Up and Down to adjust the
height, Home to enlarge it, or End to dismiss it. Dragging the edge to the
bottom, clicking ×, or clicking the selected row again also dismisses the pane.
Bounds shows
the allocated rectangle, while Clip shows the part visible through its
ancestors. Compare these with the widget’s width and height rules to diagnose
truncated text or a control that grows unexpectedly.

The debugger attaches to the current frame context. A menu item or key handler
can toggle it once; subsequent frames draw the debugger automatically:

```lisp
(asdf:load-system "lui/debug")
(when (lui:button "Show debugger" (lui:opt :id :debug))
  (lui:set-debugger-enabled t))
```

Drag the debugger's left edge to resize its sidebar; the width persists.
Focus the separator and use Left/Right or Home/End to resize from the keyboard.
`lui:debugger-state-width` can also set its optional width in LUI spacing units.
The terminal tree uses one dense line per row, and floating debugger panes
cover the underlying borders.

The debugger reads the previous completed frame. Stable IDs preserve selection;
anonymous elements use paths below the closest ID, so reordered identical
anonymous siblings have positional identity. Removed selections are cleared.
Clipping/offscreen badges describe geometry, not errors. Duplicate IDs still
raise the core layout error and cannot be inspected as a completed frame.
Closing the debugger stops tree collection and formatting.

## Frame contract

`with-frame` executes the application body once and returns its solved root.
Rows, columns, and panels declare temporary layout elements. Input is routed
against the previous completed layout. IDs use `equal`; use stable symbols,
strings, or compound IDs, and do not mutate them after declaration. Duplicate
non-NIL IDs are errors. Resize invalidates old pointer geometry. Removed widgets
lose focus/capture; an aborted frame invalidates geometry.

Backends measure `(widget available-content-width) -> width, height`; NIL width
requests intrinsic measurement. Dimensions must be nonnegative. Measured leaves
cannot have children. Value widgets return the new value and a changed flag.
Layout structs are frame-local and should not be mutated after completion.
Temporary storage currently allocates per frame; pooling is deferred.

## Tests and current evidence

Portable source tests run without ASDF or dependencies:

```sh
sbcl --script tests/run.lisp
clisp -q -q tests/run.lisp
ecl -shell tests/run.lisp
node /path/to/jscl/dist/jscl-node.js tests/run.lisp
```

Additional checks:

- `(asdf:test-system "lui/native/tests")` runs native font and painter regressions.
- `python3 tests/terminal.py` runs the shared demo in a POSIX PTY on SBCL, CLISP,
  and ECL; `--lisp sbcl` selects one implementation.
- `make test-terminal-parity` compares full renderer and I/O output against
  commit `16f79dd` using real SBCL PTYs and an accumulating terminal-screen
  model. It compares cells, colors, focus, scrolling, Unicode, clipping, and
  resizing across all three toolkits. Layout, widgets, and examples remain
  current on both sides; the historical commit must exist in local Git history.
- `(asdf:test-system "lui/terminal")` runs terminal raster and incremental-output
  regressions. Core and JSCL tests cover layout and widget behavior without
  loading the terminal backend.
- `python3 tests/x11.py` requires an X display, SBCL, and Pillow, as well as
  the X11 backend dependencies. Pixel checks capture the test windows with XGetImage.
- `python3 tests/web.py` requires the browser build, Playwright, and Chromium.
- On Windows SBCL, run `sbcl --script scripts/test-win32.lisp` with dependencies
  registered in ASDF. The launcher also works with Windows SBCL under Wine.
- After loading `lui/gl` and `lui/demo`, load `tests/gl.lisp` for the
  offscreen EGL/OpenGL smoke test. Ensure `build/` exists.
- With a Wayland compositor, load `lui/wayland`, `lui/demo`, and
  `tests/wayland.lisp` to exercise native pointer callbacks, keyboard repeat,
  modifier changes, cancellation, and delivery through the shared frame loop.
- After loading `lui/cocoa`, load `tests/cocoa.lisp` for portable SBCL ABI,
  UTF-8, event-routing, callback-safety, and floating-point-boundary checks.
  On Linux, this also compiles a test-only Objective-C ABI double with `cc`
  (override with `CC`) and tests the empty-stacktrace guard in an isolated
  subprocess. The fixture checks null/empty/nonempty traces, restoration after
  errors/nonlocal exits, ownership cleanup, and native callback FP settings.
  It is never linked into applications or loaded into the AppKit test process.
  On macOS it additionally runs AppKit selector and shared-demo smoke tests;
  that branch has not been executed here. Cocoa masks floating-point traps
  during native initialization, event processing, cleanup, and callbacks,
  then restores the caller's complete floating-point settings on exit.

| Area | Verified evidence |
| --- | --- |
| Portable core | SBCL, CLISP, ECL, and JSCL: core layout plus widget, editing, tab, hover, and focus checks |
| uncursed terminal | SBCL: Historical renderer/I/O comparisons reconstruct incremental output and compare styled cells; shared layout/widgets/examples remain current. Input, fragmented Unicode/escape sequences, mouse, resize, cleanup and redirected-input fallback also pass. Other implementations unverified on this branch |
| HTML | Chromium integration tests: interaction, composition/lifecycle, resizing and teardown |
| X11/GLX | Real-window tests of OpenGL rendering, input/resize, glass frost and clipboard behavior |
| EGL/OpenGL | Offscreen shared-demo rendering, glass shader, pixel readback, and GL error checks |
| Wayland | Restored libwayland backend; prior SBCL, CLISP, ECL compositor tests covered gallery frames, pointer callbacks and keyboard repeat/modifiers/cancellation |
| Win32 | Windows SBCL under Wine: outline holes, alpha, clipping, input, resizing, and filtered blur |
| Cocoa | ABI/callback/input/FP and isolated empty-stacktrace guard tests passed on Linux SBCL; AppKit runtime unverified |

The portable core and native backends target Common Lisp implementations generally;
Cocoa deliberately uses SBCL. The verified combinations above are narrower than
that portability goal. Native IME and clipboard support remain incomplete,
Wayland text-input/IME protocols need work, and native text is not
a complete shaping engine. Cocoa runtime behavior still needs macOS validation.
Performance tuning and broader platform/implementation coverage remain open.

## Source organization

Each core source file owns one package. Filenames match the package after removing
its `lui.` namespace and converting dots to hyphens; numeric, `backend-`, and
`backend-common-` prefixes describe load order or source organization.
The public `lui` package lives in `07-lui.lisp`.

The portable sources are numbered in dependency order:

- `01-fn.lisp`, `02-conditions.lisp`, `03-text.lisp`: typed declarations,
  documented conditions, and text wrapping.
- `04-layout.lisp`, `05-frame.lisp`: layout solving and frame state.
- `06-widgets.lisp`, `07-lui.lisp`, `08-interaction.lisp`: controls, application
  declarations, and input handling.
- `09-glass.lisp` through `13-garnet.lisp`: dependency-free toolkit definitions.
- `paint-<toolkit>.lisp`: graphical painters and geometry registrations for each
  built-in toolkit, loaded after the shared renderer. Backends do not select
  painters by toolkit name. Custom toolkits register their own callbacks.
  `lui:renderer-backdrop-effect` is an optional renderer callback taking a box,
  corner radius, and blur radius; any toolkit can use it before painting a tint.
- `14-debug.lisp`: optional layout debugger, loaded by `lui/debug`.

Platform backends live in `src/backend-<platform>.lisp` and may group related
packages in one file. Wayland includes its protocol package.
`backend-common.lisp` contains the font and drawing packages;
`backend-common-gl.lisp` provides shared OpenGL rendering.
`backend-common-web.lisp` groups browser input and window handling.
`backend-host.lisp` selects the native host backend. ASDF system names are
unchanged, and the dependency-free core does not load backend files.

`backend-ecl-emscripten.lisp` owns the `lui.ecl-emscripten` bridge package;
its C/JavaScript support lives in `scripts/ecl-web.c` and `scripts/ecl-web.js`.
Both web builders load the same numbered core and shared browser sources.

Tests use the `lui.tests.` namespace, and gallery examples use `lui.example.`.
For example, `tests/core.lisp` owns `lui.tests.core`, and `examples/demo.lisp`
owns `lui.example.demo`. Script packages likewise follow their filenames.

## Conventions

One package per core source file; backend files may group related packages.
Implementation packages may use `:use`. Demos and
examples use only Common Lisp and qualify their LUI API references. Other external
symbols are qualified or explicitly imported. Data uses `defstruct`, with typed
slots and functions through `lui.fn`, adapted from `open-orders`. Normal Lisp code wraps at
78 columns; LOOP clauses use keyword symbols.

Run `make lint` with Mallet installed. The runner normalizes typed `fn` headers
into `defun` headers in temporary copies so Mallet can inspect their bodies.
It runs strict rules plus complexity, function-length, and missing-docstring
checks, and fails on informational findings as well as warnings. Only
`no-package-use` is disabled for the internal-package convention. The JSON
report is written to `build/logs/mallet-normalized.json`.

### Error conditions

Explicit LUI failures use documented `define-condition` types exported by `lui`:

- `lui-error` is the common base, inheriting `simple-error` diagnostic formatting.
  `error-operation` identifies the operation that failed.
- `configuration-error` reports unavailable backends, toolkits, palettes,
  controls, or rendering callbacks. Inspect `error-setting` and `error-value`.
- `backend-error` reports platform failures; `error-backend` identifies the backend.
- `font-error`, a backend-error subtype, adds `error-font-request` for the font
  family/weight request that could not be loaded.
- `frame-state-error` reports an operation that requires a completed frame.

For example, catch a configuration failure without intercepting unrelated errors:

```lisp
(handler-case
    (lui:run #'draw-application :backend :x11)
  (lui:configuration-error (condition)
    (format *error-output* "Missing ~S: ~S (~A)~%"
            (lui:error-setting condition)
            (lui:error-value condition)
            condition)))
```

Load or configure the missing capability before retrying. Backend cleanup still
runs when a condition unwinds through the application lifecycle. Invalid argument
assertions and errors raised by application callbacks retain their own condition
types; they are not indiscriminately wrapped as backend errors.

### macOS 13 menu-bar auto-hide crash

The supplied macOS log reaches the saved executable, then aborts in
`HIPrintBacktrace` / `MenuBarInstance::IsAutoShowHideAllowed` with an empty-array
`NSRangeException`. This matches the macOS auto-hide issue reported by
[Makie](https://github.com/MakieOrg/Makie.jl/issues/2629) and reproduced in a native
Cocoa application in [CPython's report](https://github.com/python/cpython/issues/101067).
The Cocoa runner now applies the same temporary empty-stacktrace guard used by
cc's RGFW test runner. It substitutes one diagnostic entry only when
`NSThread.callStackSymbols` returns an empty trace, preserves real traces, and
restores the original method when the runner exits. Menu-bar auto-hide can stay
enabled; LUI does not change system preferences. Floating-point traps are also
masked at Cocoa boundaries. Run `make test-macos` to verify the native runtime;
the log includes macOS and Lisp versions. The affected machine's user confirmed
that the demo now runs with auto-hide enabled (November 5, 2026); no new log was
provided. The initial reported speed was about 20 FPS.

Cocoa uses a double-buffered OpenGL view and the shared GL renderer. It
requests a zero swap interval. All interactive backends default to one idle
frame per second and a maximum of 240 active frames per second. Pass
`:min-fps 1 :max-fps 170` to `lui:run` or `lui:mount` to change them.
Input wakes the next frame, and animation deadlines can request faster redraws. When an
accelerated pixel format is unavailable, it reports a warning and draws with
AppKit. Run `make benchmark PLATFORM=cocoa BENCH_FRAMES=720 WARMUP=144`
to measure the Mac. Each BUDGET row counts frame intervals exceeding 1/170 s,
including input processing and presentation. Logs are written to `build/logs/`.

An earlier `Component "zpb-ttf" not found` error means the font dependency is not
installed or visible to ASDF; install/register it before building. A compiled
executable and passing Linux ABI checks do not establish a passing macOS runtime.


Use `(lui:date-picker)` for a date field with an owned value. Click anywhere
in the field to open the calendar, or type a date as MM/DD/YYYY. The widget
returns YYYY-MM-DD or NIL when cleared. The gallery’s Editing page includes
an example.

### Tables

`lui:cell` is a selectable text widget. Use it directly in a table row for a
text-only cell, or use `lui:table-cell` to group labels, buttons, editors, or
nested layouts in one column. All three table containers accept `lui:opt`
layout options, including expressions or stored option lists. Use `:column-gap`
on the table and `:column-span` on a cell; use NIL for default options.

```lisp
(lui:table (lui:opt :width (lui:grow) :column-gap (lui:units 1))
  (lui:table-row ()
    (lui:table-cell (lui:opt :column-span 2) (lui:label "Account")))
  (lui:table-row ()
    (lui:label "Name")
    (lui:table-cell ()
      (setf name (lui:text-field (lui:opt :id :name :value name))))))
```

Columns use the widest content across rows. Extra width is shared equally,
and narrow tables shrink columns proportionally before measuring row heights.
Short rows can omit trailing cells. Row spanning is currently unsupported.

Password fields use `(lui:text-field (lui:opt :password-p t))`.
Use `:value password` when your application model owns the string.
Built-in rendering, selection copying, accessibility text, and debugger values
show one `*` per character. This is display masking, not encrypted storage;
custom painters receive the original widget value.
