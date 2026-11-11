(defpackage #:lui.build.web
  (:use #:cl))

(in-package #:lui.build.web)

(jscl:compile-application
 '("src/fn.lisp" "src/web-js.lisp" "src/layout.lisp" "src/frame.lisp" "src/widgets.lisp"
   "src/app.lisp" "src/interaction.lisp"
   "src/glass.lisp" "src/motif.lisp" "src/desktop.lisp" "src/garnet.lisp"
   "src/text-wrap.lisp" "src/web-font.lisp" "src/draw.lisp" "src/text-selection.lisp" "src/paint-common.lisp"
   "src/paint-glass.lisp" "src/paint-motif.lisp" "src/paint-desktop.lisp" "src/paint-garnet.lisp" "src/web-input.lisp"
   "src/debug.lisp" "src/web.lisp"
   "examples/seven-model.lisp" "examples/seven-circles.lisp"
   "examples/seven-cells.lisp" "examples/seven.lisp"
   "examples/demo.lisp" "scripts/start-demo.lisp")
 "build/lui-web.js")
