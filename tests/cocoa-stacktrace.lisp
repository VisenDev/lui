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

(fn counter ((which integer))
  (sb-alien:alien-funcall
   (sb-alien:extern-alien "test_counter"
     (function sb-alien:int sb-alien:int)) which))

(fn last-fill ()
  (sb-alien:alien-funcall
   (sb-alien:extern-alien "test_last_fill" (function lui.cocoa::object))))

(fn test-selector-cache ()
  (let ((before (counter 0)))
    (let ((lui.cocoa::*selectors* (make-hash-table :test 'equal)))
      (let ((first (lui.cocoa::selector "fixtureCacheSelector")))
        (assert (lui.cocoa::same-object-p
                 first (lui.cocoa::selector (copy-seq "fixtureCacheSelector"))))
        (assert (= (1+ before) (counter 0)))))
    (let ((lui.cocoa::*selectors* (make-hash-table :test 'equal)))
      (lui.cocoa::selector "fixtureCacheSelector")
      (assert (= (+ before 2) (counter 0)))))
  (let ((lui.cocoa::*selectors* nil) (before (counter 0)))
    (lui.cocoa::selector "fixtureCacheSelector")
    (lui.cocoa::selector "fixtureCacheSelector")
    (assert (= (+ before 2) (counter 0)))))

(fn test-text-path-cache ()
  (let* ((font (lui.font:open-font))
         (lui.cocoa::*app* (lui.cocoa::make-cocoa-app))
         (lui.cocoa::*selectors* (make-hash-table :test 'equal))
         (cache (lui.cocoa::cocoa-app-text-paths lui.cocoa::*app*))
         (builds (counter 1)) (retains (counter 2)) (releases (counter 3))
         (fills (counter 4)) (translates (counter 7)) (concats (counter 8))
         (color (symbol-function 'lui.cocoa::cocoa-color)))
    (unwind-protect
         (progn
           (lui.cocoa::cocoa-text font "AV" 10 20 "#000000")
           (let ((path (last-fill)) (moves (counter 5)) (lines (counter 6)))
             ;; Position and color belong to the draw, not the cached geometry.
             (lui.cocoa::cocoa-text font (copy-seq "AV") 100 -30 "#ff0000")
             (assert (lui.cocoa::same-object-p path (last-fill)))
             (assert (= (1+ builds) (counter 1)))
             (assert (= moves (counter 5)))
             (assert (= lines (counter 6)))
             (assert (= (1+ retains) (counter 2)))
             (assert (= (+ fills 2) (counter 4)))
             (assert (= (+ translates 2) (counter 7)))
             (assert (= (+ concats 2) (counter 8)))
             (assert (zerop (counter 9))))
           (let ((size (lui.font:font-size font)))
             (unwind-protect
                  (progn
                    (setf (lui.font:font-size font) (+ size 4))
                    (lui.cocoa::cocoa-text font "AV" 0 0 "#000000"))
               (setf (lui.font:font-size font) size)))
           (lui.cocoa::cocoa-text
            (lui.font:font-face font :monospace :bold) "AV" 0 0 "#000000")
           (assert (= (+ builds 3) (counter 1)))
           (let ((text (copy-seq "Mutable")))
             (lui.cocoa::cocoa-text font text 0 0 "#000000")
             (setf (char text 0) #\m)
             (lui.cocoa::cocoa-text font text 0 0 "#000000")
             (assert (gethash (list font (lui.font:font-size font) "Mutable")
                              cache))
             (assert (gethash (list font (lui.font:font-size font) "mutable")
                              cache)))
           (assert (= (+ builds 5) (counter 1)))
           ;; Both Lisp error and nonlocal exit restore native graphics state.
           (dolist (exit '(:error :throw))
             (setf (symbol-function 'lui.cocoa::cocoa-color)
                   (lambda (ink alpha)
                     (declare (ignore ink alpha))
                     (ecase exit
                       (:error (error "Synthetic cached text draw failure."))
                       (:throw (throw 'leave-cache :escaped)))))
             (assert (eq :escaped
                         (catch 'leave-cache
                           (handler-case
                               (lui.cocoa::cocoa-text font "Error" 4 5 "#000000")
                             (error () :escaped)))))
             (assert (zerop (counter 9))))
           (setf (symbol-function 'lui.cocoa::cocoa-color) color)
           (assert (= (+ builds 6) (counter 1))))
      (setf (symbol-function 'lui.cocoa::cocoa-color) color)
      (lui.cocoa::clear-text-paths)
      (lui.font:close-font font))
    (assert (zerop (hash-table-count cache)))
    (assert (= (- (counter 2) retains) (- (counter 3) releases)))
    (let ((released (counter 3)))
      (lui.cocoa::clear-text-paths)
      (assert (= released (counter 3))))
    (assert (zerop (counter 10)))
    (assert (restored-p))))

(fn test-text-cache-bound ()
  (let* ((font (lui.font:open-font))
         (lui.cocoa::*app* (lui.cocoa::make-cocoa-app))
         (lui.cocoa::*selectors* (make-hash-table :test 'equal))
         (cache (lui.cocoa::cocoa-app-text-paths lui.cocoa::*app*))
         (retains (counter 2)) (releases (counter 3)))
    (unwind-protect
         (progn
           (dotimes (i 256)
             (lui.cocoa::cocoa-text font (format nil "Text ~D" i)
                                    0 0 "#000000"))
           (assert (= 256 (hash-table-count cache)))
           (assert (= releases (counter 3)))
           (lui.cocoa::cocoa-text font "Next" 0 0 "#000000")
           (assert (= 1 (hash-table-count cache)))
           (assert (= (+ releases 256) (counter 3)))
           (assert (= (+ retains 257) (counter 2))))
      (lui.cocoa::clear-text-paths)
      (lui.font:close-font font))
    (assert (= (+ releases 257) (counter 3)))
    (assert (zerop (counter 10)))
    (assert (restored-p))))

(test-values-and-cleanup)
(test-callback-float-mode)
(test-selector-cache)
(test-text-path-cache)
(test-text-cache-bound)
(format t "Cocoa text-path reuse, bounded ownership and selector caching passed.~%")
(format t "Cocoa empty-stack guard values, cleanup, and callback FP passed.~%")
