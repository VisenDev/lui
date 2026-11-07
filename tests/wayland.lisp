(defpackage #:lui.tests.wayland
  (:use #:cl #:lui #:lui.layout #:lui.frame))
(in-package #:lui.tests.wayland)

(lui.fn:fn dispatch-event (handler proxy &rest arguments)
  ;; Exercise the same public hook installation used by the backend. Arguments
  ;; already have Wayflan's decoded representation (keywords and real values).
  (let ((object (make-instance 'wayflan-client:wl-proxy :version 1)))
    (lui.wayland::on-event object :input
                          (lambda (object &rest values)
                            (declare (ignore object)) (apply handler proxy values)))
    (dolist (hook (wayflan-client:wl-proxy-hooks object))
      (funcall hook :unrelated)
      (apply hook :input arguments))))

(cffi:defcstruct keymap-names
  (rules :pointer) (model :pointer) (layout :pointer)
  (variant :pointer) (options :pointer))

(lui.fn:fn install-us-keymap (window)
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

(lui.fn:fn keyboard-key (code pressed)
  (let ((null (cffi:null-pointer)))
    (dispatch-event #'lui.wayland::keyboard-key null 0 0 code (if (zerop pressed) :released :pressed))))

(lui.fn:fn repeat-info (rate delay)
  (let ((null (cffi:null-pointer)))
    (dispatch-event #'lui.wayland::keyboard-repeat-info null rate delay)))

(lui.fn:fn take-input ()
  (nreverse (shiftf
             (lui.wayland::wl-window-events lui.wayland::*window*) nil)))

(lui.fn:fn pointer-motion (x y)
  (let ((null (cffi:null-pointer)))
    (dispatch-event #'lui.wayland::pointer-motion null 0 (/ (round (* x 256)) 256) (/ (round (* y 256)) 256))))

(lui.fn:fn pointer-button (pressed)
  (let ((null (cffi:null-pointer)))
    (dispatch-event #'lui.wayland::pointer-button null 0 0 #x110 (if (zerop pressed) :released :pressed))))

(lui.fn:fn test-pointer-cancellation ()
  (let* ((lui:*unit* 1) (context (lui.terminal:make-terminal-context))
         (state (lui.debug:make-state :selected '(:id :target)))
         (lui.wayland::*window* (lui.wayland::make-wl-window)))
    (lui.debug:set-enabled t :context context :state state)
    (labels ((frame ()
               (with-frame (context 200 80 :events (take-input))
                 (lui:button :target "Target")))
             (node (name)
               (gethash (lui.debug::id name)
                        (lui.frame::context-ids context)))
             (height () (box-height (element-box (node :property-pane)))))
      (frame) (frame)
      (dolist (mode '(:leave :keyboard :enter :device))
        (let* ((box (element-box (node :details-resize)))
               (x (+ (box-x box) 2)) (y (+ (box-y box) 0.5)))
          (pointer-motion x y)
          (pointer-button 1)
          (assert (= 1 (event-buttons
                        (first (lui.wayland::wl-window-events
                                lui.wayland::*window*)))))
          (frame)
          (assert (equal (context-active context)
                         (lui.debug::id :details-resize)))
          (let ((before (height)))
            (pointer-motion x (- y 2))
            (frame)
            (assert (= (+ before 2) (height))))
          (let ((null (cffi:null-pointer)) (before (height)))
            (case mode
              (:enter
               ;; A new enter re-synchronizes buttons after a lost release.
               (dispatch-event #'lui.wayland::pointer-enter null 0 null (/ (round (* x 256)) 256) (/ (round (* (- y 2) 256)) 256)))
              (:device
               (dispatch-event #'lui.wayland::seat-capabilities null nil))
              (otherwise
               (funcall (if (eq mode :leave)
                    #'lui.wayland::pointer-leave
                    #'lui.wayland::keyboard-leave) null 0 null)))
            (frame)
            (assert (null (context-active context)))
            (assert (null (lui.debug::state-details-grab state)))
            (pointer-motion x (- y 5))
            (frame)
            (assert (= before (height)))
            (assert (equal '(:id :target)
                           (lui.debug:state-selected state))))))
      (format t "Wayflan pointer hook cancellation and re-entry passed.~%"))))

(lui.fn:fn test-key-repeat ()
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
               (dispatch-event #'lui.wayland::keyboard-modifiers null 0 1 0 0 0))
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
             (dispatch-event #'lui.wayland::keyboard-leave null 0 null))
           (assert (null (lui.wayland::wl-window-repeat-code
                          lui.wayland::*window*)))
           (keyboard-key 30 1)
           (lui.wayland::release-keymap lui.wayland::*window*)
           (assert (null (lui.wayland::wl-window-repeat-at
                          lui.wayland::*window*)))
           (install-us-keymap lui.wayland::*window*)
           (keyboard-key 30 1)
           (let ((null (cffi:null-pointer)))
             (dispatch-event #'lui.wayland::seat-capabilities null nil))
           (assert (null (lui.wayland::wl-window-repeat-code
                          lui.wayland::*window*))))
      (lui.wayland::release-keymap lui.wayland::*window*)
      (cffi:foreign-funcall "xkb_context_unref" :pointer context :void)))
  (format t "Wayland keyboard repeat timing, modifiers, and cancellation passed.~%"))

(lui.fn:fn test-clipboard-transfer ()
  (let* ((source (gensym "SOURCE"))
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
                 (dispatch-event #'lui.wayland::clipboard-send source mime write-fd)
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

(lui.fn:fn test-clipboard-source (window context)
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
                       (wayflan-client:wl-proxy-id (lui.wayland::wl-window-clipboard-source window))))
                 (funcall (context-copy context) "Replacement")
                 (assert (/= first-id
                             (wayflan-client:wl-proxy-id (lui.wayland::wl-window-clipboard-source
                                window)))))
               (wayflan-client:wl-display-roundtrip (lui.wayland::wl-window-display window))
               (let ((source
                       (lui.wayland::wl-window-clipboard-source window)))
                 (when source
                   (dispatch-event #'lui.wayland::clipboard-cancelled source)))
               (assert (null (lui.wayland::wl-window-clipboard-source
                              window)))
               )
          (setf (lui.wayland::wl-window-clipboard-serial window) serial)
          (lui.wayland::release-clipboard-source window)))
      (assert (null (context-copy context)))))

(lui.fn:fn test-fallback-cursor (window)
  (when (lui.wayland::wl-window-pointer window)
    (let ((serial (lui.wayland::wl-window-cursor-serial window)))
      (unwind-protect
           (progn
             (setf (lui.wayland::wl-window-cursor-serial window) 0)
             (lui.wayland::set-fallback-cursor)
             (let ((buffer (lui.wayland::wl-window-cursor-buffer window)))
               (assert buffer)
               (assert (= 24 (lui.wayland::shm-buffer-width buffer)))
               (assert (= #xff000000
                          (cffi:mem-aref (lui.wayland::shm-buffer-memory buffer) :uint32 0)))))
        (setf (lui.wayland::wl-window-cursor-serial window) serial)))
    (wayflan-client:wl-display-roundtrip (lui.wayland::wl-window-display window))))

(lui.fn:fn test-pointer-cursor-state ()
  (let ((lui.wayland::*window* (lui.wayland::make-wl-window))
        (null (cffi:null-pointer)))
    (dispatch-event #'lui.wayland::pointer-enter null 41 null (/ 768 256) (/ 1024 256))
    (let ((event (first (take-input))))
      (assert (eq :move (event-kind event)))
      (assert (= 3 (event-x event)))
      (assert (= 4 (event-y event))))
    (dolist (state '(1 0))
      (dispatch-event #'lui.wayland::pointer-button null 42 0 #x110 (if (zerop state) :released :pressed))
      (assert (= 42 (lui.wayland::wl-window-clipboard-serial
                     lui.wayland::*window*)))
      ;; Cursor-shape requests require ENTER's serial, never BUTTON's serial.
      (assert (= 41 (lui.wayland::wl-window-cursor-serial
                     lui.wayland::*window*))))
    (dispatch-event #'lui.wayland::pointer-leave null 43 null)
    (assert (null (lui.wayland::wl-window-cursor-serial
                   lui.wayland::*window*)))
    (assert (= 15 (lui.wayland::cursor-shape :not-allowed)))
    (assert (= 26 (lui.wayland::cursor-shape :resize-horizontal)))
    (assert (= 27 (lui.wayland::cursor-shape :resize-vertical)))))

(lui.fn:fn test-surface-scaling ()
  (let ((lui.wayland::*window*
          (lui.wayland::make-wl-window :width 101 :height 55)))
    (let ((output (gensym "OUTPUT")))
      (setf (gethash output (lui.wayland::wl-window-outputs lui.wayland::*window*)) 2
            (lui.wayland::wl-window-entered-outputs lui.wayland::*window*) (list output))
      (lui.wayland::update-output-scale))
    (assert (equal '(202 110)
                   (multiple-value-list
                    (lui.wayland::framebuffer-size lui.wayland::*window*))))
    ;; Fractional scaling overrides the integer fallback without rounding
    ;; logical input/layout coordinates or truncating physical coverage.
    (setf (lui.wayland::wl-window-fractional-object lui.wayland::*window*)
          (gensym "SOURCE"))
    (setf (lui.wayland::wl-window-scale120 lui.wayland::*window*) 150)
    (assert (equal '(127 69)
                   (multiple-value-list
                    (lui.wayland::framebuffer-size lui.wayland::*window*))))
    (assert (= 101 (lui.wayland::wl-window-width lui.wayland::*window*)))
    (assert (= 55 (lui.wayland::wl-window-height lui.wayland::*window*)))))

(lui.fn:fn test-readline-translation ()
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
                    (dispatch-event #'lui.wayland::keyboard-modifiers null 0 mask 0 0 0))
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

(lui.fn:fn test-batched-focus ()
  (let* ((xkb (cffi:foreign-funcall "xkb_context_new" :uint 0 :pointer))
         (lui.wayland::*window*
           (lui.wayland::make-wl-window :xkb-context xkb
                                       :width 400 :height 200))
         (context (make-context
                   :measure (lambda (widget width)
                              (declare (ignore widget width))
                              (values 160 30))))
         (*context* context)
         (null (cffi:null-pointer)))
    (unwind-protect
         (progn
           (install-us-keymap lui.wayland::*window*)
           (with-frame (context 400 200)
             (lui.glass:text-field :edit "value"))
           (let ((box (element-box
                       (gethash :edit (lui.frame::context-ids context)))))
             (setf (lui.wayland::wl-window-x lui.wayland::*window*)
                   (+ 1 (box-x box))
                   (lui.wayland::wl-window-y lui.wayland::*window*)
                   (+ 1 (box-y box)))
             (dolist (pressed '(1 0))
               (dispatch-event #'lui.wayland::pointer-button null 42 0 #x110 (if (zerop pressed) :released :pressed))))
           (dispatch-event #'lui.wayland::keyboard-modifiers null 0 5 0 0 0)
           (keyboard-key 30 1)
           (assert (null (context-focus context)))
           (let ((events (take-input)))
             (assert (eq :select-all (event-key (car (last events)))))
             (with-frame (context 400 200 :events events)
               (lui.glass:text-field :edit "value")))
           (assert (eq :edit (context-focus context)))
           (let ((state (gethash :edit (context-state context))))
             (assert (= 0 (lui.widgets:edit-state-anchor state)))
             (assert (= 5 (lui.widgets:edit-state-cursor state)))))
      (lui.wayland::release-keymap lui.wayland::*window*)
      (cffi:foreign-funcall "xkb_context_unref" :pointer xkb :void)))
  (format t "Wayland batched pointer/Readline focus passed.~%"))

(test-batched-focus)

(lui.fn:fn test-decoration-configure ()
  (let ((lui.wayland::*window* (lui.wayland::make-wl-window))
        (null (cffi:null-pointer)))
    ;; Missing manager is a valid compositor configuration.
    (lui.wayland::create-decoration lui.wayland::*window*)
    (assert (null (lui.wayland::wl-window-decoration
                   lui.wayland::*window*)))
    (dolist (mode '(2 1))
      (let ((old (lui.wayland::wl-window-decoration-mode
                  lui.wayland::*window*)))
        (dispatch-event #'lui.wayland::decoration-configure null mode)
        (assert (eql old (lui.wayland::wl-window-decoration-mode
                         lui.wayland::*window*)))
        (assert (= mode (lui.wayland::wl-window-pending-decoration-mode
                         lui.wayland::*window*)))
        (lui.wayland::accept-surface-configure lui.wayland::*window*)
        (assert (= mode (lui.wayland::wl-window-decoration-mode
                         lui.wayland::*window*)))))))

(test-pointer-cursor-state)
(test-decoration-configure)
(test-pointer-cancellation)
(test-surface-scaling)
(test-readline-translation)

(test-key-repeat)

(lui.fn:fn test-shm-presentation (window)
  ;; A fresh native buffer exercises the public release hook without forging a
  ;; compositor release for any buffer it might still be reading.
  (let ((buffer (lui.wayland::allocate-buffer window 8 8)))
    (unwind-protect
         (progn
           (setf (lui.wayland::wl-window-buffers window) (list buffer)
                 (lui.wayland::shm-buffer-busy-p buffer) t)
           (dolist (hook (wayflan-client:wl-proxy-hooks
                          (lui.wayland::shm-buffer-proxy buffer)))
             (funcall hook :release))
           (assert (not (lui.wayland::shm-buffer-busy-p buffer)))
           (assert (eq buffer (lui.wayland::acquire-buffer window 8 8))))
      (setf (lui.wayland::wl-window-buffers window) nil)
      (lui.wayland::free-buffer buffer)))
  (let* ((gpu (lui.wayland::wl-window-gpu window))
         (width (lui.gl:gpu-width gpu)) (height (lui.gl:gpu-height gpu)))
    (lui.gl:begin-gpu-frame gpu)
    (cffi:foreign-funcall "glDisable" :uint #x0c11 :void)
    (cffi:foreign-funcall "glClearColor" :float 1.0 :float 0.0 :float 0.0 :float 1.0 :void)
    (cffi:foreign-funcall "glClear" :uint #x4000 :void)
    (cffi:foreign-funcall "glEnable" :uint #x0c11 :void)
    (cffi:foreign-funcall "glScissor" :int 0 :int (floor height 2)
                          :int width :int (- height (floor height 2)) :void)
    (cffi:foreign-funcall "glClearColor" :float 0.0 :float 1.0 :float 0.0 :float 1.0 :void)
    (cffi:foreign-funcall "glClear" :uint #x4000 :void)
    (cffi:foreign-funcall "glDisable" :uint #x0c11 :void)
    (lui.wayland::present-shm window)
    (let* ((buffer (first (lui.wayland::wl-window-buffers window)))
           (pixels (lui.wayland::shm-buffer-memory buffer)))
      (assert (lui.wayland::shm-buffer-busy-p buffer))
      ;; Wayland rows run top-down; pixels are native ARGB, not RGBA bytes.
      (assert (= #xff00ff00 (cffi:mem-aref pixels :uint32 0)))
      (assert (= #xffff0000 (cffi:mem-aref pixels :uint32 (* width (1- height)))))))
  (format t "Wayflan SHM ARGB colors, row orientation, and release/reuse passed.~%"))

(let ((frames 0) (native nil) (resize-target nil)
      (gallery (lui.example:make-gallery)))
  (catch 'done
    (run
     (lambda ()
       (incf frames)
       (when (= frames 1)
         (setf native lui.wayland::*window*)
         (test-clipboard-source native *context*)
         (test-fallback-cursor native)
         (test-shm-presentation native)
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
       (lui.example:draw gallery)
       (when (= frames 2)
         (setf (context-focus *context*) :name)
         ;; Exercise decoded Wayflan input hooks without moving the user's mouse.
         (let* ((box (previous-box :hello))
                (x (round (* 256 (+ (box-x box) 3))))
                (y (round (* 256 (+ (box-y box) 3))))
                (null (cffi:null-pointer)))
           (dispatch-event #'lui.wayland::pointer-motion null 0 (/ x 256) (/ y 256))
           (dolist (state '(1 0))
             (dispatch-event #'lui.wayland::pointer-button null 0 0 #x110 (if (zerop state) :released :pressed)))))
       (when (= frames 3)
         (assert (= (lui.example::gallery-count gallery) 1))
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
         (keyboard-key 30 0)
         ;; Change physical scale while retaining the compositor-configured
         ;; logical size (the headless compositor may require fullscreen).
         (setf (lui.wayland::wl-window-buffer-scale native) 2
               (lui.wayland::wl-window-scale120 native) 240
               resize-target (multiple-value-list
                              (lui.wayland::framebuffer-size native))))
       (when (= frames 5)
         (let ((gpu (lui.wayland::wl-window-gpu native)))
           (assert (equal resize-target (list (lui.gl:gpu-width gpu)
                                             (lui.gl:gpu-height gpu))))))
       (when (= frames 6)
         (let ((buffers (lui.wayland::wl-window-buffers native))
               (gpu (lui.wayland::wl-window-gpu native)))
           (assert (<= 1 (length buffers) 3))
           (assert (find-if
                    (lambda (buffer)
                      (and (= (lui.wayland::shm-buffer-width buffer) (lui.gl:gpu-width gpu))
                           (= (lui.wayland::shm-buffer-height buffer) (lui.gl:gpu-height gpu))
                           ;; The shared buffer contains actual rendered pixels.
                           (not (zerop (cffi:mem-aref
                                        (lui.wayland::shm-buffer-memory buffer) :uint32 0)))))
                    buffers)))
         (throw 'done t)))
     :backend :wayland))
  (assert (= frames 6))
  (assert (null (lui.wayland::wl-window-clipboard-source native)))

  (assert (null (lui.wayland::wl-window-clipboard-device native)))
  (assert (null (lui.wayland::wl-window-clipboard-manager native)))
  (assert (null (lui.wayland::wl-window-decoration native)))
  (assert (null (lui.wayland::wl-window-decoration-manager native)))
  (assert (null (lui.wayland::wl-window-cursor-buffer native)))
  (assert (null (lui.wayland::wl-window-cursor-surface native)))
  (assert (null (lui.wayland::wl-window-cursor-device native)))
  (assert (null (lui.wayland::wl-window-cursor-manager native)))
  (assert (null (lui.wayland::wl-window-viewport native)))
  (assert (null (lui.wayland::wl-window-fractional-object native)))
  (format t "Wayflan compositor, pointer hooks, and cleanup passed.~%"))
