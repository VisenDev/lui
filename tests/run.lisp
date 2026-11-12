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
                "src/07-palette.lisp"
                "src/08-toolkit.lisp"
                "src/09-lui.lisp"
                "src/10-interaction.lisp"
                "src/11-glass.lisp"
                "src/12-motif.lisp"
                "src/13-macos.lisp"
                "src/14-qt.lisp"
                "src/15-garnet.lisp"
                "tests/support.lisp"
                "tests/core.lisp"))
  (load file))

(lui.tests.core:run-tests)

(load "tests/widgets.lisp")

(lui.tests.widgets:run-tests)

(load "tests/interaction.lisp")
(lui.tests.interaction:run-tests)

(load "examples/seven-model.lisp")
(load "src/16-debug.lisp")
(load "tests/debug.lisp")
(lui.tests.debug:run-tests)

(load "examples/seven-circles.lisp")
(load "examples/seven-cells.lisp")
(load "examples/seven.lisp")
(load "examples/demo.lisp")
(load "examples/manual-demo.lisp")
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
