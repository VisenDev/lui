# LUI

An immediate-mode Common Lisp UI library, under construction. Source is in `src/`.
The portable core has no external dependencies. Native drawing uses CFFI and
zpb-ttf, with system rendering libraries. X11/XRender and JSCL HTML are now
implemented; the remaining native backends and full glass effects are in progress.

## Implemented

- A Clay-inspired layout core: rows/columns, fit/grow/fixed/percentage sizing,
  min/max bounds, padding, gaps, main/cross-axis alignment, and backend measurement.
- Width resolution, width-dependent text measurement, height resolution, then
  positioning. Percentage sizes exclude parent padding and main-axis child gaps.
  Unresolvable minimum/fixed-size overflow is preserved rather than violating bounds.
- Immediate-mode declarations with stable, globally unique IDs for interactive
  widgets; pointer capture, release activation, forward keyboard focus, and activation.
- Glass and Motif labels, buttons, checkboxes, sliders, and text fields share
  interaction logic, with terminal, HTML, and native graphical presentations.
- Clipping, scrolling, and floating elements share the layout engine.
- `lui:run` owns platform setup. The same `examples/demo.lisp` runs unchanged
  across backends; backend selection belongs in the launcher.
- Plain terminal frame output with word wrapping and explicit newline handling.
  This is a cell-string renderer, not a terminal event loop. Cell width currently
  assumes one character per cell; wide/combining Unicode handling remains outstanding.

## Run

From the repository directory:

```lisp
(require :asdf)
(asdf:load-asd (truename "lui.asd"))
(asdf:load-system "lui")
(asdf:test-system "lui")
(load "examples/demo.lisp")
(lui:run #'lui.example:draw :backend :terminal :interactive nil)
```

Tests can also be source-loaded with `sbcl --script tests/run.lisp`,
`clisp -q -q tests/run.lisp`, or `ecl -shell tests/run.lisp`.

For X11, load `lui/x11` and call the same `lui.example:main`. Set
`lui:*backend*` to select a loaded backend explicitly. Native dependencies must
be available through ASDF. For the browser, run JSCL on
`scripts/build-web.lisp`, copy its `dist/jscl.js` to `build/jscl.js`, and open
`examples/web.html`. This compiles the same shared example, not a browser fork.

The portable terminal runner currently accepts lines: `:next` moves focus,
an empty line activates, text edits the focused field, and `:quit` exits.
Raw terminal input remains planned.

## Frame contract

`with-frame` executes the application body once and returns its solved root.
Rows and columns declare temporary layout elements. Button calls return activation
from events routed against the previous completed layout. IDs use `equal`; use
stable symbols, strings, or compound IDs, and do not mutate IDs after declaration.
Duplicate non-NIL IDs are errors. Pointer events on a resized frame are ignored
until fresh geometry exists. Removed widgets lose focus/capture. An aborted frame
invalidates geometry. Applications own their domain state.

Backends provide `(widget available-content-width) -> width, height` measurement;
NIL width requests intrinsic measurement. Value widgets return the new value and a changed flag.
A leaf measurer must return nonnegative dimensions. Layout containers and measured
leaves are separate: do not attach children to a measured leaf. Layout structs are
frame-local and should not be mutated after completion. Temporary storage currently
allocates per frame; pooling is deferred until measurement justifies it.

## Next stages

- Richer native input, terminal raw mode, and additional widgets.
- Win32 and SBCL Cocoa adapters; Wayland with EGL/OpenGL.
- XRender blur, native input methods, clipboard, and rendering performance.
- Broader browser tests for resizing, composition, and DOM lifecycle.
- GPU rendering using the shared zpb-ttf outline path.
- Actual glass effects, per-backend capabilities, and implementation compatibility tests.

No software pixel renderer is planned. Vulkan is a later optional renderer.
The portable core targets Common Lisp implementations; only Cocoa may require SBCL.
Core tests pass on SBCL, CLISP, ECL, and JSCL. Native FFI testing currently
covers SBCL/X11; other combinations remain to be validated.

## Conventions

One package per source file; internal packages are used explicitly. External
symbols are qualified or explicitly imported. Data uses `defstruct`, with typed
slots and typed functions through `lui.fn`, adapted from `open-orders`.

## Validation

Run `mallet src --strict --disable no-package-use --disable error-without-custom-condition`.
These two style rules conflict with the project's internal-package `:use` convention
and its struct-only policy (custom conditions introduce condition classes).
