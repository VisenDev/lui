(defpackage #:lui.tests.wayland
  (:use #:cl #:lui #:lui.layout #:lui.frame))
(in-package #:lui.tests.wayland)

(cffi:defcstruct keymap-names
  (rules :pointer) (model :pointer) (layout :pointer)
  (variant :pointer) (options :pointer))

(defun install-us-keymap (window)
  (lui.wayland::release-keymap window)
  (cffi:with-foreign-object (names '(:struct keymap-names))
    (cffi:with-foreign-string (layout "us")
      (cffi:with-foreign-slots
          ((rules model layout variant options) names (:struct keymap-names))
        (setf rules (cffi:null-pointer) model (cffi:null-pointer)
              layout (cffi:foreign-string-alloc "us")
              variant (cffi:null-pointer) options (cffi:null-pointer))
        (unwind-protect
             (setf (lui.wayland::wl-window-keymap window)
                   (cffi:foreign-funcall
                    "xkb_keymap_new_from_names"
                    :pointer (lui.wayland::wl-window-xkb-context window)
                    :pointer names :uint 0 :pointer))
          (cffi:foreign-string-free layout)))))
  (assert (not (cffi:null-pointer-p
                (lui.wayland::wl-window-keymap window))))
  (setf (lui.wayland::wl-window-key-state window)
        (cffi:foreign-funcall
         "xkb_state_new" :pointer (lui.wayland::wl-window-keymap window)
         :pointer))
  (assert (not (cffi:null-pointer-p
                (lui.wayland::wl-window-key-state window)))))

(defun keyboard-key (code pressed)
  (let ((null (cffi:null-pointer)))
    (cffi:foreign-funcall-pointer
     (cffi:callback lui.wayland::keyboard-key) ()
     :pointer null :pointer null :uint32 0 :uint32 0
     :uint32 code :uint32 pressed :void)))

(defun repeat-info (rate delay)
  (let ((null (cffi:null-pointer)))
    (cffi:foreign-funcall-pointer
     (cffi:callback lui.wayland::keyboard-repeat-info) ()
     :pointer null :pointer null :int32 rate :int32 delay :void)))

(defun take-input ()
  (nreverse (shiftf
             (lui.wayland::wl-window-events lui.wayland::*window*) nil)))

(defun test-key-repeat ()
  (let* ((context (cffi:foreign-funcall "xkb_context_new" :uint 0 :pointer))
         (lui.wayland::*window*
           (lui.wayland::make-wl-window :xkb-context context)))
    (assert (not (cffi:null-pointer-p context)))
    (unwind-protect
         (progn
           (install-us-keymap lui.wayland::*window*)
           (repeat-info 20 100)
           (keyboard-key 30 1)
           (assert (equal '("a") (mapcar #'event-value (take-input))))
           (let* ((deadline
                    (lui.wayland::wl-window-repeat-at lui.wayland::*window*))
                  (interval (/ internal-time-units-per-second 20)))
             (lui.wayland::repeat-input (1- deadline))
             (assert (null (take-input)))
             (lui.wayland::repeat-input deadline)
             (assert (equal '("a") (mapcar #'event-value (take-input))))
             (lui.wayland::repeat-input (+ deadline (* 3 interval)))
             (assert (= 3 (length (take-input))))
             ;; Modifier presses do not take over the held repeatable key.
             (keyboard-key 42 1)
             (assert (= 30 (lui.wayland::wl-window-repeat-code
                            lui.wayland::*window*)))
             (let ((null (cffi:null-pointer)))
               (cffi:foreign-funcall-pointer
                (cffi:callback lui.wayland::keyboard-modifiers) ()
                :pointer null :pointer null :uint32 0 :uint32 1
                :uint32 0 :uint32 0 :uint32 0 :void))
             (lui.wayland::repeat-input (+ deadline (* 4 interval)))
             (assert (equal '("A") (mapcar #'event-value (take-input))))
             (keyboard-key 48 0)
             (assert (= 30 (lui.wayland::wl-window-repeat-code
                            lui.wayland::*window*)))
             (keyboard-key 30 0)
             (lui.wayland::repeat-input (+ deadline (* 10 interval)))
             (assert (null (take-input))))
           ;; Editing commands repeat through the same event translation.
           (keyboard-key 14 1)
           (lui.wayland::repeat-input
            (lui.wayland::wl-window-repeat-at lui.wayland::*window*))
           (assert (equal '(:backspace :backspace)
                          (mapcar #'event-key (take-input))))
           (keyboard-key 48 1)
           (keyboard-key 14 0)
           (assert (= 48 (lui.wayland::wl-window-repeat-code
                          lui.wayland::*window*)))
           (take-input)
           ;; Catch-up is bounded after a slow frame or suspended process.
           (let ((late (+ (lui.wayland::wl-window-repeat-at
                           lui.wayland::*window*)
                          (* 100 internal-time-units-per-second))))
             (lui.wayland::repeat-input late)
             (assert (= 8 (length (take-input))))
             (assert (> (lui.wayland::wl-window-repeat-at
                         lui.wayland::*window*) late)))
           ;; A compositor can disable repeat while a key remains down.
           (repeat-info 0 100)
           (assert (null (lui.wayland::wl-window-repeat-code
                          lui.wayland::*window*)))
           (keyboard-key 30 1)
           (assert (= 1 (length (take-input))))
           (assert (null (lui.wayland::wl-window-repeat-at
                          lui.wayland::*window*)))
           (repeat-info 20 100)
           (keyboard-key 30 1)
           (let ((null (cffi:null-pointer)))
             (cffi:foreign-funcall-pointer
              (cffi:callback lui.wayland::keyboard-leave) ()
              :pointer null :pointer null :uint32 0 :pointer null :void))
           (assert (null (lui.wayland::wl-window-repeat-code
                          lui.wayland::*window*)))
           (keyboard-key 30 1)
           (lui.wayland::release-keymap lui.wayland::*window*)
           (assert (null (lui.wayland::wl-window-repeat-at
                          lui.wayland::*window*)))
           (install-us-keymap lui.wayland::*window*)
           (keyboard-key 30 1)
           (let ((null (cffi:null-pointer)))
             (cffi:foreign-funcall-pointer
              (cffi:callback lui.wayland::seat-capabilities) ()
              :pointer null :pointer null :uint32 0 :void))
           (assert (null (lui.wayland::wl-window-repeat-code
                          lui.wayland::*window*))))
      (lui.wayland::release-keymap lui.wayland::*window*)
      (cffi:foreign-funcall "xkb_context_unref" :pointer context :void)))
  (format t "Wayland keyboard repeat timing, modifiers, and cancellation passed.~%"))

(defun test-decoration-configure ()
  (let ((lui.wayland::*window* (lui.wayland::make-wl-window))
        (null (cffi:null-pointer)))
    ;; Missing manager is a valid compositor configuration.
    (lui.wayland::create-decoration lui.wayland::*window*)
    (assert (null (lui.wayland::wl-window-decoration
                   lui.wayland::*window*)))
    (dolist (mode '(2 1))
      (let ((old (lui.wayland::wl-window-decoration-mode
                  lui.wayland::*window*)))
        (cffi:foreign-funcall-pointer
         (cffi:callback lui.wayland::decoration-configure) ()
         :pointer null :pointer null :uint32 mode :void)
        (assert (eql old (lui.wayland::wl-window-decoration-mode
                         lui.wayland::*window*)))
        (assert (= mode (lui.wayland::wl-window-pending-decoration-mode
                         lui.wayland::*window*)))
        (lui.wayland::accept-surface-configure lui.wayland::*window*)
        (assert (= mode (lui.wayland::wl-window-decoration-mode
                         lui.wayland::*window*)))))))

(test-decoration-configure)

(test-key-repeat)

(let ((frames 0) (native nil))
  (setf lui.example::*count* 0)
  (catch 'done
    (run
     (lambda ()
       (incf frames)
       (when (= frames 1)
         (setf native lui.wayland::*window*)
         (if (lui.wayland::wl-window-decoration-manager native)
             (progn
               (assert (lui.wayland::wl-window-decoration native))
               (assert (member (lui.wayland::wl-window-decoration-mode native)
                               '(1 2)))
               (format t "Wayland negotiated ~A decorations.~%"
                       (if (= 2 (lui.wayland::wl-window-decoration-mode
                                 native))
                           "server-side" "client-side")))
             (assert (null (lui.wayland::wl-window-decoration native)))))
       (lui.example:draw)
       (when (= frames 2)
         ;; Exercise the actual C callback ABI without moving the user's mouse.
         (let* ((box (previous-box :hello))
                (x (round (* 256 (+ (box-x box) 3))))
                (y (round (* 256 (+ (box-y box) 3))))
                (null (cffi:null-pointer)))
           (cffi:foreign-funcall-pointer
            (cffi:callback lui.wayland::pointer-motion) ()
            :pointer null :pointer null :uint32 0
            :int32 x :int32 y :void)
           (dolist (state '(1 0))
             (cffi:foreign-funcall-pointer
              (cffi:callback lui.wayland::pointer-button) ()
              :pointer null :pointer null :uint32 0 :uint32 0
              :uint32 #x110 :uint32 state :void))))
       (when (= frames 3)
         (assert (= lui.example::*count* 1))
         (install-us-keymap lui.wayland::*window*)
         (repeat-info 20 100)
         (keyboard-key 30 1)
         (setf (lui.wayland::wl-window-repeat-at lui.wayland::*window*)
               (get-internal-real-time)))
       (when (= frames 4)
         ;; Both initial and repeated input must reach the next shared frame.
         (assert (>= (count :text (events-for :hello) :key #'event-kind) 2))
         (keyboard-key 30 0))
       (when (= frames 5)
         (throw 'done t)))
     :backend :wayland))
  (assert (= frames 5))
  (assert (null (lui.wayland::wl-window-decoration native)))
  (assert (null (lui.wayland::wl-window-decoration-manager native)))
  (format t "Wayland compositor, pointer callbacks, and cleanup passed.~%"))
