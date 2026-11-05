(defpackage #:lui.tests.runner
  (:use #:cl))

(in-package #:lui.tests.runner)

;; Source-loading runner for implementations without a configured ASDF registry.

(dolist (file '("src/fn.lisp" "src/layout.lisp" "src/frame.lisp"
                "src/widgets.lisp" "src/glass.lisp" "src/motif.lisp"
                "src/app.lisp" "src/terminal.lisp" "tests/core.lisp"))
  (load file))

(lui.tests:run-tests)

(load "tests/widgets.lisp")

(lui.tests.widgets:run-tests)

(load "examples/demo.lisp")
(load "tests/gallery.lisp")
(lui.tests.gallery:run-tests)
