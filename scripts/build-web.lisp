(defpackage #:lui.build.web
  (:use #:cl))

(in-package #:lui.build.web)

(jscl:compile-application
 '("src/fn.lisp" "src/layout.lisp" "src/frame.lisp" "src/widgets.lisp"
   "src/glass.lisp" "src/motif.lisp" "src/app.lisp" "src/web.lisp"
   "examples/demo.lisp" "examples/showcase.lisp" "scripts/start-demo.lisp")
 "build/lui-web.js")
