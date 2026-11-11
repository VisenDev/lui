(defpackage #:lui.tests.runner
  (:use #:cl))

(in-package #:lui.tests.runner)

;; Portable runner; :LUI-TEST-BUNDLE keeps the preloaded implementation intact.

#-lui-test-bundle
(dolist (file '("src/fn.lisp" "src/text-wrap.lisp" "src/layout.lisp" "src/frame.lisp"
                "src/widgets.lisp" "src/app.lisp" "src/interaction.lisp"
                "src/glass.lisp" "src/motif.lisp" "src/desktop.lisp"
                "src/garnet.lisp"))
  (load file))

(load "tests/support.lisp")
(load "tests/core.lisp")
(lui.tests:run-tests)

(load "tests/widgets.lisp")

(lui.tests.widgets:run-tests)

(load "tests/interaction.lisp")
(lui.tests.interaction:run-tests)

#-lui-test-bundle
(load "examples/seven-model.lisp")
#-lui-test-bundle
(load "src/debug.lisp")
(load "tests/debug.lisp")
(lui.tests.debug:run-tests)

#-lui-test-bundle
(load "examples/seven-circles.lisp")
#-lui-test-bundle
(load "examples/seven-cells.lisp")
#-lui-test-bundle
(load "examples/seven.lisp")
#-lui-test-bundle
(load "examples/demo.lisp")
(load "tests/gallery.lisp")
(lui.tests.gallery:run-tests)

(load "tests/seven-model.lisp")
(lui.tests.seven.model:run-tests)
(load "tests/seven.lisp")
(lui.tests.seven:run-tests)

(load "tests/seven-circles.lisp")
(lui.tests.seven.circles:run-tests)
(load "tests/seven-cells.lisp")
(lui.tests.seven.cells:run-tests)
