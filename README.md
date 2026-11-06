# LUI

LUI is an immediate-mode Common Lisp UI library under development. The same
[shared example](examples/demo.lisp) runs unchanged in a browser, native windows,
and a terminal. Applications own their state; `lui:run` owns the backend lifecycle.

Load the library with `(asdf:load-system "lui")` to register the backends for
your host. Use `lui/core` for the portable core with no external dependencies.
Native graphical backends add CFFI, zpb-ttf, and system rendering libraries. Browser output uses
JSCL and one high-DPI Canvas 2D surface per window. There is no application software pixel renderer; Vulkan remains future
work.

## Layout and widgets

- Rows, columns, fit/grow/fixed/percentage sizing, minimum/maximum bounds, padding,
  gaps, alignment, clipping, scrolling, and floating elements.
- Width-dependent text wrapping: horizontal sizing precedes measurement of height
  and vertical positioning. Percentage sizes exclude padding and inter-child gaps.
  Fixed sizes and minimum bounds may overflow instead of silently shrinking.
- Glass, Motif, and Garnet toolkits with labels, buttons, checkboxes, sliders, text
  fields, tabs, single-selection rows, progress gauges, circle canvases, and
  styled layout panels. Toolkits share interaction logic.
- Stable IDs, pointer capture, release activation, hover feedback, and keyboard
  navigation. Button clicks preserve existing keyboard focus; focus rings appear
  for keyboard navigation. Text fields acquire editing focus on click.
- Tabs support Left/Right wrapping and Home/End navigation, skipping disabled
  tabs. Widgets return current-frame values and activation results.

A draw function describes the current frame. Give interactive controls stable
IDs so a release, keypress, or edit can find the same control on the next
frame. For example, this entire application runs with any loaded backend:

```lisp
(defun counter (&optional (toolkit :glass))
  (let ((count 0))
    (lui:run
     (lambda ()
       (lui:with-toolkit (toolkit)
         (lui:panel (lui:opt :padding (lui:units 1))
           (when (lui:button :increment "Count")
             (incf count))
           (lui:label (format nil "Count: ~D" count))))))))
```

`with-toolkit` evaluates its argument once and scopes ordinary widget calls.
`panel` attaches its body as children; the layout macros `lui.frame:row` and
`lui.frame:column` group children without painting a panel. Buttons return
activation; fields, sliders, and checkboxes return the current value and a
second value indicating a change. Store application values outside the draw
function. The library keeps focus, capture, and caret state between frames.

Use the optional final `lui:opt` form for widget customization. Its keyword
lambda list is visible to SLIME; layout keys such as `:gap` apply to panels,
whereas `:step` configures a slider. To change toolkit defaults, bind
`lui.glass:*defaults*`, `lui.motif:*defaults*`, or `lui.garnet:*defaults*` for a
group. Options include foreground/background, radius, frost, opacity, accent,
font size, `:font-family` (`:sans-serif` or `:monospace`), and `:font-weight`
(`:normal` or `:bold`). Native
widgets also support a custom painter callback.

User widgets can be ordinary functions composed from these controls. For
example, this adds a selectable badge to a toolkit and inherits the rest
of its controls from Motif:

