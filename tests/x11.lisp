(defpackage #:%lui.tests.x11
  (:use #:cl #:%lui.frame #:%lui.layout))
(in-package #:%lui.tests.x11)

(defun translated-key (display symbol state context)
  (cffi:with-foreign-object (event '(:struct %lui.x11::key-event))
    (loop :for index :below
            (cffi:foreign-type-size '(:struct %lui.x11::key-event))
          :do (setf (cffi:mem-aref event :uint8 index) 0))
    (setf (cffi:foreign-slot-value event '(:struct %lui.x11::key-event)
                                  '%lui.x11::type) 2
          (cffi:foreign-slot-value event '(:struct %lui.x11::key-event)
                                  '%lui.x11::display) display
          (cffi:foreign-slot-value event '(:struct %lui.x11::key-event)
                                  '%lui.x11::state) state
          (cffi:foreign-slot-value event '(:struct %lui.x11::key-event)
                                  '%lui.x11::code)
          (cffi:foreign-funcall "XKeysymToKeycode" :pointer display
                                                  :ulong symbol :uint))
    (%lui.x11::key-input event context)))

(assert (= 0 (%lui.x11::pointer-buttons 0)))
(assert (= 1 (%lui.x11::pointer-buttons #x100)))
(assert (= 2 (%lui.x11::pointer-buttons #x400)))
(assert (= 3 (%lui.x11::pointer-buttons #x500)))

(let* ((display (%lui.x11::open-display (cffi:null-pointer)))
       (window (%lui.x11::make-x-window :display display))
       (context (make-context
                 :measure (lambda (widget width)
                            (declare (ignore widget width))
                            (values 160 30)))))
  (assert (not (cffi:null-pointer-p display)))
  (unwind-protect
       (progn
         (with-frame (context 400 200)
        (lui.glass:button "Button" (lui:opt :id :button)))
      (setf (context-focus context) (lui:widget-id :button context))
         (assert (eq :backward
                     (event-key (translated-key display #xff09 1 context))))
         (assert (eq :activate
                     (event-kind (translated-key display 32 0 context))))
         (with-frame (context 400 200)
        (lui.glass:text-field (lui:opt :id :button :value "value")))
         (assert (equal " "
                        (event-value (translated-key display 32 0 context))))
      (setf (context-focus context) (lui:widget-id nil context))
         (with-frame (context 400 200)
        (lui.glass:text-field (lui:opt :id :edit :value "value")))
         (let* ((box (element-box
                    (gethash (lui:widget-id :edit context)
                      (%lui.frame::context-ids context))))
                (press (make-event :kind :press
                                   :x (+ (box-x box) 1)
                                   :y (+ (box-y box) 1)))
                (predicted (pending-input-context context (list press))))
        (assert (null (lui:widget-key (context-focus context))))
        (assert (eq :edit (lui:widget-key (context-focus predicted))))
           (assert (eq :select-all
                       (event-key (translated-key display #x41 5 predicted))))
           ;; A queued Tab follows the same focus order without mutating it.
           (assert (eq :edit
                  (lui:widget-key (context-focus
                        (pending-input-context
                                    context (list (make-event :kind
                        :tab))))))))
         (dolist (kind '(:default :pointer :text :not-allowed
                         :resize-horizontal :resize-vertical))
           (assert (plusp (%lui.x11::cursor-for window kind))))
      (format t "X11 reverse Tab, Space, and native cursor checks passed.~%"))
    (maphash (lambda (kind cursor)
               (declare (ignore kind)) (%lui.x11::free-cursor display cursor))
             (%lui.x11::x-window-cursors window))
    (%lui.x11::close-display display)))

#+sbcl
(let ((before (sb-int:get-floating-point-modes)))
  (assert (eq :native-result
              (%lui.x11::call-glx
               (lambda ()
                 (assert (null (getf (sb-int:get-floating-point-modes)
                  :traps)))
                 (sb-int:set-floating-point-modes :rounding-mode :zero)
                 :native-result))))
  (assert (equal before (sb-int:get-floating-point-modes)))
  (handler-case
      (%lui.x11::call-glx
       (lambda ()
         (sb-int:set-floating-point-modes :rounding-mode :zero)
         (error "test native failure")))
    (error ()))
  (assert (equal before (sb-int:get-floating-point-modes))))
