(defpackage #:lui.wayland
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.font
        #:lui.draw #:lui.gl #:lui.wayland-protocol)
  (:local-nicknames (#:wf #:wayflan-client)
                    (#:xdg #:wayflan-client.xdg-shell)
                    (#:vp #:wayflan-client.viewporter))
  (:export #:run-wayland))
(in-package #:lui.wayland)

(cffi:define-foreign-library xkbcommon
  (:unix (:or "libxkbcommon.so.0" "libxkbcommon.so")))
(cffi:use-foreign-library xkbcommon)

(defstruct wl-window
  display registry compositor shell seat surface xdg toplevel
  decoration-manager decoration decoration-mode pending-decoration-mode
  viewporter viewport fractional-manager fractional-object
  cursor-manager cursor-device cursor-serial cursor-kind cursor-surface cursor-buffer
  shm (buffers nil) (outputs (make-hash-table :test 'eq)) (entered-outputs nil)
  (compositor-version 1 :type integer)
  (scale120 120 :type integer) (buffer-scale 1 :type integer)
  applied-buffer-scale
  (viewport-width 0 :type integer) (viewport-height 0 :type integer)
  clipboard-manager clipboard-device clipboard-source clipboard-text clipboard-serial
  pointer keyboard gpu font xkb-context keymap key-state
  (seat-version 1 :type integer)
  (repeat-rate 25 :type integer) (repeat-delay 600 :type integer)
  repeat-code repeat-at
  (width 720 :type integer) (height 520 :type integer)
  (x 0 :type real) (y 0 :type real) (buttons 0 :type integer)
  (configured-p nil :type boolean) (quit-p nil :type boolean)
  (events nil :type list))
(defvar *window*)

(fn on-event (proxy event (handler function))
  (push (lambda (name &rest arguments)
          (when (eq name event) (apply handler proxy arguments)))
        (wf:wl-proxy-hooks proxy)))

(fn pump-display (display &optional (timeout 16))
  ;; Wayflan exposes readiness rather than a socket descriptor. Keep the wait
  ;; bounded for animation and keyboard repeats, without depending on internals.
  (let ((deadline (+ (get-internal-real-time)
                     (* timeout (/ internal-time-units-per-second 1000)))))
    (loop until (wf:wl-display-listen display)
          when (>= (get-internal-real-time) deadline) do (return-from pump-display)
          do (sleep (min 0.005 (/ (max 0 (- deadline (get-internal-real-time)))
                                  internal-time-units-per-second))))
    (wf:wl-display-dispatch-event display)))



(fn queue-input ((kind symbol) &rest options)
  (push (apply #'make-event :kind kind options)
        (wl-window-events *window*)))

(fn release-clipboard-source ((window wl-window))
  (when (wl-window-clipboard-source window)
    (wf:destroy-proxy (wl-window-clipboard-source window))
    (setf (wl-window-clipboard-source window) nil
          (wl-window-clipboard-text window) nil)))

(fn write-clipboard-fd ((text string) (fd integer))
  (unwind-protect
       (cffi:with-foreign-string ((bytes byte-size) text :encoding :utf-8)
         (let ((size (1- byte-size))
               (offset 0))
           (loop :while (< offset size)
                 :for count :=
                 (cffi:foreign-funcall "write" :int fd
                   :pointer (cffi:inc-pointer bytes offset)
                   :size (- size offset) :long)
                 :do (cond ((plusp count) (incf offset count))
                           ((and (minusp count)
                                 (= 4 (cffi:mem-ref
                                       (cffi:foreign-funcall
                                        "__errno_location" :pointer) :int))))
                           (t (return nil))))))
    (cffi:foreign-funcall "close" :int fd :int)))

(fn clipboard-send (proxy mime fd)
  (declare (ignorable proxy))
  ;; FD belongs to this event; close it even for an unsupported target.
  (handler-case
      (write-clipboard-fd
       (if (and (wl-window-clipboard-source *window*)
                (eq proxy (wl-window-clipboard-source *window*))
                (member mime '("text/plain;charset=utf-8" "text/plain")
                        :test #'string=))
           (or (wl-window-clipboard-text *window*) "") "") fd)
    (error () nil)))

(fn clipboard-cancelled (proxy)
  (when (eq proxy (wl-window-clipboard-source *window*))
    (release-clipboard-source *window*)))

(fn create-clipboard-device ((window wl-window))
  (when (and (wl-window-clipboard-manager window) (wl-window-seat window))
    (let ((device (wf:wl-data-device-manager.get-data-device
                   (wl-window-clipboard-manager window) (wl-window-seat window))))
      (setf (wl-window-clipboard-device window) device)
      (on-event device :data-offer
                (lambda (proxy offer) (declare (ignore proxy))
                  (wf:destroy-proxy offer))))))

(fn copy-clipboard ((window wl-window) (text string))
  (when (and (wl-window-clipboard-device window) (wl-window-clipboard-serial window))
    (release-clipboard-source window)
    (let ((source (wf:wl-data-device-manager.create-data-source
                   (wl-window-clipboard-manager window))))
      (setf (wl-window-clipboard-source window) source
            (wl-window-clipboard-text window) (copy-seq text))
      (on-event source :send #'clipboard-send)
      (on-event source :cancelled #'clipboard-cancelled)
      (dolist (mime '("text/plain;charset=utf-8" "text/plain"))
        (wf:wl-data-source.offer source mime))
      (wf:wl-data-device.set-selection (wl-window-clipboard-device window)
                                        source (wl-window-clipboard-serial window)))))


(fn cursor-shape ((kind symbol))
  (case kind (:not-allowed 15) (:pointer 4) (:text 9)
        (:resize-horizontal 26) (:resize-vertical 27) (otherwise 1)))

(defstruct shm-buffer proxy memory size width height (busy-p nil))

(fn allocate-buffer ((window wl-window) (width integer) (height integer))
  (let* ((size (* width height 4))
         (fd (cffi:foreign-funcall "memfd_create" :string "lui-wayland" :uint 1 :int))
         (memory nil) (pool nil) (buffer nil) (complete nil))
    (when (minusp fd) (error "Cannot create Wayland shared memory."))
    (unwind-protect
         (progn
           (unless (zerop (cffi:foreign-funcall "ftruncate" :int fd :long size :int))
             (error "Cannot size Wayland shared memory."))
           (setf memory (cffi:foreign-funcall "mmap" :pointer (cffi:null-pointer)
                                            :size size :int 3 :int 1 :int fd :long 0 :pointer))
           (when (= (cffi:pointer-address memory) (1- (ash 1 (* 8 (cffi:foreign-type-size :pointer)))))
             (setf memory nil)
             (error "Cannot map Wayland shared memory."))
           (setf pool (wf:wl-shm.create-pool (wl-window-shm window) fd size)
                 buffer (make-shm-buffer
                         :proxy (wf:wl-shm-pool.create-buffer pool 0 width height
                                                               (* width 4) :argb8888)
                         :memory memory :size size :width width :height height))
           (on-event (shm-buffer-proxy buffer) :release
                     (lambda (proxy) (declare (ignore proxy))
                       (setf (shm-buffer-busy-p buffer) nil)))
           (setf complete t)
           buffer)
      (when pool (wf:destroy-proxy pool))
      (cffi:foreign-funcall "close" :int fd :int)
      (unless complete
        (when memory (cffi:foreign-funcall "munmap" :pointer memory :size size :int))))))

(fn free-buffer ((buffer shm-buffer))
  (when (shm-buffer-proxy buffer)
    (wf:destroy-proxy (shm-buffer-proxy buffer))
    (setf (shm-buffer-proxy buffer) nil))
  (when (shm-buffer-memory buffer)
    (cffi:foreign-funcall "munmap" :pointer (shm-buffer-memory buffer)
                                  :size (shm-buffer-size buffer) :int)
    (setf (shm-buffer-memory buffer) nil)))

(fn acquire-buffer ((window wl-window) (width integer) (height integer))
  (loop
    ;; Keep in-flight buffers until release, and reclaim obsolete sizes promptly.
    (setf (wl-window-buffers window)
          (delete-if (lambda (buffer)
                       (when (and (not (shm-buffer-busy-p buffer))
                                  (or (/= width (shm-buffer-width buffer))
                                      (/= height (shm-buffer-height buffer))))
                         (free-buffer buffer) t))
                     (wl-window-buffers window)))
    (let ((available (find-if (lambda (buffer) (not (shm-buffer-busy-p buffer)))
                              (wl-window-buffers window))))
      (when available (return available)))
    (when (< (length (wl-window-buffers window)) 3)
      (let ((buffer (allocate-buffer window width height)))
        (push buffer (wl-window-buffers window))
        (return buffer)))
    (when (wl-window-quit-p window) (return nil))
    (pump-display (wl-window-display window) 16)))

(fn present-shm ((window wl-window))
  (let* ((gpu (wl-window-gpu window))
         (width (gpu-width gpu)) (height (gpu-height gpu))
         (buffer (acquire-buffer window width height)))
    (when buffer
      ;; Native ARGB words match wl_shm's format. GL's bottom-up rows are flipped
      ;; before attaching the buffer; the renderer remains in logical coordinates.
      (let ((memory (shm-buffer-memory buffer)) (stride (* width 4)))
        (cffi:foreign-funcall "glReadPixels" :int 0 :int 0 :int width :int height
                              :uint #x80e1 :uint #x8367 :pointer memory :void)
        (cffi:with-foreign-object (row :uint8 stride)
          (dotimes (y (floor height 2))
            (let ((top (cffi:inc-pointer memory (* y stride)))
                  (bottom (cffi:inc-pointer memory (* (- height y 1) stride))))
              (cffi:foreign-funcall "memcpy" :pointer row :pointer top :size stride :pointer)
              (cffi:foreign-funcall "memcpy" :pointer top :pointer bottom :size stride :pointer)
              (cffi:foreign-funcall "memcpy" :pointer bottom :pointer row :size stride :pointer)))))
      (setf (shm-buffer-busy-p buffer) t)
      (wf:wl-surface.attach (wl-window-surface window) (shm-buffer-proxy buffer) 0 0)
      (wf:wl-surface.damage (wl-window-surface window) 0 0
                            (wl-window-width window) (wl-window-height window))
      (wf:wl-surface.commit (wl-window-surface window)))))

(fn set-fallback-cursor ()
  ;; Cursor-shape supplies semantic themed cursors when available. Older
  ;; compositors get a visible client-owned arrow instead of an invisible pointer.
  (when (wl-window-shm *window*)
    (unless (wl-window-cursor-buffer *window*)
      (let ((buffer (allocate-buffer *window* 24 24)))
        (dotimes (y 24)
          (dotimes (x 24)
            (setf (cffi:mem-aref (shm-buffer-memory buffer) :uint32 (+ x (* y 24)))
                  (cond ((and (< y 19) (<= x (floor y 2)))
                         (if (or (zerop x) (= x (floor y 2)) (= y 18))
                             #xff000000 #xffffffff))
                        ((and (<= 10 y 22) (<= (- (floor y 2) 2) x (floor y 2)))
                         #xff000000)
                        (t 0)))))
        (setf (wl-window-cursor-buffer *window*) buffer
              (wl-window-cursor-surface *window*)
              (wf:wl-compositor.create-surface (wl-window-compositor *window*)))
        (wf:wl-surface.attach (wl-window-cursor-surface *window*)
                              (shm-buffer-proxy buffer) 0 0)
        (wf:wl-surface.damage (wl-window-cursor-surface *window*) 0 0 24 24)
        (wf:wl-surface.commit (wl-window-cursor-surface *window*))))
    (wf:wl-pointer.set-cursor (wl-window-pointer *window*)
                              (wl-window-cursor-serial *window*)
                              (wl-window-cursor-surface *window*) 0 0)))


(fn update-cursor ()
  (when (and (wl-window-pointer *window*) (wl-window-cursor-serial *window*))
    (let ((kind (if (and (boundp '*context*) *context*)
                    (lui.widgets:cursor-at *context* (wl-window-x *window*)
                                                    (wl-window-y *window*))
                    :default)))
      (unless (eq kind (wl-window-cursor-kind *window*))
        (if (wl-window-cursor-device *window*)
            (set-cursor-shape (wl-window-cursor-device *window*)
                              (wl-window-cursor-serial *window*) (cursor-shape kind))
            (set-fallback-cursor))
        (setf (wl-window-cursor-kind *window*) kind)))))

(fn create-cursor-device ()
  (when (and (wl-window-cursor-manager *window*) (wl-window-pointer *window*)
             (null (wl-window-cursor-device *window*)))
    (setf (wl-window-cursor-device *window*)
          (get-cursor-device (wl-window-cursor-manager *window*)
                             (wl-window-pointer *window*))
          (wl-window-cursor-kind *window*) nil)))

(fn cancel-pointer ((window wl-window))
  (setf (wl-window-buttons window) 0)
  (push (make-event :kind :cancel :buttons 0) (wl-window-events window)))

(fn pointer-enter (proxy serial surface x y)
  (declare (ignorable proxy))
  (declare (ignore surface))
  (setf (wl-window-buttons *window*) 0
        (wl-window-cursor-serial *window*) serial
        (wl-window-cursor-kind *window*) nil
        (wl-window-x *window*) x
        (wl-window-y *window*) y)
  (queue-input :move :buttons 0
                    :x (wl-window-x *window*) :y (wl-window-y *window*))
  (update-cursor))

(fn pointer-leave (proxy serial surface)
  (declare (ignorable proxy))
  (declare (ignore serial surface))
  (cancel-pointer *window*)
  (setf (wl-window-cursor-serial *window*) nil
        (wl-window-cursor-kind *window*) nil
        (wl-window-x *window*) -1 (wl-window-y *window*) -1)
  (queue-input :move :buttons 0 :x -1 :y -1))

(fn pointer-motion (proxy time x y)
  (declare (ignorable proxy))
  (declare (ignore time))
  (setf (wl-window-x *window*) x
        (wl-window-y *window*) y)
  (queue-input :move :buttons (wl-window-buttons *window*)
                    :x (wl-window-x *window*) :y (wl-window-y *window*))
  (update-cursor))

(fn pointer-button (proxy serial time button state)
  (declare (ignorable proxy))
  (declare (ignore time))
  (setf (wl-window-clipboard-serial *window*) serial)
  (when (member button '(#x110 #x111))
    (let ((bit (if (= button #x111) 2 1)))
      (setf (wl-window-buttons *window*)
            (if (eq state :released) (logandc2 (wl-window-buttons *window*) bit)
                (logior (wl-window-buttons *window*) bit))))
    (queue-input (if (eq state :released) :release :press)
                 :button (if (= button #x111) :secondary :primary)
                 :buttons (wl-window-buttons *window*)
                 :x (wl-window-x *window*) :y (wl-window-y *window*))))

(fn pointer-axis (proxy time axis value)
  (declare (ignorable proxy))
  (declare (ignore time))
  (when (eq axis :vertical-scroll)
    (queue-input :scroll :x (wl-window-x *window*)
                        :y (wl-window-y *window*) :value value)))

(fn stop-key-repeat ((window wl-window))
  (setf (wl-window-repeat-code window) nil
        (wl-window-repeat-at window) nil))

(fn start-key-repeat ((code integer)
                      &optional ((now real) (get-internal-real-time)))
  (when (and (plusp (wl-window-repeat-rate *window*))
             (wl-window-keymap *window*)
             (plusp (cffi:foreign-funcall
                     "xkb_keymap_key_repeats"
                     :pointer (wl-window-keymap *window*)
                     :uint (+ code 8) :int)))
    (setf (wl-window-repeat-code *window*) code
          (wl-window-repeat-at *window*)
          (+ now (* (/ internal-time-units-per-second 1000)
                    (wl-window-repeat-delay *window*))))))

(fn release-keymap ((window wl-window))
  (stop-key-repeat window)
  (when (wl-window-key-state window)
    (cffi:foreign-funcall "xkb_state_unref"
                          :pointer (wl-window-key-state window) :void)
    (setf (wl-window-key-state window) nil))
  (when (wl-window-keymap window)
    (cffi:foreign-funcall "xkb_keymap_unref"
                          :pointer (wl-window-keymap window) :void)
    (setf (wl-window-keymap window) nil)))

(fn keyboard-map (proxy format fd size)
  (declare (ignorable proxy))
  (unwind-protect
       (when (and (eq format :xkb-v1) (< 0 size (* 16 1024 1024)))
         (cffi:with-foreign-object (text :char (1+ size))
           (loop :with offset := 0
                 :for count :=
                 (when (< offset size)
                   (cffi:foreign-funcall
                    "read" :int fd
                    :pointer (cffi:inc-pointer text offset)
                    :size (- size offset) :long))
                 :while (< offset size)
                 :do (when (<= count 0) (return))
                     (incf offset count)
                 :finally
                 (setf (cffi:mem-aref text :char size) 0)
                 (release-keymap *window*)
                 (let ((keymap
                         (cffi:foreign-funcall
                          "xkb_keymap_new_from_string"
                          :pointer (wl-window-xkb-context *window*)
                          :pointer text :uint 1 :uint 0 :pointer)))
                   (unless (cffi:null-pointer-p keymap)
                     (setf (wl-window-keymap *window*) keymap
                           (wl-window-key-state *window*)
                           (cffi:foreign-funcall "xkb_state_new"
                                                 :pointer keymap
                                                 :pointer)))))))
    (cffi:foreign-funcall "close" :int fd :int)))

(fn keyboard-enter (proxy serial surface keys)
  (declare (ignorable proxy))
  (declare (ignore serial surface keys))
  (stop-key-repeat *window*))

(fn keyboard-leave (proxy serial surface)
  (declare (ignorable proxy))
  (declare (ignore serial surface))
  (stop-key-repeat *window*)
  (cancel-pointer *window*))

(fn modifier-active-p (state (name string))
  (plusp (cffi:foreign-funcall
          "xkb_state_mod_name_is_active" :pointer state
          :string name :uint 8 :int)))

(fn editor-command (state (symbol integer) context)
  (when (and context (lui.widgets:text-field-focused-p context))
    (cffi:with-foreign-object (name :char 64)
      (let ((length (cffi:foreign-funcall
                     "xkb_keysym_get_name" :uint symbol
                     :pointer name :size 64 :int)))
        (when (< 0 length 64)
          (lui.widgets:readline-key
           (cffi:foreign-string-to-lisp name :count length)
           :control (modifier-active-p state "Control")
           :alt (modifier-active-p state "Mod1")
           :shift (modifier-active-p state "Shift")))))))

(fn emit-key-input ((code integer))
  (when (wl-window-key-state *window*)
    (let* ((context
             (when (and (boundp '*context*) *context*)
               (pending-input-context
                *context* (wl-window-events *window*)
                (wl-window-width *window*) (wl-window-height *window*))))
           (state (wl-window-key-state *window*))
           (key (+ code 8))
           (symbol (cffi:foreign-funcall "xkb_state_key_get_one_sym"
                                         :pointer state :uint key :uint))
           (editor (editor-command state symbol context))
           (command
             (cdr (assoc symbol
                         '((#xff51 . :left) (#xff53 . :right)
                           (#xff52 . :up) (#xff54 . :down)
                           (#xff50 . :home) (#xff57 . :end)
                           (#xff08 . :backspace) (#xffff . :delete)
                           (#xff1b . :escape))))))
      (cond ((and (member symbol '(#x63 #x43))
                  (modifier-active-p state "Control")
                  (not (modifier-active-p state "Mod1")))
             (queue-input :key :key :copy))
            (editor (queue-input :key :key editor))
            ((member symbol '(#xff09 #xfe20))
             (queue-input :tab :key
                          (when (or (= symbol #xfe20)
                                    (modifier-active-p state "Shift"))
                            :backward)))
            ((and (= symbol 32) context
                  (lui.widgets:activation-focused-p context))
             (queue-input :activate))
            ((= symbol #xff0d) (queue-input :activate))
            (command (queue-input :key :key command))
            (t
             (cffi:with-foreign-object (text :char 64)
               (let ((length
                       (cffi:foreign-funcall "xkb_state_key_get_utf8"
                                             :pointer state :uint key
                                             :pointer text :size 64 :int)))
                 (when (< 0 length 64)
                   (queue-input
                    :text :value
                    (cffi:foreign-string-to-lisp text :count length
                                                    :encoding :utf-8))))))))))

(fn keyboard-key (proxy serial time code pressed)
  (declare (ignorable proxy))
  (declare (ignore time))
  (setf (wl-window-clipboard-serial *window*) serial)
  (case pressed
    (:released
     (when (eql code (wl-window-repeat-code *window*))
       (stop-key-repeat *window*)))
    (:pressed
     (emit-key-input code)
     (start-key-repeat code))))

(fn keyboard-repeat-info (proxy rate delay)
  (declare (ignorable proxy))
  (setf (wl-window-repeat-rate *window*) (max 0 rate)
        (wl-window-repeat-delay *window*) (max 0 delay))
  (let ((code (wl-window-repeat-code *window*)))
    (stop-key-repeat *window*)
    (when code (start-key-repeat code))))

(fn repeat-input (&optional ((now real) (get-internal-real-time)))
  (when (and (wl-window-repeat-code *window*)
             (wl-window-repeat-at *window*)
             (plusp (wl-window-repeat-rate *window*)))
    (let ((interval (/ internal-time-units-per-second
                       (wl-window-repeat-rate *window*))))
      ;; Bound catch-up after a stalled frame so one held key cannot flood UI.
      (loop :repeat 8
            :while (<= (wl-window-repeat-at *window*) now)
            :do (emit-key-input (wl-window-repeat-code *window*))
                (incf (wl-window-repeat-at *window*) interval))
      (when (<= (wl-window-repeat-at *window*) now)
        (setf (wl-window-repeat-at *window*) (+ now interval))))))

(fn keyboard-modifiers (proxy serial depressed latched locked group)
  (declare (ignorable proxy))
  (declare (ignore serial))
  (when (wl-window-key-state *window*)
    (cffi:foreign-funcall "xkb_state_update_mask"
                          :pointer (wl-window-key-state *window*)
                          :uint depressed :uint latched :uint locked
                          :uint 0 :uint 0 :uint group :uint)))

(fn release-keyboard ((window wl-window))
  (release-keymap window)
  (when (wl-window-keyboard window)
    (cancel-pointer window)
    (wf:destroy-proxy (wl-window-keyboard window))
    (setf (wl-window-keyboard window) nil)))

(fn seat-capabilities (proxy capabilities)
  (unless (member :pointer capabilities)
    (when (or (wl-window-pointer *window*) (plusp (wl-window-buttons *window*)))
      (cancel-pointer *window*))
    (when (wl-window-cursor-device *window*)
      (wf:destroy-proxy (wl-window-cursor-device *window*))
      (setf (wl-window-cursor-device *window*) nil))
    (when (wl-window-pointer *window*)
      (wf:destroy-proxy (wl-window-pointer *window*))
      (setf (wl-window-pointer *window*) nil))
    (setf (wl-window-cursor-serial *window*) nil (wl-window-cursor-kind *window*) nil))
  (unless (member :keyboard capabilities) (release-keyboard *window*))
  (when (and (member :pointer capabilities) (null (wl-window-pointer *window*)))
    (let ((pointer (wf:wl-seat.get-pointer proxy)))
      (setf (wl-window-pointer *window*) pointer)
      (on-event pointer :enter #'pointer-enter)
      (on-event pointer :leave #'pointer-leave)
      (on-event pointer :motion #'pointer-motion)
      (on-event pointer :button #'pointer-button)
      (on-event pointer :axis #'pointer-axis)
      (create-cursor-device)))
  (when (and (member :keyboard capabilities) (null (wl-window-keyboard *window*)))
    (let ((keyboard (wf:wl-seat.get-keyboard proxy)))
      (setf (wl-window-keyboard *window*) keyboard)
      (on-event keyboard :keymap #'keyboard-map)
      (on-event keyboard :enter #'keyboard-enter)
      (on-event keyboard :leave #'keyboard-leave)
      (on-event keyboard :key #'keyboard-key)
      (on-event keyboard :modifiers #'keyboard-modifiers)
      (on-event keyboard :repeat-info #'keyboard-repeat-info))))

(fn registry-global (registry name interface-name version)
  (let* ((description
           (assoc interface-name
                  '(("wl_compositor" wf:wl-compositor compositor 5)
                    ("xdg_wm_base" xdg:xdg-wm-base shell 1)
                    ("wl_seat" wf:wl-seat seat 4)
                    ("wl_shm" wf:wl-shm shm 1)
                    ("wl_output" wf:wl-output outputs 2)
                    ("wl_data_device_manager" wf:wl-data-device-manager clipboard-manager 1)
                    ("zxdg_decoration_manager_v1" decoration-manager decoration-manager 1)
                    ("wp_viewporter" vp:wp-viewporter viewporter 1)
                    ("wp_fractional_scale_manager_v1" fractional-manager fractional-manager 1)
                    ("wp_cursor_shape_manager_v1" cursor-manager cursor-manager 1))
                  :test #'string=)))
    (when description
      (destructuring-bind (name-string class slot maximum) description
        (declare (ignore name-string))
        (let* ((bound-version (min version maximum))
               (object (wf:wl-registry.bind registry name class bound-version)))
          (case slot
            (compositor (setf (wl-window-compositor *window*) object
                              (wl-window-compositor-version *window*) bound-version))
            (shell (setf (wl-window-shell *window*) object)
                   (on-event object :ping
                             (lambda (shell serial) (xdg:xdg-wm-base.pong shell serial))))
            (seat (setf (wl-window-seat *window*) object
                        (wl-window-seat-version *window*) bound-version)
                  (on-event object :capabilities #'seat-capabilities))
            (shm (setf (wl-window-shm *window*) object))
            (outputs (setf (gethash object (wl-window-outputs *window*)) 1)
                     (on-event object :scale
                               (lambda (output scale)
                                 (setf (gethash output (wl-window-outputs *window*)) scale)
                                 (update-output-scale))))
            (clipboard-manager (setf (wl-window-clipboard-manager *window*) object))
            (decoration-manager (setf (wl-window-decoration-manager *window*) object))
            (viewporter (setf (wl-window-viewporter *window*) object))
            (fractional-manager (setf (wl-window-fractional-manager *window*) object))
            (cursor-manager (setf (wl-window-cursor-manager *window*) object)
                            (create-cursor-device))))))))

(fn update-output-scale ()
  (setf (wl-window-buffer-scale *window*)
        (loop for output in (wl-window-entered-outputs *window*)
              maximize (gethash output (wl-window-outputs *window*) 1) into scale
              finally (return (max 1 (or scale 1))))))

(fn create-scaling ((window wl-window))
  (on-event (wl-window-surface window) :enter
            (lambda (surface output) (declare (ignore surface))
              (pushnew output (wl-window-entered-outputs window))
              (update-output-scale)))
  (on-event (wl-window-surface window) :leave
            (lambda (surface output) (declare (ignore surface))
              (setf (wl-window-entered-outputs window)
                    (remove output (wl-window-entered-outputs window)))
              (update-output-scale)))
  (when (and (wl-window-viewporter window) (wl-window-fractional-manager window))
    (setf (wl-window-viewport window)
          (vp:wp-viewporter.get-viewport (wl-window-viewporter window) (wl-window-surface window))
          (wl-window-fractional-object window)
          (get-fractional-scale (wl-window-fractional-manager window) (wl-window-surface window)))
    (on-event (wl-window-fractional-object window) :preferred-scale
              (lambda (object scale) (declare (ignore object))
                (when (plusp scale) (setf (wl-window-scale120 window) scale))))))

(fn (surface-scale real) ((window wl-window))
  (if (wl-window-fractional-object window)
      (/ (wl-window-scale120 window) 120)
      (wl-window-buffer-scale window)))

(fn framebuffer-size ((window wl-window))
  (let ((scale (surface-scale window)))
    (values (max 1 (ceiling (* (wl-window-width window) scale)))
            (max 1 (ceiling (* (wl-window-height window) scale))))))

(fn sync-window-size ((window wl-window))
  (let ((width (wl-window-width window)) (height (wl-window-height window))
        (buffer-scale (if (wl-window-viewport window) 1 (wl-window-buffer-scale window))))
    (when (and (>= (wl-window-compositor-version window) 3)
               (not (eql buffer-scale (wl-window-applied-buffer-scale window))))
      (wf:wl-surface.set-buffer-scale (wl-window-surface window) buffer-scale)
      (setf (wl-window-applied-buffer-scale window) buffer-scale))
    (when (and (wl-window-viewport window)
               (or (/= width (wl-window-viewport-width window))
                   (/= height (wl-window-viewport-height window))))
      (vp:wp-viewport.set-destination (wl-window-viewport window) width height)
      (setf (wl-window-viewport-width window) width (wl-window-viewport-height window) height))
    (multiple-value-bind (pixel-width pixel-height) (framebuffer-size window)
      (let ((gpu (wl-window-gpu window)))
        (unless (and (= pixel-width (gpu-width gpu)) (= pixel-height (gpu-height gpu)))
          (resize-gpu-pbuffer gpu pixel-width pixel-height))
        (setf (gpu-logical-width gpu) width (gpu-logical-height gpu) height)))))

(fn decoration-configure (proxy mode)
  (declare (ignorable proxy))
  ;; This pending state belongs to the next xdg_surface.configure sequence.
  (setf (wl-window-pending-decoration-mode *window*) mode))

(fn accept-surface-configure ((window wl-window))
  (when (wl-window-pending-decoration-mode window)
    (setf (wl-window-decoration-mode window)
          (wl-window-pending-decoration-mode window)
          (wl-window-pending-decoration-mode window) nil))
  (setf (wl-window-configured-p window) t))

(fn surface-configure (proxy serial)
  (xdg:xdg-surface.ack-configure proxy serial)
  (accept-surface-configure *window*))

(fn create-decoration ((window wl-window))
  (when (wl-window-decoration-manager window)
    (let ((decoration (get-decoration (wl-window-decoration-manager window)
                                      (wl-window-toplevel window))))
      (setf (wl-window-decoration window) decoration)
      (on-event decoration :configure #'decoration-configure)
      (set-decoration-mode decoration 2))))

(fn toplevel-configure (proxy width height states)
  (declare (ignorable proxy))
  (declare (ignore states))
  (when (and (plusp width) (plusp height))
    (setf (wl-window-width *window*) width
          (wl-window-height *window*) height)))

(fn toplevel-close (proxy )
  (declare (ignorable proxy))
  (setf (wl-window-quit-p *window*) t))

(fn wait-wayland (display (context context) events)
  (loop :for delay := (lui.frame::frame-wait context events)
        :for repeat := (wl-window-repeat-at *window*)
        :when repeat
          :do (let ((ticks (- repeat (get-internal-real-time))))
                (setf delay
                      (min delay (/ (max 0 ticks)
                                    internal-time-units-per-second))))
        :do (pump-display display (ceiling (* 1000 delay)))
        :until (or (zerop delay) (wl-window-events *window*)
                   (wl-window-quit-p *window*)
                   (/= (wl-window-width *window*) (context-width context))
                   (/= (wl-window-height *window*) (context-height context))))
  (lui.frame::limit-frame-rate context))

(fn release-extensions ((window wl-window))
  (release-clipboard-source window)
  (dolist (proxy (list (wl-window-clipboard-device window)
                      (wl-window-clipboard-manager window)
                      (wl-window-cursor-surface window)
                      (wl-window-cursor-device window)
                      (wl-window-decoration window) (wl-window-viewport window)
                      (wl-window-fractional-object window)
                      (wl-window-cursor-manager window)
                      (wl-window-decoration-manager window)
                      (wl-window-viewporter window) (wl-window-fractional-manager window)))
    (when proxy (wf:destroy-proxy proxy)))
  (setf (wl-window-clipboard-device window) nil (wl-window-clipboard-manager window) nil
        (wl-window-cursor-surface window) nil (wl-window-cursor-device window) nil
        (wl-window-decoration window) nil (wl-window-viewport window) nil
        (wl-window-fractional-object window) nil (wl-window-cursor-manager window) nil
        (wl-window-decoration-manager window) nil (wl-window-viewporter window) nil
        (wl-window-fractional-manager window) nil))

(fn run-wayland ((draw function) &key title width height (interactive t))
  "Run DRAW through Wayflan, presenting the shared OpenGL renderer with wl_shm."
  (let* ((display (wf:wl-display-connect))
         (*window* (make-wl-window :display display :width (or width 720)
                                   :height (or height 520)))
         (*unit* 8))
    (unwind-protect
         (progn
           (setf (wl-window-xkb-context *window*)
                 (cffi:foreign-funcall "xkb_context_new" :uint 0 :pointer)
                 (wl-window-registry *window*) (wf:wl-display.get-registry display))
           (on-event (wl-window-registry *window*) :global #'registry-global)
           (wf:wl-display-roundtrip display)
           (unless (and (wl-window-compositor *window*) (wl-window-shell *window*)
                        (wl-window-shm *window*))
             (error "Wayland requires wl_compositor, xdg_wm_base, and wl_shm."))
           ;; Include seat capabilities and output scales in initialization.
           (wf:wl-display-roundtrip display)
           (create-clipboard-device *window*)
           (setf (wl-window-surface *window*)
                 (wf:wl-compositor.create-surface (wl-window-compositor *window*))
                 (wl-window-xdg *window*)
                 (xdg:xdg-wm-base.get-xdg-surface (wl-window-shell *window*)
                                                 (wl-window-surface *window*))
                 (wl-window-toplevel *window*)
                 (xdg:xdg-surface.get-toplevel (wl-window-xdg *window*)))
           (on-event (wl-window-xdg *window*) :configure #'surface-configure)
           (on-event (wl-window-toplevel *window*) :configure #'toplevel-configure)
           (on-event (wl-window-toplevel *window*) :close #'toplevel-close)
           (create-decoration *window*)
           (create-scaling *window*)
           (xdg:xdg-toplevel.set-title (wl-window-toplevel *window*) (or title "LUI"))
           (xdg:xdg-toplevel.set-app-id (wl-window-toplevel *window*) "lui")
           (wf:wl-surface.commit (wl-window-surface *window*))
           (loop until (wl-window-configured-p *window*)
                 do (wf:wl-display-dispatch-event display))
           (multiple-value-bind (pixel-width pixel-height) (framebuffer-size *window*)
             (setf (wl-window-font *window*) (open-font)
                   (wl-window-gpu *window*)
                   (open-gpu (wl-window-font *window*) pixel-width pixel-height)))
           (let* ((gpu (wl-window-gpu *window*)) (renderer (gpu-renderer gpu))
                  (context (make-context
                            :copy (when (wl-window-clipboard-device *window*)
                                    (let ((window *window*))
                                      (lambda (text) (copy-clipboard window text))))
                            :measure (lambda (widget width)
                                       (measure-widget renderer widget width))))
                  (*context* context))
             (loop with events until (wl-window-quit-p *window*) do
               (sync-window-size *window*)
               (repeat-input)
               (setf events (nreverse (shiftf (wl-window-events *window*) nil)))
               (with-frame (context (wl-window-width *window*) (wl-window-height *window*)
                                    :events events)
                 (funcall draw))
               (update-cursor)
               (begin-gpu-frame gpu)
               (paint-frame renderer context)
               (present-shm *window*)
               (unless interactive (wf:wl-display-roundtrip display) (return context))
               (wait-wayland display context events))))
      (when (wl-window-gpu *window*) (close-gpu (wl-window-gpu *window*)))
      (when (wl-window-font *window*) (close-font (wl-window-font *window*)))
      (release-keymap *window*)
      (when (wl-window-xkb-context *window*)
        (cffi:foreign-funcall "xkb_context_unref"
                              :pointer (wl-window-xkb-context *window*) :void))
      (release-extensions *window*)
      (dolist (buffer (wl-window-buffers *window*)) (free-buffer buffer))
      (when (wl-window-cursor-buffer *window*)
        (free-buffer (wl-window-cursor-buffer *window*)))
      (setf (wl-window-buffers *window*) nil (wl-window-cursor-buffer *window*) nil)
      ;; Disconnect invalidates all remaining proxy objects together.
      (wf:wl-display-disconnect display))))

(register-backend :wayland #'run-wayland)
