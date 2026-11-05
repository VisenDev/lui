# LUI

LUI is an immediate-mode Common Lisp UI library under development. The same
[shared example](examples/demo.lisp) runs unchanged in a browser, native windows,
and a terminal. Applications own their state; `lui:run` owns the backend lifecycle.

The portable core has no external dependencies. Native graphical backends add
CFFI and zpb-ttf, plus operating-system rendering libraries. Browser output uses
JSCL and native HTML controls, with browser DOM text measurement rather than
Canvas. There is no application software pixel renderer; Vulkan remains future
work.

## Layout and widgets

- Rows, columns, fit/grow/fixed/percentage sizing, minimum/maximum bounds, padding,
  gaps, alignment, clipping, scrolling, and floating elements.
- Width-dependent text wrapping: horizontal sizing precedes measurement of height
  and vertical positioning. Percentage sizes exclude padding and inter-child gaps.
  Fixed sizes and minimum bounds may overflow instead of silently shrinking.
- Glass and Motif collections with labels, buttons, checkboxes, sliders, text
  fields, tabs, and styled layout panels. Collections share interaction logic.
- Stable IDs, pointer capture, release activation, hover feedback, and keyboard
  navigation. Button clicks preserve existing keyboard focus; focus rings appear
  for keyboard navigation. Text fields acquire editing focus on click.
- Tabs support Left/Right wrapping and Home/End navigation, skipping disabled
  tabs. Widgets return current-frame values and activation results.

Pass appearance options to individual widgets or dynamically bind
`lui.glass:*defaults*` / `lui.motif:*defaults*` for a group. Options include
foreground/background, radius, frost, opacity, accent, and font size. Native
widgets also support a custom painter callback.

There is one [demo gallery](examples/demo.lisp), with Controls, Editing, Layout,
Scroll, and Styles pages. Its Glass/Motif selector changes the collection for
the whole gallery, so each page uses one toolkit consistently. The gallery also
displays FPS and average frame time on graphical backends; these include backend
pacing. The terminal labels its event-driven rendering instead.

## Make commands

The Makefile uses GNU Make, Bash, and SBCL. Backend dependencies and display
requirements still apply. Python 3 runs browser serving and the existing
terminal/X11/browser integration tests; `cloc` is needed for source reports and
the test/benchmark targets. Run from the repository directory:

```sh
make build                   # Save the native demo executable
make demo                    # Build and run the same executable
make demo RUN_ARGS=--smoke-test
make test                    # Platform checks, executable smoke test, and log
make loc                     # cloc src, by file
make benchmark               # Throughput/frame-time measurements and log
```

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
spread across both toolkits and all five pages (24 measured frames per case by
default). `BENCH_FRAMES` must be at least 10 and `WARMUP` nonnegative. Reports
include per-toolkit/page FPS, mean, median, 95th-percentile, and maximum frame
time, plus timer/settings information.

Windowed native results include event-loop, window-system, and presentation
pacing; browser results measure paced requestAnimationFrame intervals. The
`core`/`terminal` benchmark measures layout and terminal string rendering; `gl`
measures an offscreen pipeline with `glFinish`. These paths should not be
compared as equivalent screen FPS. Compare logged platform/settings and matching
toolkit/page rows:

```sh
make benchmark PLATFORM=core BENCH_FRAMES=240 WARMUP=30
make benchmark PLATFORM=gl
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
(asdf:load-system "lui")
(asdf:test-system "lui")
(load "examples/demo.lisp")
(lui:run #'lui.example:draw :backend :terminal :interactive nil)
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

| ASDF system | Purpose and system requirements |
| --- | --- |
| `lui` | Dependency-free layout, widgets, and portable terminal output |
| `lui/terminal` | Optional raw POSIX terminal input through CFFI and libc |
| `lui/native` | Shared native measurement and outline painting; CFFI, zpb-ttf |
| `lui/x11` | X11 and XRender libraries, an X display |
| `lui/gl` | EGL/OpenGL renderer; EGL and compatibility OpenGL libraries |
| `lui/wayland` | Wayland client/EGL, xkbcommon, EGL/OpenGL, a Wayland compositor |
| `lui/win32` | Windows User32, GDI32, Kernel32, and GDI+ |
| `lui/cocoa` | macOS AppKit and Objective-C runtime; SBCL only |

For a native window, load its system and select its backend:

```lisp
(asdf:load-system "lui/x11")
(let ((lui:*backend* :x11))
  (lui.example:main))
