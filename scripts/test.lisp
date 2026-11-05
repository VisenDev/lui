(defpackage #:lui.test-runner
  (:use #:cl))
(in-package #:lui.test-runner)

(load "scripts/setup.lisp")

(let ((test (uiop:getenv "LUI_TEST")))
  (cond
    ((string= test "core") (asdf:test-system "lui"))
    ((string= test "native") (asdf:test-system "lui/native/tests"))
    ((member test '("wayland" "win32" "cocoa" "gl") :test #'string=)
     (asdf:load-system (concatenate 'string "lui/" test))
     (load "examples/demo.lisp")
     (load (format nil "tests/~A.lisp" test)))
    (t (error "Unknown test platform ~S." test))))
