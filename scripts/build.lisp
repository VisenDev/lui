(defpackage #:%lui.build
  (:use #:cl))
(in-package #:%lui.build)

(load "scripts/setup.lisp")

(defvar *backend* (uiop:getenv "PLATFORM"))

(unless (member *backend* '("terminal" "x11" "wayland" "win32" "cocoa")
                :test #'string=)
  (error "Cannot save a native executable for platform ~S." *backend*))
(asdf:load-system (concatenate 'string "lui/" *backend*))
(defvar *demo* (or (uiop:getenv "LUI_DEMO") "demo"))
(asdf:load-system (concatenate 'string "lui/" *demo*))
(defvar *demo-package*
  (concatenate 'string "%LUI.EXAMPLE." (string-upcase *demo*)))

(defun main ()
  (let ((lui:*backend* (intern (string-upcase *backend*) :keyword)))
    (if (member "--smoke-test" (uiop:command-line-arguments) :test #'string=)
        (lui:run (uiop:symbol-call *demo-package* :make-demo)
                 :interactive nil)
        (uiop:symbol-call *demo-package* :main))))

(sb-ext:save-lisp-and-die (uiop:getenv "LUI_OUTPUT")
                        :toplevel #'main :executable t
                        :save-runtime-options t)
