;;; Isolated Linux test process: the fixture exports fake Objective-C symbols.
(load "scripts/setup.lisp")
(sb-alien:load-shared-object (first (uiop:command-line-arguments)))
(asdf:load-system "lui/cocoa")

(defpackage #:lui.tests.cocoa-stacktrace
  (:use #:cl #:lui.fn))
(in-package #:lui.tests.cocoa-stacktrace)

(fn trace-value ()
  (lui.cocoa::message lui.cocoa::object
                      (lui.cocoa::objc-class "NSThread") "callStackSymbols"))

(fn trace-count ((count integer) &optional null-p)
  (sb-alien:alien-funcall
   (sb-alien:extern-alien "test_trace"
     (function sb-alien:void sb-alien:unsigned-long sb-alien:int))
   count (if null-p 1 0)))

(fn restored-p ()
  (= 1 (sb-alien:alien-funcall
        (sb-alien:extern-alien "test_restored" (function sb-alien:int)))))

(fn drains ()
  (sb-alien:alien-funcall
   (sb-alien:extern-alien "test_drains" (function sb-alien:int))))

(fn check-cleanup ((before integer))
  (assert (restored-p))
  (assert (= (1+ before) (drains)))
  (assert (null lui.cocoa::*stacktrace-method*))
  (assert (null lui.cocoa::*stacktrace-placeholder*)))

(fn test-values-and-cleanup ()
  (let ((before (drains))
        (*error-output* (make-string-output-stream)))
    (trace-count 0)
    (assert (zerop (lui.cocoa::message sb-alien:unsigned-long
                                     (trace-value) "count")))
    (assert (eq :returned
                (lui.cocoa::call-with-stacktrace-guard
                 (lambda ()
                   (dolist (null-p '(nil t nil))
                     (trace-count 0 null-p)
                     (assert (= 1 (lui.cocoa::message sb-alien:unsigned-long
                                                     (trace-value) "count"))))
                   (assert lui.cocoa::*stacktrace-reported-p*)
                   (trace-count 5)
                   (let ((trace (trace-value)))
                     (assert (= 5 (lui.cocoa::message sb-alien:unsigned-long
                                                     trace "count")))
                     (assert (= (sb-sys:sap-int trace)
                                (sb-sys:sap-int
                                 (sb-alien:alien-funcall
                                  (sb-alien:extern-alien "test_original"
                                    (function lui.cocoa::object)))))))
                   (let ((entered nil))
                     (assert (eq :blocked
                                 (handler-case
                                     (lui.cocoa::call-with-stacktrace-guard
                                      (lambda () (setf entered t)))
                                   (error () :blocked))))
                     (assert (null entered)))
                   :returned))))
    (check-cleanup before)
    (let* ((diagnostic (get-output-stream-string *error-output*))
           (at (search "placeholder" diagnostic)))
      (assert at)
      (assert (null (search "placeholder" diagnostic :start2 (1+ at))))))
  (dolist (exit '(:throw :error))
    (let ((before (drains)) (entered nil))
      (assert (eq :escaped
                  (catch 'leave
                    (handler-case
                        (lui.cocoa::call-with-stacktrace-guard
                         (lambda ()
                           (setf entered t)
                           (ecase exit
                             (:throw (throw 'leave :escaped))
                             (:error (error "Guard body failed.")))))
                      (error () :escaped)))))
      (assert entered)
      (check-cleanup before))))

(fn test-callback-float-mode ()
  (let ((original (sb-int:get-floating-point-modes))
        (observed 0)
        (traps '(:invalid :divide-by-zero :overflow :underflow :inexact)))
    (unwind-protect
         (sb-alien:with-alien-callable
             ((observe sb-alien:int ()
                       (assert (null (intersection
                                      traps (getf
                                             (sb-int:get-floating-point-modes)
                                             :traps))))
                       (incf observed)
                       (sb-int:set-floating-point-modes :rounding-mode :zero)
                       1))
           (sb-alien:alien-funcall
            (sb-alien:extern-alien "test_observer"
              (function sb-alien:void lui.cocoa::object))
            (sb-alien:alien-sap observe))
           (sb-int:set-floating-point-modes
            :traps traps :current-exceptions nil :accrued-exceptions nil)
           (let ((before (sb-int:get-floating-point-modes)))
             (trace-count 3)
             (lui.cocoa::call-with-stacktrace-guard
              (lambda () (trace-value)))
             (assert (= observed 1))
             (assert (equal before (sb-int:get-floating-point-modes)))))
      (sb-alien:alien-funcall
       (sb-alien:extern-alien "test_observer"
         (function sb-alien:void lui.cocoa::object)) (sb-sys:int-sap 0))
      (apply #'sb-int:set-floating-point-modes original))))

(test-values-and-cleanup)
(test-callback-float-mode)
(format t "Cocoa empty-stack guard values, cleanup, and callback FP passed.~%")
