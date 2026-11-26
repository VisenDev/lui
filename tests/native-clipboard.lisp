;; Exercise native transfers without a display server or desktop clipboard.
(asdf:load-system "lui/x11")
(asdf:load-system "lui/wayland")

(defpackage #:%lui.tests.native-clipboard
  (:use #:cl))
(in-package #:%lui.tests.native-clipboard)

(defmacro with-functions (bindings &body body)
  (let ((saved (gensym "SAVED")))
    `(let ((,saved (mapcar (lambda (symbol)
                            (cons symbol (symbol-function symbol)))
                          ',(mapcar #'first bindings))))
       (unwind-protect
            (progn
              ,@(loop :for (symbol function) :in bindings
                      :collect `(setf (symbol-function ',symbol) ,function))
              ,@body)
         (dolist (entry ,saved)
           (setf (symbol-function (car entry)) (cdr entry)))))))

(defun test-x11-paste-queue ()
  (let ((window (%lui.x11::make-x-window))
        (requests 0)
        (delivered nil)
        (chunk "A")
        (incremental nil))
    (with-functions
        ((%lui.x11::intern-atom
          (lambda (display name flag)
            (declare (ignore display flag))
            (cond ((string= name "UTF8_STRING") 1)
                  ((string= name "INCR") 2)
                  (t 3))))
         (%lui.x11::convert-selection
          (lambda (&rest args) (declare (ignore args)) (incf requests)))
         (%lui.x11::read-clipboard-property
          (lambda (window property)
            (declare (ignore property))
            (cffi:with-foreign-string ((bytes size) chunk :encoding :utf-8)
              (%lui.x11::clipboard-chunk
               window bytes (if incremental 2 1) 8
               (1- size) 0)))))
      (cffi:with-foreign-object (event :long 24)
        (setf (cffi:mem-ref event :int) 31
              (cffi:foreign-slot-value
               event '(:struct %lui.x11::selection-notify)
               '%lui.x11::property) 3)
        (labels ((request (id)
                   (%lui.x11::paste-clipboard
                    window (lambda (text) (push (list id text) delivered))))
                 (reply ()
                   (if (%lui.x11::x-window-paste-incremental-p window)
                       (setf (cffi:mem-ref event :int) 28
                             (cffi:foreign-slot-value
                              event '(:struct %lui.x11::property-notify)
                              '%lui.x11::atom) 3
                             (cffi:foreign-slot-value
                              event '(:struct %lui.x11::property-notify)
                              '%lui.x11::state) 0)
                       ;; else
                       (setf (cffi:mem-ref event :int) 31))
                   (%lui.x11::receive-clipboard window event)))
          (request 1)
          (request 2)
          (assert (= requests 1))
          (reply)
          (assert (= requests 2))
          (setf chunk "B")
          (reply)
          (assert (equal (reverse delivered) '((1 "A") (2 "B"))))
          ;; A queued request must preserve accumulated INCR bytes.
          (request 3)
          (setf incremental t)
          (reply)
          (setf incremental nil chunk "C")
          (reply)
          (request 4)
          (assert (= requests 3))
          (setf chunk "D")
          (reply)
          (setf chunk "")
          (reply)
          (assert (= requests 4))
          (setf chunk "E"
                (cffi:foreign-slot-value
                 event '(:struct %lui.x11::selection-notify)
                 '%lui.x11::property) 3)
          (reply)
          (assert (equal (reverse delivered)
                         '((1 "A") (2 "B") (3 "CD") (4 "E"))))
          ;; A refused conversion must not strand the next request.
          (request 5)
          (request 6)
          (setf (cffi:foreign-slot-value
                 event '(:struct %lui.x11::selection-notify)
                 '%lui.x11::property) 0)
          (reply)
          (assert (= requests 6)))))))

(defun test-wayland-paste-queue ()
  (let ((window (%lui.wayland::make-wl-window))
        (requests 0)
        (writer nil)
        (delivered nil))
    (setf (%lui.wayland::wl-window-clipboard-incoming window)
          (%lui.wayland::make-clipboard-offer
           :mime "text/plain;charset=utf-8"))
    (with-functions
        ((%lui.wayland-protocol:request
          (lambda (proxy opcode interface args &rest rest)
            (declare (ignore proxy opcode interface rest))
            (incf requests)
            (setf writer (cffi:foreign-funcall
                          "dup" :int (cdr (second args)) :int)))))
      (unwind-protect
           (labels ((request (id)
                      (%lui.wayland::paste-clipboard
                       window (lambda (text) (push (list id text) delivered))))
                    (reply (text)
                      (cffi:with-foreign-string ((bytes size) text :encoding :utf-8)
                        (cffi:foreign-funcall
                         "write" :int writer :pointer bytes :size
                         (1- size)
                         :long))
                      (cffi:foreign-funcall "close" :int writer :int)
                      (setf writer nil)
                      (%lui.wayland::poll-paste window)))
             (request 1)
             (request 2)
             (assert (= requests 1))
             (reply "α")
             (%lui.wayland::poll-paste window)
             (assert (= requests 2))
             (reply "β")
             (assert (equal (reverse delivered) '((1 "α") (2 "β"))))
             ;; Timeout advances the queue without delivering partial data.
             (request 3)
             (request 4)
             (cffi:foreign-funcall "close" :int writer :int)
             (setf writer nil
                   (%lui.wayland::wl-window-paste-deadline window) -1)
             (%lui.wayland::poll-paste window)
             (%lui.wayland::poll-paste window)
             (assert (= requests 4))
             (reply "δ")
             (assert (equal (reverse delivered)
                            '((1 "α") (2 "β") (4 "δ")))))
        (when writer (cffi:foreign-funcall "close" :int writer :int))
        (%lui.wayland::close-paste window)))))

(test-x11-paste-queue)
(test-wayland-paste-queue)
(format t "Native clipboard request ordering passed.~%")
