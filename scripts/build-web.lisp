(defpackage #:%lui.build.web
  (:use #:cl))

(in-package #:%lui.build.web)

(jscl:compile-application
 '("src/01-fn.lisp"
   "src/02-conditions.lisp"
   "src/03-text.lisp"
   "src/04-layout.lisp"
   "src/05-frame.lisp"
   "src/06-widgets.lisp"
   "src/07-palette.lisp"
   "src/08-toolkit.lisp"
   "src/09-lui.lisp"
   "src/10-interaction.lisp"
   "src/11-glass.lisp"
   "src/12-motif.lisp"
   "src/13-macos.lisp"
   "src/14-qt.lisp"
   "src/15-garnet.lisp"
   "src/16-debug.lisp"
   "src/backend-common.lisp"
    "src/paint-glass.lisp"
    "src/paint-motif.lisp"
    "src/paint-macos.lisp"
    "src/paint-qt.lisp"
    "src/paint-garnet.lisp"
   "src/backend-common-web.lisp"
   "examples/seven-model.lisp" "examples/seven-circles.lisp"
   "examples/seven-cells.lisp" "examples/seven.lisp"
   "examples/demo.lisp" "scripts/start-demo.lisp")
 "build/lui-web.js")
