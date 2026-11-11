(defpackage #:lui.build.web
  (:use #:cl))

(in-package #:lui.build.web)

(jscl:compile-application
 '("src/01-fn.lisp"
   "src/02-conditions.lisp"
   "src/03-text.lisp"
   "src/04-layout.lisp"
   "src/05-frame.lisp"
   "src/06-widgets.lisp"
   "src/07-lui.lisp"
   "src/08-interaction.lisp"
   "src/09-glass.lisp"
   "src/10-motif.lisp"
   "src/11-macos.lisp"
   "src/12-qt.lisp"
   "src/13-garnet.lisp"
   "src/14-debug.lisp"
   "src/backend-common.lisp"
   "src/backend-common-web.lisp"
   "examples/seven-model.lisp" "examples/seven-circles.lisp"
   "examples/seven-cells.lisp" "examples/seven.lisp"
   "examples/demo.lisp" "scripts/start-demo.lisp")
 "build/lui-web.js")
