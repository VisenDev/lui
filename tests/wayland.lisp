(defpackage #:lui.tests.wayland
  (:use #:cl #:lui #:lui.layout #:lui.frame))
(in-package #:lui.tests.wayland)

(cffi:defcstruct keymap-names
  (rules :pointer) (model :pointer) (layout :pointer)
  (variant :pointer) (options :pointer))

(defun install-us-keymap (window)
  (lui.wayland::release-keymap window)
  (cffi:with-foreign-object (names '(:struct keymap-names))
    (cffi:with-foreign-string (layout-name "us")
      (cffi:with-foreign-slots
          ((rules model layout variant options) names (:struct keymap-names))
        (setf rules (cffi:null-pointer) model (cffi:null-pointer)
              layout layout-name variant (cffi:null-pointer)
              options (cffi:null-pointer)))
      (setf (lui.wayland::wl-window-keymap window)
            (cffi:foreign-funcall
             "xkb_keymap_new_from_names"
             :pointer (lui.wayland::wl-window-xkb-context window)
             :pointer names :uint 0 :pointer))))
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

(defun test-clipboard-transfer ()
  (let* ((source (cffi:make-pointer 1))
         (text "Clipboard café 🦊")
         (lui.wayland::*window*
           (lui.wayland::make-wl-window :clipboard-source source
                                       :clipboard-text text)))
    (dolist (mime '("text/plain;charset=utf-8" "text/plain" "image/png"))
      (cffi:with-foreign-object (fds :int 2)
        (assert (zerop (cffi:foreign-funcall "pipe" :pointer fds :int)))
        (let ((read-fd (cffi:mem-aref fds :int 0))
              (write-fd (cffi:mem-aref fds :int 1)))
          (unwind-protect
               (progn
                 (cffi:with-foreign-string (type mime)
                   (cffi:foreign-funcall-pointer
                    (cffi:callback lui.wayland::clipboard-send) ()
                    :pointer (cffi:null-pointer) :pointer source
                    :pointer type :int write-fd :void))
                 (cffi:with-foreign-object (bytes :char 128)
                   (let ((count (cffi:foreign-funcall
                                 "read" :int read-fd :pointer bytes
                                 :size 128 :long)))
                     (assert (>= count 0))
                     (assert (string=
                              (if (string= mime "image/png") "" text)
                              (cffi:foreign-string-to-lisp
                               bytes :count count :encoding :utf-8))))
                   ;; The callback owns and closes the transferred write FD.
                   (assert (zerop (cffi:foreign-funcall
                                   "read" :int read-fd :pointer bytes
                                   :size 128 :long)))))
            (cffi:foreign-funcall "close" :int read-fd :int))))))
  (format t "Wayland clipboard UTF-8 transfer and descriptor cleanup passed.~%"))

(test-clipboard-transfer)

(defun test-clipboard-source (window context)
  (if (lui.wayland::wl-window-clipboard-device window)
      (let ((serial (lui.wayland::wl-window-clipboard-serial window))
            (text (copy-seq "Native café 🦊")))
        (assert (functionp (context-copy context)))
        (unwind-protect
             (progn
               ;; No user input serial: exercise the actual protocol lifecycle
               ;; without claiming that this synthetic request gains ownership.
               (setf (lui.wayland::wl-window-clipboard-serial window) 0)
               (funcall (context-copy context) text)
               (setf (char text 0) #\X)
               (assert (string= "Native café 🦊"
                                (lui.wayland::wl-window-clipboard-text
                                 window)))
               (let ((first-id
                       (cffi:foreign-funcall "wl_proxy_get_id" :pointer
                         (lui.wayland::wl-window-clipboard-source window)
                         :uint32)))
                 (funcall (context-copy context) "Replacement")
                 (assert (/= first-id
                             (cffi:foreign-funcall "wl_proxy_get_id" :pointer
                               (lui.wayland::wl-window-clipboard-source
                                window) :uint32))))
               (assert (not (minusp
                             (lui.wayland-protocol:roundtrip
                              (lui.wayland::wl-window-display window)))))
               (let ((source
                       (lui.wayland::wl-window-clipboard-source window)))
                 (when source
                   (cffi:foreign-funcall-pointer
                    (cffi:callback lui.wayland::clipboard-cancelled) ()
                    :pointer (cffi:null-pointer) :pointer source :void)))
               (assert (null (lui.wayland::wl-window-clipboard-source
                              window)))
               (assert (null (lui.wayland::wl-window-clipboard-listener
                              window))))
          (setf (lui.wayland::wl-window-clipboard-serial window) serial)
          (lui.wayland::release-clipboard-source window)))
      (assert (null (context-copy context)))))

(defun test-themed-cursor (window)
  (when (lui.wayland::wl-window-shm window)
    (let ((image (lui.wayland::cursor-image-for window :not-allowed))
          (serial (lui.wayland::wl-window-cursor-serial window)))
      (assert image)
      (assert (plusp (cffi:foreign-slot-value
                      image '(:struct lui.wayland::cursor-image)
                      'lui.wayland::width)))
      (when (lui.wayland::wl-window-pointer window)
        ;; Serial 0 cannot change the real pointer. Still exercise native
        ;; theme-buffer attachment/commit and check server protocol errors.
        (unwind-protect
             (progn
               (setf (lui.wayland::wl-window-cursor-serial window) 0)
               (assert (lui.wayland::set-themed-cursor :not-allowed)))
          (setf (lui.wayland::wl-window-cursor-serial window) serial))
        (assert (not (minusp
                      (lui.wayland-protocol:roundtrip
                       (lui.wayland::wl-window-display window)))))))))

(defun test-pointer-cursor-state ()
  (let ((lui.wayland::*window* (lui.wayland::make-wl-window))
        (null (cffi:null-pointer)))
    (cffi:foreign-funcall-pointer
     (cffi:callback lui.wayland::pointer-enter) ()
     :pointer null :pointer null :uint32 41 :pointer null
     :int32 768 :int32 1024 :void)
    (let ((event (first (take-input))))
      (assert (eq :move (event-kind event)))
      (assert (= 3 (event-x event)))
      (assert (= 4 (event-y event))))
    (dolist (state '(1 0))
      (cffi:foreign-funcall-pointer
       (cffi:callback lui.wayland::pointer-button) ()
       :pointer null :pointer null :uint32 42 :uint32 0
       :uint32 #x110 :uint32 state :void)
      (assert (= 42 (lui.wayland::wl-window-clipboard-serial
                     lui.wayland::*window*)))
      ;; Cursor-shape requests require ENTER's serial, never BUTTON's serial.
      (assert (= 41 (lui.wayland::wl-window-cursor-serial
                     lui.wayland::*window*))))
    (cffi:foreign-funcall-pointer
     (cffi:callback lui.wayland::pointer-leave) ()
     :pointer null :pointer null :uint32 43 :pointer null :void)
    (assert (null (lui.wayland::wl-window-cursor-serial
                   lui.wayland::*window*)))
    (assert (= 15 (lui.wayland::cursor-shape :not-allowed)))))

(defun test-surface-scaling ()
  (let ((lui.wayland::*window*
          (lui.wayland::make-wl-window :width 101 :height 55))
        (null (cffi:null-pointer)))
    (cffi:foreign-funcall-pointer
     (cffi:callback lui.wayland::preferred-buffer-scale) ()
     :pointer null :pointer null :int32 2 :void)
    (assert (equal '(202 110)
                   (multiple-value-list
                    (lui.wayland::framebuffer-size lui.wayland::*window*))))
    ;; Fractional scaling overrides the integer fallback without rounding
    ;; logical input/layout coordinates or truncating physical coverage.
    (setf (lui.wayland::wl-window-fractional-object lui.wayland::*window*)
          (cffi:make-pointer 1))
    (cffi:foreign-funcall-pointer
     (cffi:callback lui.wayland::fractional-preferred-scale) ()
     :pointer null :pointer null :uint32 150 :void)
    (assert (equal '(127 69)
                   (multiple-value-list
                    (lui.wayland::framebuffer-size lui.wayland::*window*))))
    (assert (= 101 (lui.wayland::wl-window-width lui.wayland::*window*)))
    (assert (= 55 (lui.wayland::wl-window-height lui.wayland::*window*)))))

(defun test-readline-translation ()
  (let* ((xkb (cffi:foreign-funcall "xkb_context_new" :uint 0 :pointer))
         (lui.wayland::*window*
           (lui.wayland::make-wl-window :xkb-context xkb))
         (context (make-context :focus :edit))
         (*context* context)
         (null (cffi:null-pointer)))
    (setf (context-root context)
          (make-element :id :edit
                        :content (lui.widgets:make-widget :kind :text-field)))
    (unwind-protect
         (progn
           (install-us-keymap lui.wayland::*window*)
           (flet ((modifiers (mask)
                    (cffi:foreign-funcall-pointer
                     (cffi:callback lui.wayland::keyboard-modifiers) ()
                     :pointer null :pointer null :uint32 0 :uint32 mask
                     :uint32 0 :uint32 0 :uint32 0 :void))
                  (expect (code command)
                    (keyboard-key code 1)
                    (let ((events (take-input)))
                      (assert (= 1 (length events)))
                      (assert (eq :key (event-kind (first events))))
                      (assert (eq command (event-key (first events)))))))
             (modifiers 4)
             (loop :for (code command)
                     :in '((30 :home) (18 :end) (48 :left) (33 :right)
                           (32 :delete) (35 :backspace) (37 :kill-end)
                           (22 :kill-start) (17 :kill-word) (21 :yank)
                           (20 :transpose))
                   :do (expect code command))
             (expect 46 :copy)
             (modifiers 5)
             (expect 30 :select-all)
             (modifiers 8)
             (expect 48 :word-left)
             (expect 33 :word-right)
             (expect 32 :kill-word-forward)
             (modifiers 1)
             (keyboard-key 15 1)
             (let ((event (first (take-input))))
               (assert (eq :tab (event-kind event)))
               (assert (eq :backward (event-key event))))
             (modifiers 0)
             (expect 1 :escape)
             (setf (lui.widgets:widget-kind
                    (element-content (context-root context))) :button)
             (keyboard-key 57 1)
             (assert (eq :activate (event-kind (first (take-input)))))
             (setf (lui.widgets:widget-kind
                    (element-content (context-root context))) :text-field)
             (keyboard-key 57 1)
             (assert (equal " " (event-value (first (take-input)))))
             (modifiers 4)
             (setf (context-focus context) :another-widget)
             (keyboard-key 30 1)
             (assert (not (find :home (take-input) :key #'event-key)))))
      (lui.wayland::release-keymap lui.wayland::*window*)
      (cffi:foreign-funcall "xkb_context_unref" :pointer xkb :void))))

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

(test-pointer-cursor-state)
(test-decoration-configure)
(test-surface-scaling)
(test-readline-translation)

(test-key-repeat)

(let ((frames 0) (native nil))
  (setf lui.example::*count* 0)
  (catch 'done
    (run
     (lambda ()
       (incf frames)
       (when (= frames 1)
         (setf native lui.wayland::*window*)
         (test-clipboard-source native *context*)
         (test-themed-cursor native)
         (let ((gpu (lui.wayland::wl-window-gpu native)))
           (assert (= (context-width *context*)
                      (lui.wayland::wl-window-width native)))
           (assert (= (lui.gl:gpu-logical-width gpu)
                      (lui.wayland::wl-window-width native)))
           (assert (equal
                    (list (lui.gl:gpu-width gpu) (lui.gl:gpu-height gpu))
                    (multiple-value-list
                     (lui.wayland::framebuffer-size native))))
           (when (lui.wayland::wl-window-viewport native)
             (assert (= 1 (lui.wayland::wl-window-applied-buffer-scale
                           native)))
             (assert (= (lui.wayland::wl-window-viewport-width native)
                        (lui.wayland::wl-window-width native))))
           (format t "Wayland logical ~Dx~D, framebuffer ~Dx~D, scale ~A.~%"
                   (lui.gl:gpu-logical-width gpu)
                   (lui.gl:gpu-logical-height gpu)
                   (lui.gl:gpu-width gpu) (lui.gl:gpu-height gpu)
                   (lui.wayland::surface-scale native)))
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
         (setf (context-focus *context*) :name)
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
         (assert (eq :name (context-focus *context*)))
         (assert (not (context-focus-visible-p *context*)))
         (install-us-keymap lui.wayland::*window*)
         (repeat-info 20 100)
         (keyboard-key 30 1)
         (setf (lui.wayland::wl-window-repeat-at lui.wayland::*window*)
               (get-internal-real-time)))
       (when (= frames 4)
         ;; Both initial and repeated input must reach the next shared frame.
         (assert (>= (count :text (events-for :name) :key #'event-kind) 2))
         (keyboard-key 30 0))
       (when (= frames 5)
         (throw 'done t)))
     :backend :wayland))
  (assert (= frames 5))
  (assert (null (lui.wayland::wl-window-clipboard-source native)))
  (assert (null (lui.wayland::wl-window-clipboard-listener native)))
  (assert (null (lui.wayland::wl-window-clipboard-device native)))
  (assert (null (lui.wayland::wl-window-clipboard-manager native)))
  (assert (null (lui.wayland::wl-window-decoration native)))
  (assert (null (lui.wayland::wl-window-decoration-manager native)))
  (assert (null (lui.wayland::wl-window-cursor-theme native)))
  (assert (null (lui.wayland::wl-window-cursor-surface native)))
  (assert (null (lui.wayland::wl-window-cursor-device native)))
  (assert (null (lui.wayland::wl-window-cursor-manager native)))
  (assert (null (lui.wayland::wl-window-viewport native)))
  (assert (null (lui.wayland::wl-window-fractional-object native)))
  (format t "Wayland compositor, pointer callbacks, and cleanup passed.~%"))