```lisp
(defun badge (id text &optional options)
  (lui:button id text (append options (lui:opt :foreground "#105030"))))

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
For custom drawing, `:painter` takes the shared graphical renderer and element
on desktop and web. `:terminal-label` takes a widget and returns its text.

There is one [demo gallery](examples/demo.lisp), with Controls, Editing, Layout,
Scroll, Styles, and 7GUIs pages. Its Glass/Motif/Garnet selector changes the toolkit for
the whole gallery, so each page uses one toolkit consistently. Style Preview
buttons select an interactive sample. Motif uses an opaque matching background,
beveled checkboxes, and visually distinct disabled buttons. Garnet uses bold
monospaced text, black hairlines, checker stipples, hard offset shadows, and X
checkboxes inspired by the original Garnet gadgets. Window backgrounds remain
opaque; Glass translucency composites within the application. The gallery also
displays FPS and average frame time on graphical backends; these include backend
pacing. The terminal labels its event-driven rendering instead. Its sliders have tracks
and thumbs, colors distinguish selection from pointer hover, and text/clip edges
share cell rounding. Raw-terminal output uses ANSI colors; plain snapshots remain
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
HTML copy, run `make docs-html`. It embeds the JSCL runtime and application
in a single file. Run `make docs-pages` to build the HTML if needed and copy
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
spread across all three toolkits, five gallery pages, and every 7GUIs task
(36 cases; 6–7 measured frames per case by default). Use 720 frames and 144
warmup frames for 20 samples per case. `BENCH_FRAMES` must be at least 36
and `WARMUP` nonnegative. Reports
include per-toolkit/page FPS, mean, median, 95th-percentile, and maximum frame
time, plus timer/settings information.

Windowed native results include event-loop, window-system, and presentation
pacing; browser results actively redraw the application and measure completed
frames plus application/layout/drawing work, rather than idle animation ticks. The
`core`/`terminal` benchmark measures layout and terminal string rendering; `gl`
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

## Install and run

Start a Common Lisp implementation in the repository directory:

```lisp
(require :asdf)
(asdf:load-asd (truename "lui.asd"))
(asdf:load-system "lui/demo")
(asdf:test-system "lui")
(lui:run (lui.example:make-demo) :backend :terminal :interactive nil)
```

To make LUI discoverable from other directories, put the following in
`~/.config/common-lisp/source-registry.conf.d/lui.conf`, substituting the actual
absolute repository path:

```lisp
(:directory "/absolute/path/to/lui/")
```

Optional dependencies must also be discoverable through ASDF. If using
Quicklisp, `(ql:quickload '("cffi" "zpb-ttf"))` installs the Lisp dependencies for
native graphics; raw terminal input needs only CFFI. No native rendering library
is bundled. A TrueType font is required for native graphics: common system paths
are tried automatically, or set `lui.font:*font-path*` after loading the backend.
To use an installed or bundled font family, set these variables **before**
opening the window. For a saved executable, set `LUI_FONT` to the base TTF
path or `LUI_FONT_DIR` to an additional search directory at launch time.
`*font-directories*` lists directory pathnames (or strings
ending in a slash); `*font-names*` maps each family and weight to candidate
filenames. Lookup tries each filename across those directories in order.
For example, to search your own directory first:

```lisp
(push #p"/opt/my-app/fonts/" lui.font:*font-directories*)
(push '((:sans-serif :normal) "MySans.ttf") lui.font:*font-names*)
```

An exact face override takes precedence over directory search, and
`*font-path*` takes precedence for the base face.
Additional faces are cached and closed with the base font. Override their paths
with `lui.font:*font-paths*`, for example
`'(((:monospace :bold) . "/path/to/Mono-Bold.ttf"))`. Browser measurement and
painting use the same CSS family and weight.

| ASDF system | Purpose and system requirements |
| --- | --- |
| `lui` | Core and the backends supported on the host |
| `lui/core` | Dependency-free layout, widgets, and portable terminal output |
| `lui/terminal` | Optional raw POSIX terminal input through CFFI and libc |
| `lui/native` | Shared native measurement and outline painting; CFFI, zpb-ttf |
| `lui/pdf` | Single-page PDF output through cl-pdf and the native font renderer |
| `lui/x11` | Xlib and system OpenGL, an X display with GLX |
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
  (lui.example:main))
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
(lui.pdf:render-pdf (lambda () (lui:label "Quarterly report"
                                          (lui:opt :foreground "#17212b")))
                    #p"report.pdf" :width 595 :height 842 :background "#ffffff")
```

For existing `lui:run` callers, bind `lui.pdf:*output*` (default `lui.pdf`) and
pass `:backend :pdf`. Run `(asdf:test-system "lui/pdf")` to test the backend.

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

Run `make terminal-demo` for a real POSIX terminal, or load `lui/terminal` and
select `:terminal`. Tab and Shift-Tab move focus forward and backward. Enter and
Space activate buttons/tabs or toggle checkboxes; Space inserts text in editors.
Arrows adjust sliders, navigate tabs, or move the text cursor. SGR mouse clicks,
dragging, wheel scrolling, and terminal resizing are supported. Ctrl-Q or Ctrl-C
exits; Ctrl-D deletes text. Terminal attributes, mouse modes, cursor visibility,
and the alternate screen are restored on exit and Lisp errors. Other platforms
and non-TTY input retain line input: `:next`, an empty line to activate, text to
edit, and `:quit`. Noninteractive terminal output remains dependency-free. Cell
widths approximate common CJK, emoji, and combining marks; full grapheme handling
is not implemented.

For the browser, `make web-demo JSCL=/path/to/jscl` compiles and serves the
same `examples/demo.lisp`. Open the root URL printed by the server;
it is not a separate browser application. `make web-build` builds the JavaScript
without launching a server.

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
The browser draws custom widgets with their shared toolkit painter. A single
hidden text field handles keyboard composition and exposes the focused label
and value. Screen readers currently lack a navigable tree of canvas widgets.

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
traversal. JSCL's generated generic slot checks are omitted for trusted internal
structures; native Lisp type declarations remain intact. Direct child traversal
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
(when (lui:button :debug "Show debugger")
  (lui.debug:set-enabled t))
```

Drag the debugger's left edge to resize its sidebar; the width persists.
Focus the separator and use Left/Right or Home/End to resize from the keyboard.
`lui.debug:state-width` can also set its optional width in LUI spacing units.
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
- `python3 tests/x11.py` requires an X display, SBCL, Pillow, and ImageMagick
  `import`, as well as the X11 backend dependencies.
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
| Raw terminal | SBCL, CLISP, ECL: real PTY input, Unicode, mouse, resize, and cleanup after normal exit/errors |
| HTML | Chromium integration tests: interaction, composition/lifecycle, resizing and teardown |
| X11/GLX | Real-window tests of OpenGL rendering, input/resize, glass frost and clipboard behavior |
| EGL/OpenGL | Offscreen shared-demo rendering, glass shader, pixel readback, and GL error checks |
| Wayland | SBCL, CLISP, ECL: shared-demo compositor frames, pointer callbacks, repeat timing/modifiers/cancellation |
| Win32 | Windows SBCL under Wine: outline holes, alpha, clipping, input, resizing, and filtered blur |
| Cocoa | ABI/callback/input/FP and isolated empty-stacktrace guard tests passed on Linux SBCL; AppKit runtime unverified |

The portable core and CFFI backends target Common Lisp implementations generally;
Cocoa deliberately uses SBCL. The verified combinations above are narrower than
that portability goal. Native IME and clipboard support remain incomplete,
Wayland text-input/IME protocols need work, and native text is not
a complete shaping engine. Cocoa runtime behavior still needs macOS validation.
Performance tuning and broader platform/implementation coverage remain open.

## Conventions

One package per source file; internal packages use `:use`, while external symbols
are qualified or explicitly imported. Data uses `defstruct`, with typed slots and
functions through `lui.fn`, adapted from `open-orders`. Normal Lisp code wraps at
78 columns; LOOP clauses use keyword symbols.

Run `mallet src --strict --disable no-package-use --disable error-without-custom-condition`.
The disabled rules conflict with the internal-package `:use` convention and the
struct-only policy: custom conditions introduce condition classes.

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
`:min-fps 1 :max-fps 170` to `lui:run` or `lui.web:mount` to change them.
Input wakes the next frame, and animation deadlines can request faster redraws. When an
accelerated pixel format is unavailable, it reports a warning and draws with
AppKit. Run `make benchmark PLATFORM=cocoa BENCH_FRAMES=720 WARMUP=144`
to measure the Mac. Each BUDGET row counts frame intervals exceeding 1/170 s,
including input processing and presentation. Logs are written to `build/logs/`.

An earlier `Component "zpb-ttf" not found` error means the font dependency is not
installed or visible to ASDF; install/register it before building. A compiled
executable and passing Linux ABI checks do not establish a passing macOS runtime.


Use `(lui:date-time-picker :appointment value (lui:opt :mode :datetime))`
for a calendar and 24-hour time picker. Store its returned ISO local value
(`YYYY-MM-DDTHH:MM`). Modes `:date` and `:time` return `YYYY-MM-DD` and
`HH:MM`. Invalid typed drafts stay editable while the last valid value is
retained. NIL starts an empty editor with the calendar at January 2000.
The gallery’s Editing page includes an example.

### Tables

`lui:cell` is a selectable text widget. Use it directly in a table row for a
text-only cell, or use `lui:table-cell` to group labels, buttons, editors, or
nested layouts in one column.

```lisp
(lui:table (:width (lui.layout:grow) :column-gap (lui:units 1))
  (lui:table-row ()
    (lui:table-cell (:column-span 2) (lui:label "Account")))
  (lui:table-row ()
    (lui:label "Name")
    (lui:table-cell ()
      (setf name (lui:text-field :name name)))))
```

Columns use the widest content across rows. Extra width is shared equally,
and narrow tables shrink columns proportionally before measuring row heights.
Short rows can omit trailing cells. Row spanning is currently unsupported.
