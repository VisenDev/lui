(defpackage #:%lui.build.docs (:use #:cl))
(in-package #:%lui.build.docs)

(load "scripts/setup.lisp")
(defparameter *platform* (uiop:getenv "PLATFORM"))
(asdf:load-system (concatenate 'string "lui/" *platform*))
(asdf:load-system "lui/demo")
(load "examples/docs.lisp")
(load "build/docs-data.lisp")

(defun main ()
  (let ((backend (intern (string-upcase *platform*) :keyword)))
    (if (member "--smoke-test" (uiop:command-line-arguments) :test #'string=)
        (lui:run (%lui.docs:make-docs) :backend backend :interactive nil)
        (%lui.docs:main :backend backend))))

(sb-ext:save-lisp-and-die (uiop:getenv "LUI_OUTPUT")
                          :toplevel #'main :executable t
                          :save-runtime-options t)
