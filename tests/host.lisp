(defpackage #:%lui.tests.host
  (:use #:cl))
(in-package #:%lui.tests.host)

;; No display is needed: exercise the aggregate system's automatic dispatch
;; with a registered terminal runner and an isolated backend registry.
(let ((lui::*backends* (make-hash-table :test 'eq))
      (lui:*backend* nil)
      (lui:%*default-backend-function* #'%lui.host::preferred-backend)
      (calls 0))
  (lui:register-backend
   :terminal (lambda (draw &rest options)
               (assert (equal (getf options :title) "Auto backend"))
               (incf calls)
               (funcall draw)))
  (assert (equalp #(:terminal) (lui:available-backends)))
  (assert (eq :terminal (%lui.host::preferred-backend)))
  (assert (eq :drawn (lui:run (lambda () :drawn) :title "Auto backend")))
  (assert (= calls 1)))
(format t "Automatic host backend dispatch passed.~%")
