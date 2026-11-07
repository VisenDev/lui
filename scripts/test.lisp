(defpackage #:lui.test-runner
  (:use #:cl))
(in-package #:lui.test-runner)

(load "scripts/setup.lisp")

(let ((test (uiop:getenv "LUI_TEST")))
  (cond
    ((string= test "core") (asdf:test-system "lui/core"))
    ((string= test "native") (asdf:test-system "lui/native/tests"))
    ((string= test "terminal") (asdf:test-system "lui/terminal"))
    ((member test '("wayland" "win32" "cocoa" "gl") :test #'string=)
     #+darwin
     (when (string= test "cocoa")
       (uiop:run-program '("sw_vers") :output t)
       (format t "Lisp: ~A ~A~%" (lisp-implementation-type)
               (lisp-implementation-version)))
     (asdf:load-system (concatenate 'string "lui/" test))
     (asdf:load-system "lui/demo")
     (when (string= test "wayland") (load "tests/support.lisp"))
     (load (format nil "tests/~A.lisp" test)))
    (t (error "Unknown test platform ~S." test))))
