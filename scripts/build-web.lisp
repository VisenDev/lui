(defpackage #:lui.build.web
  (:use #:cl))

(in-package #:lui.build.web)

(jscl:compile-application
 '("src/01-fn.lisp"
   "src/02-helpers.lisp"
   "src/03-layout.lisp"
   "src/04-frame.lisp"
   "src/05-widgets.lisp"
   "src/06-app.lisp"
   "src/07-interaction.lisp"
   "src/08-toolkits.lisp"
   "src/09-debug.lisp"
   "src/backend-common.lisp"
   "src/backend-web.lisp"
   "examples/seven-model.lisp" "examples/seven-circles.lisp"
   "examples/seven-cells.lisp" "examples/seven.lisp"
   "examples/demo.lisp" "scripts/start-demo.lisp")
 "build/lui-web.js")
