(defpackage #:lui.tests.cocoa
  (:use #:cl #:lui #:lui.frame #:lui.layout))
(in-package #:lui.tests.cocoa)

(unless (and (member :darwin *features*) (member :sbcl *features*))
  (error "Cocoa runtime tests require SBCL on macOS."))

(let ((frames 0))
  (let ((context
          (run (lambda ()
                 (incf frames)
                 (lui.example:draw))
               :backend :cocoa :interactive nil)))
    (assert (= frames 1))
    (assert (plusp (box-width (element-box (context-root context)))))
    (assert (plusp (box-height (element-box (context-root context)))))))
(format t "Cocoa native shared demo smoke test passed.~%")
