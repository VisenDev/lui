(defpackage #:lui.tests.x11
  (:use #:cl #:lui.frame #:lui.layout))
(in-package #:lui.tests.x11)

(defun translated-key (display symbol state context)
  (cffi:with-foreign-object (event '(:struct lui.x11::key-event))
    (loop :for index :below
            (cffi:foreign-type-size '(:struct lui.x11::key-event))
          :do (setf (cffi:mem-aref event :uint8 index) 0))
    (setf (cffi:foreign-slot-value event '(:struct lui.x11::key-event)
                                  'lui.x11::type) 2
          (cffi:foreign-slot-value event '(:struct lui.x11::key-event)
                                  'lui.x11::display) display
          (cffi:foreign-slot-value event '(:struct lui.x11::key-event)
                                  'lui.x11::state) state
          (cffi:foreign-slot-value event '(:struct lui.x11::key-event)
                                  'lui.x11::code)
          (cffi:foreign-funcall "XKeysymToKeycode" :pointer display
                                                  :ulong symbol :uint))
    (lui.x11::key-input event context)))

(let* ((display (lui.x11::open-display (cffi:null-pointer)))
       (window (lui.x11::make-x-window :display display))
       (context (make-context :focus :button))
       (widget (lui.widgets:make-widget :kind :button)))
  (assert (not (cffi:null-pointer-p display)))
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
         (dolist (kind '(:default :pointer :text :not-allowed))
           (assert (plusp (lui.x11::cursor-for window kind))))
         (format t "X11 reverse Tab, Space, and native cursor checks passed.~%"))
    (maphash (lambda (kind cursor)
               (declare (ignore kind)) (lui.x11::free-cursor display cursor))
             (lui.x11::x-window-cursors window))
    (lui.x11::close-display display)))
