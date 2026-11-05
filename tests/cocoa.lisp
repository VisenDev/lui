(defpackage #:lui.tests.cocoa
  (:use #:cl #:lui.fn #:lui #:lui.frame #:lui.layout)
  (:export #:run-tests))

(in-package #:lui.tests.cocoa)

(fn (rect-values list) (rect)
  (let ((origin (sb-alien:slot rect 'lui.cocoa::origin))
        (size (sb-alien:slot rect 'lui.cocoa::size)))
    (list (sb-alien:slot origin 'lui.cocoa::x)
          (sb-alien:slot origin 'lui.cocoa::y)
          (sb-alien:slot size 'lui.cocoa::width)
          (sb-alien:slot size 'lui.cocoa::height))))

(fn test-layout-and-encoding ()
  (assert (= 1 (sb-alien:alien-size lui.cocoa::objc-bool :bytes)))
  (assert (= 16 (sb-alien:alien-size lui.cocoa::point :bytes)))
  (assert (= 16 (sb-alien:alien-size lui.cocoa::size :bytes)))
  (assert (= 32 (sb-alien:alien-size lui.cocoa::rect :bytes)))
  (lui.cocoa::with-rect (rect -1.25 2.5 300 400)
    (assert (equal (rect-values rect) '(-1.25d0 2.5d0 300d0 400d0)))
    (let ((address (sb-alien:alien-sap rect)))
      (loop :for offset :from 0 :by 8
            :for value :in '(-1.25d0 2.5d0 300d0 400d0)
            :do (assert (= value (sb-sys:sap-ref-double address offset))))))
  ;; NSString's UTF8String contract must not depend on the host locale.
  (assert (= 8 (sb-alien:alien-funcall
                (sb-alien:extern-alien "strlen"
                  (function sb-alien:unsigned-long lui.cocoa::utf8-string))
                "λ日本"))))

(fn test-message-abi-selection ()
  (dolist (architecture '(:x86-64 :arm64))
    (let* ((*features* (cons architecture
                             (set-difference *features* '(:x86-64 :arm64))))
           (rect (macroexpand-1
                  '(lui.cocoa::message lui.cocoa::rect receiver "bounds")))
           (point (macroexpand-1
                   '(lui.cocoa::message lui.cocoa::point receiver
                     "convertPoint:fromView:"
                     lui.cocoa::point location lui.cocoa::object parent))))
      (assert (string= (second (second rect))
                       (if (eq architecture :x86-64)
                           "objc_msgSend_stret" "objc_msgSend")))
      (assert (string= "objc_msgSend" (second (second point))))
      (assert (equal (third (second point))
                     '(function lui.cocoa::point lui.cocoa::object
                       lui.cocoa::object lui.cocoa::point
                       lui.cocoa::object)))))
  (assert (handler-case
              (progn
                (macroexpand-1 '(lui.cocoa::message lui.cocoa::object
                                 receiver "bad:" lui.cocoa::object))
                nil)
            (error () t))))

(fn test-struct-call-abi ()
  ;; Exercise real native argument AND return conventions without AppKit or
  ;; a helper library: SBCL invokes its own C-callable entry points by value.
  (let ((calls 0))
    (sb-alien:with-alien-callable
        ((echo-rect lui.cocoa::rect
                    ((receiver lui.cocoa::object) (selector lui.cocoa::object)
                     (rect lui.cocoa::rect))
                    (assert (= 17 (sb-sys:sap-int receiver)))
                    (assert (= 23 (sb-sys:sap-int selector)))
                    (incf calls)
                    rect)
         (echo-point lui.cocoa::point ((point lui.cocoa::point))
                     (incf calls)
                     point))
      (lui.cocoa::with-rect (rect 1.25 -2.5 640 480)
        (let ((returned
               (sb-alien:alien-funcall echo-rect
                                       (sb-sys:int-sap 17)
                                       (sb-sys:int-sap 23) rect)))
          (assert (equal (rect-values returned)
                         '(1.25d0 -2.5d0 640d0 480d0)))))
      (sb-alien:with-alien ((point lui.cocoa::point))
        (setf (sb-alien:slot point 'lui.cocoa::x) 3.75d0
              (sb-alien:slot point 'lui.cocoa::y) -4.5d0)
        (let ((returned (sb-alien:alien-funcall echo-point point)))
          (assert (= 3.75d0 (sb-alien:slot returned 'lui.cocoa::x)))
          (assert (= -4.5d0 (sb-alien:slot returned 'lui.cocoa::y))))))
    (assert (= calls 2))))

(fn test-callback-boundary ()
  (let* ((view (sb-sys:int-sap 31))
         (context (make-context))
         (lui.cocoa::*app*
          (lui.cocoa::make-cocoa-app :view view :context context)))
    (lui.cocoa::with-rect (dirty 0 0 10 10)
      ;; Display before the first frame and after disposal must be harmless.
      (sb-alien:alien-funcall
       (sb-alien:alien-callable-function
        'lui.cocoa::draw-view)
       view (sb-sys:int-sap 0) dirty)
      (assert (null (lui.cocoa::cocoa-app-error lui.cocoa::*app*)))
      (let ((lui.cocoa::*app* nil))
        (sb-alien:alien-funcall
         (sb-alien:alien-callable-function
          'lui.cocoa::draw-view)
         view (sb-sys:int-sap 0) dirty))
      (setf (context-root context) (make-element))
      (let ((lookup (symbol-function 'lui.cocoa::objc-class)))
        (unwind-protect
             (progn
               (setf (symbol-function 'lui.cocoa::objc-class)
                     (lambda (name)
                       (declare (ignore name))
                       (error "Synthetic draw callback failure.")))
               (sb-alien:alien-funcall
                (sb-alien:alien-callable-function
                 'lui.cocoa::draw-view)
                view (sb-sys:int-sap 0) dirty)
               (assert (typep (lui.cocoa::cocoa-app-error lui.cocoa::*app*)
                              'error))
               (setf (lui.cocoa::cocoa-app-error lui.cocoa::*app*) nil
                     (symbol-function 'lui.cocoa::objc-class)
                     (lambda (name)
                       (declare (ignore name))
                       (throw 'escaped :unsafe)))
               (assert
                (eq :contained
                    (catch 'escaped
                      (sb-alien:alien-funcall
                       (sb-alien:alien-callable-function
                        'lui.cocoa::draw-view)
                       view (sb-sys:int-sap 0) dirty)
                      :contained)))
               (assert (typep (lui.cocoa::cocoa-app-error lui.cocoa::*app*)
                              'error)))
          (setf (symbol-function 'lui.cocoa::objc-class) lookup))))
    (assert (= 1 (sb-alien:alien-funcall
                  (sb-alien:alien-callable-function 'lui.cocoa::flipped)
                  view (sb-sys:int-sap 0))))))

(fn test-float-boundaries ()
  (let ((original (sb-int:get-floating-point-modes))
        (lookup (symbol-function 'lui.cocoa::objc-class))
        (traps '(:invalid :divide-by-zero :overflow :underflow :inexact)))
    (unwind-protect
         (progn
           (sb-int:set-floating-point-modes
            :traps traps :current-exceptions nil :accrued-exceptions nil)
           (let ((before (sb-int:get-floating-point-modes)))
             (sb-alien:with-alien-callable
                 ((divide sb-alien:double
                          ((numerator sb-alien:double)
                           (denominator sb-alien:double))
                          (/ numerator denominator)))
               (lui.cocoa::with-cocoa-float-mode
                 (assert (null (intersection
                                traps (getf (sb-int:get-floating-point-modes)
                                            :traps))))
                 ;; This actually crosses a native C calling boundary.
                 (assert (sb-ext:float-infinity-p
                          (sb-alien:alien-funcall divide 1d0 0d0)))
                 (sb-int:set-floating-point-modes :rounding-mode :zero)))
             (assert (equal before (sb-int:get-floating-point-modes)))
             (assert (eq :escaped
                         (catch 'exit-float-test
                           (lui.cocoa::with-cocoa-float-mode
                             (sb-int:set-floating-point-modes
                              :rounding-mode :zero)
                             (throw 'exit-float-test :escaped)))))
             (assert (equal before (sb-int:get-floating-point-modes)))
             (let* ((observed nil)
                    (view (sb-sys:int-sap 51))
                    (context (make-context))
                    (lui.cocoa::*app*
                     (lui.cocoa::make-cocoa-app :view view :context context)))
               (setf (context-root context) (make-element)
                     (symbol-function 'lui.cocoa::objc-class)
                     (lambda (name)
                       (declare (ignore name))
                       (setf observed (sb-int:get-floating-point-modes))
                       (sb-int:set-floating-point-modes :rounding-mode :zero)
                       (error "Synthetic native callback failure.")))
               (lui.cocoa::with-rect (dirty 0 0 1 1)
                 (sb-alien:alien-funcall
                  (sb-alien:alien-callable-function 'lui.cocoa::draw-view)
                  view (sb-sys:int-sap 0) dirty))
               (assert observed)
               (assert (null (intersection traps (getf observed :traps))))
               (assert (equal before (sb-int:get-floating-point-modes))))))
      (setf (symbol-function 'lui.cocoa::objc-class) lookup)
      (apply #'sb-int:set-floating-point-modes original))))

(fn test-window-routing ()
  (let ((target (sb-sys:int-sap 41))
        (other (sb-sys:int-sap 42))
        (null (sb-sys:int-sap 0)))
    (assert (lui.cocoa::input-for-window-p 10 (sb-sys:int-sap 41) target))
    (assert (lui.cocoa::input-for-window-p 22 target target))
    (assert (lui.cocoa::input-for-window-p 9 target target))
    (assert (null (lui.cocoa::input-for-window-p 1 other target)))
    (assert (null (lui.cocoa::input-for-window-p 15 target target)))
    (assert (null (lui.cocoa::input-for-window-p 10 null null)))))

(fn test-key-input ()
  (assert (eq :backward
              (event-key (lui.cocoa::cocoa-key-input 48 #x20000 ""))))
  (assert (eq :activate
              (event-kind (lui.cocoa::cocoa-key-input
                           49 0 " " nil " " t))))
  (assert (equal " "
                 (event-value (lui.cocoa::cocoa-key-input 49 0 " " t))))
  (assert (equal "operationNotAllowedCursor"
                 (lui.cocoa::cursor-selector :not-allowed)))
  (assert (eq :home
              (event-key (lui.cocoa::cocoa-key-input 0 #x40000 "a" t))))
  (assert (eq :kill-end
              (event-key (lui.cocoa::cocoa-key-input 40 #x40000 "k" t))))
  (assert (eq :word-left
              (event-key (lui.cocoa::cocoa-key-input 11 #x80000 "b" t))))
  (assert (null (lui.cocoa::cocoa-key-input
                 0 #x40000 (string (code-char 1)))))
  (assert (null (lui.cocoa::cocoa-key-input 0 #x100000 "a")))

  (assert (eq :shift-left
              (event-key (lui.cocoa::cocoa-key-input 123 #x20000 ""))))
  (assert (eq :shift-right
              (event-key (lui.cocoa::cocoa-key-input 124 #x20000 ""))))
  (assert (eq :select-all
              (event-key (lui.cocoa::cocoa-key-input 0 #x100000 "a" t))))
  (assert (null (lui.cocoa::cocoa-key-input 12 #x100000 "q")))
  (assert (eq :activate (event-kind (lui.cocoa::cocoa-key-input 76 0 ""))))
  (assert (string= "λ日本"
                   (event-value (lui.cocoa::cocoa-key-input 0 0 "λ日本"))))
  (assert (eq :escape
              (event-key (lui.cocoa::cocoa-key-input 53 0 ""))))
  (assert (eq :copy
              (event-key (lui.cocoa::cocoa-key-input 8 #x100000 "c")))))

#+darwin
(fn test-macos-runtime ()
  ;; This branch is a real AppKit smoke test, run only on macOS's main thread.
  (unless (sb-thread:main-thread-p)
    (error "Run the Cocoa runtime tests on the main thread."))
  (lui.cocoa::with-cocoa-float-mode
    (sb-alien:load-shared-object
     "/System/Library/Frameworks/AppKit.framework/AppKit")
    (let ((pool (lui.cocoa::message
                 lui.cocoa::object
                 (lui.cocoa::message
                  lui.cocoa::object
                  (lui.cocoa::objc-class "NSAutoreleasePool") "alloc")
                 "init")))
      (unwind-protect
           (progn
             (let ((string (lui.cocoa::ns-string "λ日本")))
               (assert (string= "λ日本"
                                (lui.cocoa::message lui.cocoa::utf8-string
                                                    string "UTF8String"))))
             (lui.cocoa::with-rect (rect 1.25 2.5 30 40)
               (let* ((path
                       (lui.cocoa::message
                        lui.cocoa::object
                        (lui.cocoa::objc-class "NSBezierPath")
                        "bezierPathWithRect:" lui.cocoa::rect rect))
                      (bounds (lui.cocoa::message lui.cocoa::rect
                                                  path "bounds")))
                 (assert (equal (rect-values bounds)
                                '(1.25d0 2.5d0 30d0 40d0))))))
        (lui.cocoa::message sb-alien:void pool "drain"))))
  (load "examples/demo.lisp")
  (let ((frames 0))
    (let ((context
           (run (lambda ()
                  (incf frames)
                  (funcall (symbol-function
                            (find-symbol "DRAW" "LUI.EXAMPLE"))))
                :backend :cocoa :interactive nil)))
      (assert (= frames 1))
      (assert (plusp (box-width (element-box (context-root context)))))
      (assert (plusp (box-height (element-box (context-root context))))))))

(fn run-tests ()
  (test-layout-and-encoding)
  (test-message-abi-selection)
  (test-struct-call-abi)
  (test-callback-boundary)
  (test-key-input)
  (test-window-routing)
  (test-float-boundaries)
  #+darwin (test-macos-runtime)
  (format t "Cocoa ABI/callback/input tests passed.~%")
  #-darwin (format t "AppKit runtime smoke skipped: macOS unavailable.~%")
  #+darwin (format t "Cocoa native shared demo smoke test passed.~%"))

(run-tests)
