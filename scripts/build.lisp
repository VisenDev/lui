(defpackage #:lui.build
  (:use #:cl))
(in-package #:lui.build)

(load "scripts/setup.lisp")

(defvar *backend* (uiop:getenv "PLATFORM"))

(unless (member *backend* '("terminal" "x11" "wayland" "win32" "cocoa")
                :test #'string=)
  (error "Cannot save a native executable for platform ~S." *backend*))
(asdf:load-system (concatenate 'string "lui/" *backend*))
(load "examples/demo.lisp")

(defun main ()
  (let ((package "LUI.EXAMPLE"))
    (progv (list (find-symbol "*BACKEND*" "LUI"))
           (list (intern (string-upcase *backend*) :keyword))
      (if (member "--smoke-test" (uiop:command-line-arguments)
                  :test #'string=)
          (uiop:symbol-call :lui :run
                           (symbol-function (find-symbol "DRAW" package))
                           :interactive nil)
          (uiop:symbol-call package :main)))))

(sb-ext:save-lisp-and-die (uiop:getenv "LUI_OUTPUT")
                        :toplevel #'main :executable t
                        :save-runtime-options t)