```

Use `lui/wayland` with `:wayland`, `lui/win32` with `:win32`, or `lui/cocoa` with
`:cocoa` in the same launcher. `lui:available-backends` lists loaded backends.
Width and height are backend coordinates; omit them for backend defaults.

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
lines where supported; there is no command-history model. Browsers retain native
DOM inputs and composition behavior. Modifier reporting differs between terminal
emulators, so Ctrl-Shift-A requires a distinguishable terminal key sequence.

For a real POSIX terminal, load `lui/terminal` and select `:terminal`. Tab changes
focus; Enter activates; Space activates buttons/tabs or toggles checkboxes.
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
| HTML | Browser backdrop filtering, tint, rounded borders, and native controls |
| EGL/OpenGL / Wayland | Backdrop sampling, blur, and an edge refraction approximation |
| XRender | Server-side Gaussian convolution, tint, and rim; no refraction. A warning identifies servers without convolution support, which fall back to tint/rim. |
| Win32 | Native filtered downsample/upsample backdrop blur, tint, and rim; no refraction |
| Cocoa | Whole-window AppKit material, with widget tint and rounded outlines; no per-widget backdrop blur |
| Terminal | Cell text and square/rounded panel outlines |

These effects are approximations, not identical implementations of a single
physical glass model.

## Local performance evidence

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
| Headless Chromium, per toolkit/page | 60.00–60.02 | 16.662–16.667 ms | 16.7–16.8 ms |

The matched profiled Wayland runs show about a 21× throughput improvement;
the unprofiled result confirms the post-optimization timing. Wayland includes
compositor pacing. Chromium's requestAnimationFrame intervals are paced at
60 Hz in this setup, while offscreen GL has no screen presentation limit.
These numbers do not rank the backends against one another.

Recorded local evidence is in generated logs under `build/`:
`profile-wayland-before.log`, `profile-wayland-after.log`,
`benchmark-wayland-after.log`, `benchmark-gl-after.log`, and
`benchmark-web-baseline.log`. Logs include the workload and timing settings;
new `make benchmark` runs also record the current cloc source report.

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
- After loading `lui/gl` and `examples/demo.lisp`, load `tests/gl.lisp` for the
  offscreen EGL/OpenGL smoke test. Ensure `build/` exists.
- With a Wayland compositor, load `lui/wayland`, the shared demo, and
  `tests/wayland.lisp` to exercise native pointer callbacks, keyboard repeat,
  modifier changes, cancellation, and delivery through the shared frame loop.
- After loading `lui/cocoa`, load `tests/cocoa.lisp` for portable SBCL ABI,
  UTF-8, event-routing, callback-safety, and floating-point-boundary checks.
  On macOS it additionally runs AppKit selector and shared-demo smoke tests;
  that branch has not been executed here. Cocoa masks floating-point traps
  during native initialization, event processing, cleanup, and callbacks,
  then restores the caller's complete floating-point settings on exit.

| Area | Verified evidence |
| --- | --- |
| Portable core | SBCL, CLISP, ECL, and JSCL: core layout plus widget, editing, tab, hover, and focus checks |
| Raw terminal | SBCL, CLISP, ECL: real PTY input, Unicode, mouse, resize, and cleanup after normal exit/errors |
| HTML | Chromium integration tests: interaction, composition/lifecycle, resizing and teardown |
| X11/XRender | Real-window tests of native rendering, input/resize, convolution and fallback behavior |
| EGL/OpenGL | Offscreen shared-demo rendering, glass shader, pixel readback, and GL error checks |
| Wayland | SBCL, CLISP, ECL: shared-demo compositor frames, pointer callbacks, repeat timing/modifiers/cancellation |
| Win32 | Windows SBCL under Wine: outline holes, alpha, clipping, input, resizing, and filtered blur |
| Cocoa | Source/test compilation and seven ABI/callback/input/FP test groups passed on Linux SBCL; AppKit runtime unverified |

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
