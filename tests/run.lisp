(defpackage #:lui.tests.run
  (:use #:cl))

(in-package #:lui.tests.run)

;; Source-loading runner for implementations without a configured ASDF registry.

(dolist (file '("src/01-fn.lisp"
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
                "tests/support.lisp"
                "tests/core.lisp"))
  (load file))

(lui.tests.core:run-tests)

(load "tests/widgets.lisp")

(lui.tests.widgets:run-tests)

(load "tests/interaction.lisp")
(lui.tests.interaction:run-tests)

(load "examples/seven-model.lisp")
(load "src/14-debug.lisp")
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
