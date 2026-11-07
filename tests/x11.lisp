(defpackage #:lui.tests.x11
  (:use #:cl #:lui.frame #:lui.layout))
(in-package #:lui.tests.x11)

(lui.fn:fn translated-key (display symbol state context)
  (let ((keycode (xlib:keysym->keycodes display symbol)))
    (lui.x11::key-input display keycode state context)))

(assert (= 0 (lui.x11::pointer-buttons 0)))
(assert (= 1 (lui.x11::pointer-buttons #x100)))
(assert (= 2 (lui.x11::pointer-buttons #x400)))
(assert (= 3 (lui.x11::pointer-buttons #x500)))

(let* ((display (xlib:open-default-display))
       (window (lui.x11::make-x-window :display display))
       (context (make-context :focus :button))
       (widget (lui.widgets:make-widget :kind :button)))
  (assert (xlib:display-p display))
  (unwind-protect
       (progn
         (setf (context-root context)
               (make-element :id :button :content widget))
         (assert (eq :backward
                     (event-key (translated-key display #xff09 1 context))))
         (assert (eq :activate
                     (event-kind (translated-key display 32 0 context))))
         (setf (lui.widgets:widget-kind widget) :text-field)
         (assert (equal " "
                        (event-value (translated-key display 32 0 context))))
         (setf (context-focus context) nil
               (context-measure context)
               (lambda (widget width)
                 (declare (ignore widget width)) (values 160 30)))
         (with-frame (context 400 200)
           (lui.glass:text-field :edit "value"))
         (let* ((box (element-box
                      (gethash :edit (lui.frame::context-ids context))))
                (press (make-event :kind :press
                                   :x (+ (box-x box) 1)
                                   :y (+ (box-y box) 1)))
                (predicted (pending-input-context context (list press))))
           (assert (null (context-focus context)))
           (assert (eq :edit (context-focus predicted)))
           (assert (eq :select-all
                       (event-key (translated-key display #x41 5 predicted))))
           ;; A queued Tab follows the same focus order without mutating it.
           (assert (eq :edit
                       (context-focus
                        (pending-input-context
                         context (list (make-event :kind :tab)))))))
         (dolist (kind '(:default :pointer :text :not-allowed
                         :resize-horizontal :resize-vertical))
           (assert (xlib:cursor-p (lui.x11::cursor-for window kind))))
         (format t "X11 reverse Tab, Space, and native cursor checks passed.~%"))
    (maphash (lambda (kind cursor)
               (declare (ignore kind)) (xlib:free-cursor cursor))
             (lui.x11::x-window-cursors window))
    (xlib:close-display display)))

#+sbcl
(let ((before (sb-int:get-floating-point-modes)))
  (assert (eq :native-result
              (lui.x11::call-glx
               (lambda ()
                 (assert (null (getf (sb-int:get-floating-point-modes) :traps)))
                 (sb-int:set-floating-point-modes :rounding-mode :zero)
                 :native-result))))
  (assert (equal before (sb-int:get-floating-point-modes)))
  (handler-case
      (lui.x11::call-glx
       (lambda ()
         (sb-int:set-floating-point-modes :rounding-mode :zero)
         (error "test native failure")))
    (error ()))
  (assert (equal before (sb-int:get-floating-point-modes))))
