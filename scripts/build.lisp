(defpackage #:lui.build
  (:use #:cl))
(in-package #:lui.build)

(load "scripts/setup.lisp")

(defvar *backend* (uiop:getenv "PLATFORM"))

(unless (member *backend* '("terminal" "x11" "wayland" "win32" "cocoa")
                :test #'string=)
  (error "Cannot save a native executable for platform ~S." *backend*))
(asdf:load-system (concatenate 'string "lui/" *backend*))
(asdf:load-system "lui/demo")

(defun main ()
  (let ((lui:*backend* (intern (string-upcase *backend*) :keyword)))
    (if (member "--smoke-test" (uiop:command-line-arguments) :test #'string=)
        (lui:run (lui.example.demo:make-demo) :interactive nil)
        (lui.example.demo:main))))

(sb-ext:save-lisp-and-die (uiop:getenv "LUI_OUTPUT")
                        :toplevel #'main :executable t
                        :save-runtime-options t)
