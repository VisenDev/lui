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
  fields, and styled layout panels. Collections share interaction logic.
- Stable IDs, pointer capture, release activation, forward keyboard focus, and
  editable values. Widgets return current-frame values and activation results.

Pass appearance options to individual widgets or dynamically bind
`lui.glass:*defaults*` / `lui.motif:*defaults*` for a group. Options include
foreground/background, radius, frost, opacity, accent, and font size. Native
widgets also support a custom painter callback. The optional
[showcase](examples/showcase.lisp) demonstrates panels and mixed collections;
it does not replace the shared demo.

## Make commands

The Makefile needs GNU Make and Python 3 for build/test tooling; the Lisp default
is SBCL. Backend dependencies and display requirements still apply. Run from the
repository directory:

```sh
make test                    # Core tests plus the detected platform's checks
make demo                    # Shared examples/demo.lisp
make example                 # Alias for demo
make showcase                # Optional style showcase
```

`PLATFORM=auto` selects Windows on Windows, Cocoa on macOS, then Wayland when
`WAYLAND_DISPLAY` is set, X11 when `DISPLAY` is set, or terminal otherwise.
Selection uses the environment; it does not start a display server. Tests run
core checks, native font/painter checks for graphical native platforms, and the
selected backend's tests. Each stage prints progress and PASS/FAIL results;
timestamped platform logs, including test output and the final result, go in
`build/logs/`. Failed stages make `make test` fail.

Override the selection or tool commands as needed:

```sh
make test PLATFORM=core
make test PLATFORM=terminal LISP=clisp LISP_KIND=clisp
make demo PLATFORM=x11
make showcase PLATFORM=web JSCL=/path/to/jscl PORT=8080
make web-build JSCL=/path/to/jscl
```

`PLATFORM` accepts `terminal`, `x11`, `wayland`, `win32`, `cocoa`, `web`, `gl`,
`core`, and `native`; the last three are test-only. `LISP` is an executable path
or command prefix, and `LISP_KIND=sbcl|clisp|ecl` selects its command-line flags.
The POSIX terminal PTY harness launches the installed implementation named by
`LISP_KIND`; the X11 harness launches installed SBCL. Those subprocesses do not
use a custom `LISP` command. Raw-terminal PTY checks are skipped on Windows.

`JSCL` names a built JSCL checkout, defaulting to `~/clone/jscl`; browser builds
also need Node.js. Browser launches build both examples, print the local URL,
and serve on `PORT` (default 8000). Open the printed URL; showcase uses
`?example=showcase`. Stop the server with Ctrl-C. Browser tests additionally need
Playwright and Chromium.

For Windows SBCL under Wine, a configured installation can be selected with:

```sh
make test PLATFORM=win32 LISP='wine C:/sbcl/sbcl.exe --core C:/sbcl/sbcl.core'
```

Supply the appropriate existing `WINEPREFIX` and ASDF dependency configuration
for that Windows Lisp. The driver does not install Wine, Lisp, or dependencies.

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
`examples/showcase.lisp` can be loaded and run through
`lui.example.showcase:main` in the same way.

For a real POSIX terminal, load `lui/terminal` and select `:terminal`. Tab changes
focus; Enter activates; Space toggles buttons/checkboxes; arrows adjust sliders
or move the text cursor. Home, End, Delete, Backspace, Shift-arrows, and Ctrl-A
support editing. SGR mouse clicks, dragging, wheel scrolling, and terminal
resizing are supported. Ctrl-Q, Ctrl-C, or Ctrl-D exits. Terminal attributes,
mouse modes, cursor visibility, and the alternate screen are restored on exit
and Lisp errors. Other platforms and non-TTY input retain line input:
`:next`, an empty line to activate, text to edit, and `:quit`. Noninteractive
terminal output remains dependency-free. Cell widths approximate common CJK,
emoji, and combining marks; full grapheme handling is not implemented.

For the browser, use a built JSCL checkout:

```sh
mkdir -p build
node /path/to/jscl/dist/jscl-node.js scripts/build-web.lisp
cp /path/to/jscl/dist/jscl.js build/jscl.js
python3 -m http.server 8000
```

Open [the browser example](http://localhost:8000/examples/web.html). This compiles the same
`examples/demo.lisp`; it is not a separate browser application.

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
| Portable core | SBCL, CLISP, ECL, and JSCL: 31 core checks plus widget/scrolling checks |
| Raw terminal | SBCL, CLISP, ECL: real PTY input, Unicode, mouse, resize, and cleanup after normal exit/errors |
| HTML | Three Chromium integration tests: interaction, composition/lifecycle, resizing and teardown |
| X11/XRender | Two real-window tests, including native rendering, input/resize, convolution and fallback behavior |
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
