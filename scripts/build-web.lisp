(defpackage #:lui.build.web
  (:use #:cl))

(in-package #:lui.build.web)

(jscl:compile-application
 '("src/fn.lisp" "src/layout.lisp" "src/frame.lisp" "src/widgets.lisp"
   "src/glass.lisp" "src/motif.lisp" "src/garnet.lisp"
   "src/app.lisp" "src/debug.lisp" "src/web.lisp"
   "examples/seven-model.lisp" "examples/demo.lisp"
   "examples/seven-circles.lisp" "examples/seven-cells.lisp"
   "examples/seven.lisp" "scripts/start-demo.lisp")
 "build/lui-web.js")
