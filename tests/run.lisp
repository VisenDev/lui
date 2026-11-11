(defpackage #:lui.tests.runner
  (:use #:cl))

(in-package #:lui.tests.runner)

;; Source-loading runner for implementations without a configured ASDF registry.

(dolist (file '("src/01-fn.lisp"
                "src/02-helpers.lisp"
                "src/03-layout.lisp"
                "src/04-frame.lisp"
                "src/05-widgets.lisp"
                "src/06-app.lisp"
                "src/07-interaction.lisp"
                "src/08-toolkits.lisp"
                "tests/support.lisp"
                "tests/core.lisp"))
  (load file))

(lui.tests:run-tests)

(load "tests/widgets.lisp")

(lui.tests.widgets:run-tests)

(load "tests/interaction.lisp")
(lui.tests.interaction:run-tests)

(load "examples/seven-model.lisp")
(load "src/09-debug.lisp")
(load "tests/debug.lisp")
(lui.tests.debug:run-tests)

(load "examples/seven-circles.lisp")
(load "examples/seven-cells.lisp")
(load "examples/seven.lisp")
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
