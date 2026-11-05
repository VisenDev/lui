(defpackage #:lui.wayland
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.font
        #:lui.draw #:lui.gl #:lui.wayland-protocol)
  (:export #:run-wayland))
(in-package #:lui.wayland)

(cffi:define-foreign-library wayland-egl
  (:unix (:or "libwayland-egl.so.1" "libwayland-egl.so")))
(cffi:define-foreign-library xkbcommon
  (:unix (:or "libxkbcommon.so.0" "libxkbcommon.so")))
(cffi:use-foreign-library wayland-egl)
(cffi:use-foreign-library xkbcommon)

(defstruct wl-window
  display registry compositor shell seat surface xdg toplevel
  pointer keyboard native gpu font xkb-context keymap key-state
  (width 720 :type integer) (height 520 :type integer)
  (x 0 :type real) (y 0 :type real)
  (configured-p nil :type boolean) (quit-p nil :type boolean)
  (events nil :type list) (listeners nil :type list))
(defvar *window*)

(fn attach-listener (proxy (callbacks list))
  (push (listen-proxy proxy callbacks) (wl-window-listeners *window*)))

(defmacro callback (name arguments &body body)
  `(cffi:defcallback ,name :void
       ((data :pointer) (proxy :pointer) ,@arguments)
     (declare (ignore data) (ignorable proxy))
     ,@body))

(fn queue-input ((kind symbol) &rest options)
  (push (apply #'make-event :kind kind options)
        (wl-window-events *window*)))

(callback pointer-enter
    ((serial :uint32) (surface :pointer) (x :int32) (y :int32))
  (declare (ignore serial surface))
  (setf (wl-window-x *window*) (/ x 256.0)
        (wl-window-y *window*) (/ y 256.0)))

(callback pointer-leave ((serial :uint32) (surface :pointer))
  (declare (ignore serial surface)))

(callback pointer-motion ((time :uint32) (x :int32) (y :int32))
  (declare (ignore time))
  (setf (wl-window-x *window*) (/ x 256.0)
        (wl-window-y *window*) (/ y 256.0))
  (queue-input :move :x (wl-window-x *window*)
                    :y (wl-window-y *window*)))

(callback pointer-button
    ((serial :uint32) (time :uint32) (button :uint32) (state :uint32))
  (declare (ignore serial time))
  (when (= button #x110)
    (queue-input (if (zerop state) :release :press)
                 :x (wl-window-x *window*) :y (wl-window-y *window*))))

(callback pointer-axis ((time :uint32) (axis :uint32) (value :int32))
  (declare (ignore time))
  (when (zerop axis)
    (queue-input :scroll :x (wl-window-x *window*)
                        :y (wl-window-y *window*) :value (/ value 256.0))))

(fn release-keymap ((window wl-window))
  (when (wl-window-key-state window)
    (cffi:foreign-funcall "xkb_state_unref"
                          :pointer (wl-window-key-state window) :void)
    (setf (wl-window-key-state window) nil))
  (when (wl-window-keymap window)
    (cffi:foreign-funcall "xkb_keymap_unref"
                          :pointer (wl-window-keymap window) :void)
    (setf (wl-window-keymap window) nil)))

(callback keyboard-map ((format :uint32) (fd :int32) (size :uint32))
  (unwind-protect
       (when (and (= format 1) (< 0 size (* 16 1024 1024)))
         (cffi:with-foreign-object (text :char (1+ size))
           (loop :with offset := 0 :while (< offset size)
                 :for count :=
                 (cffi:foreign-funcall "read" :int fd
                                       :pointer (cffi:inc-pointer text offset)
                                       :size (- size offset) :long)
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

(callback keyboard-enter
    ((serial :uint32) (surface :pointer) (keys :pointer))
  (declare (ignore serial surface keys)))
(callback keyboard-leave ((serial :uint32) (surface :pointer))
  (declare (ignore serial surface)))

(callback keyboard-key
    ((serial :uint32) (time :uint32) (code :uint32) (pressed :uint32))
  (declare (ignore serial time))
  (when (and (= pressed 1) (wl-window-key-state *window*))
    (let* ((state (wl-window-key-state *window*))
           (key (+ code 8))
           (symbol (cffi:foreign-funcall "xkb_state_key_get_one_sym"
                                         :pointer state :uint key :uint))
           (command
             (cdr (assoc symbol
                         '((#xff51 . :left) (#xff53 . :right)
                           (#xff52 . :up) (#xff54 . :down)
                           (#xff50 . :home) (#xff57 . :end)
                           (#xff08 . :backspace) (#xffff . :delete))))))
      (cond ((= symbol #xff09) (queue-input :tab))
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

(callback keyboard-modifiers
    ((serial :uint32) (depressed :uint32) (latched :uint32)
     (locked :uint32) (group :uint32))
  (declare (ignore serial))
  (when (wl-window-key-state *window*)
    (cffi:foreign-funcall "xkb_state_update_mask"
                          :pointer (wl-window-key-state *window*)
                          :uint depressed :uint latched :uint locked
                          :uint 0 :uint 0 :uint group :uint)))

(callback seat-capabilities ((capabilities :uint32))
  (when (and (logtest capabilities 1) (null (wl-window-pointer *window*)))
    (let ((pointer
            (request proxy 0 "wl_pointer"
                     (list (cons :pointer (cffi:null-pointer))) 1)))
      (setf (wl-window-pointer *window*) pointer)
      (attach-listener
       pointer (list (cffi:callback pointer-enter)
                     (cffi:callback pointer-leave)
                     (cffi:callback pointer-motion)
                     (cffi:callback pointer-button)
                     (cffi:callback pointer-axis)))))
  (when (and (logtest capabilities 2) (null (wl-window-keyboard *window*)))
    (let ((keyboard
            (request proxy 1 "wl_keyboard"
                     (list (cons :pointer (cffi:null-pointer))) 1)))
      (setf (wl-window-keyboard *window*) keyboard)
      (attach-listener
       keyboard (list (cffi:callback keyboard-map)
                      (cffi:callback keyboard-enter)
                      (cffi:callback keyboard-leave)
                      (cffi:callback keyboard-key)
                      (cffi:callback keyboard-modifiers))))))

(callback shell-ping ((serial :uint32))
  (request proxy 3 nil (list (cons :uint32 serial))))

(callback registry-global
    ((name :uint32) (interface-name :string) (version :uint32))
  (when (member interface-name '("wl_compositor" "xdg_wm_base" "wl_seat")
                :test #'string=)
    (let* ((version (min version (if (string= interface-name "wl_compositor")
                                    4 1)))
           (object
             (request proxy 0 interface-name
                      (list (cons :uint32 name)
                            (cons :string interface-name)
                            (cons :uint32 version)
                            (cons :pointer (cffi:null-pointer)))
                      version)))
      (cond ((string= interface-name "wl_compositor")
             (setf (wl-window-compositor *window*) object))
            ((string= interface-name "xdg_wm_base")
             (setf (wl-window-shell *window*) object)
             (attach-listener object (list (cffi:callback shell-ping))))
            (t
             (setf (wl-window-seat *window*) object)
             (attach-listener object
                              (list (cffi:callback seat-capabilities))))))))

(callback registry-remove ((name :uint32))
  (declare (ignore name)))

(callback surface-configure ((serial :uint32))
  (request proxy 4 nil (list (cons :uint32 serial)))
  (setf (wl-window-configured-p *window*) t))

(callback toplevel-configure
    ((width :int32) (height :int32) (states :pointer))
  (declare (ignore states))
  (when (and (plusp width) (plusp height))
    (setf (wl-window-width *window*) width
          (wl-window-height *window*) height)))

(callback toplevel-close ()
  (setf (wl-window-quit-p *window*) t))

(fn run-wayland ((draw function) &key title width height (interactive t))
  (let* ((display (connect-display (cffi:null-pointer)))
         (*window* (make-wl-window :display display
                                  :width (or width 720)
                                  :height (or height 520)))
         (*unit* 8))
    (when (cffi:null-pointer-p display)
      (error "Cannot connect to the Wayland display."))
    (unwind-protect
         (progn
           (setf (wl-window-xkb-context *window*)
                 (cffi:foreign-funcall "xkb_context_new" :uint 0 :pointer)
                 (wl-window-registry *window*)
                 (request display 1 "wl_registry"
                          (list (cons :pointer (cffi:null-pointer))) 1))
           (attach-listener (wl-window-registry *window*)
                            (list (cffi:callback registry-global)
                                  (cffi:callback registry-remove)))
           (when (minusp (roundtrip display))
             (error "Wayland registry roundtrip failed."))
           (unless (and (wl-window-compositor *window*)
                        (wl-window-shell *window*))
             (error "Wayland compositor requires wl_compositor and xdg_wm_base."))
           (setf (wl-window-surface *window*)
                 (request (wl-window-compositor *window*) 0 "wl_surface"
                          (list (cons :pointer (cffi:null-pointer))))
                 (wl-window-xdg *window*)
                 (request (wl-window-shell *window*) 2 "xdg_surface"
                          (list (cons :pointer (cffi:null-pointer))
                                (cons :pointer (wl-window-surface *window*))))
                 (wl-window-toplevel *window*)
                 (request (wl-window-xdg *window*) 1 "xdg_toplevel"
                          (list (cons :pointer (cffi:null-pointer)))))
           (attach-listener (wl-window-xdg *window*)
                            (list (cffi:callback surface-configure)))
           (attach-listener (wl-window-toplevel *window*)
                            (list (cffi:callback toplevel-configure)
                                  (cffi:callback toplevel-close)))
           (request (wl-window-toplevel *window*) 2 nil
                    (list (cons :string title)))
           (request (wl-window-toplevel *window*) 3 nil
                    (list (cons :string "lui")))
           (request (wl-window-surface *window*) 6 nil nil)
           (loop :until (wl-window-configured-p *window*)
                 :do (when (minusp (dispatch-display display))
                       (error "Wayland initial configure failed.")))
           (setf (wl-window-native *window*)
                 (cffi:foreign-funcall
                  "wl_egl_window_create"
                  :pointer (wl-window-surface *window*)
                  :int (wl-window-width *window*)
                  :int (wl-window-height *window*) :pointer)
                 (wl-window-font *window*) (open-font)
                 (wl-window-gpu *window*)
                 (open-gpu display (wl-window-native *window*)
                           (wl-window-font *window*)
                           (wl-window-width *window*)
                           (wl-window-height *window*)))
           (let* ((gpu (wl-window-gpu *window*))
                  (renderer (gpu-renderer gpu))
                  (context
                    (make-context
                     :measure (lambda (widget width)
                                (measure-widget renderer widget width)))))
             (loop :until (wl-window-quit-p *window*)
                   :do
                   (unless (and (= (gpu-width gpu)
                                   (wl-window-width *window*))
                                (= (gpu-height gpu)
                                   (wl-window-height *window*)))
                     (setf (gpu-width gpu) (wl-window-width *window*)
                           (gpu-height gpu) (wl-window-height *window*))
                     (cffi:foreign-funcall
                      "wl_egl_window_resize"
                      :pointer (wl-window-native *window*)
                      :int (gpu-width gpu) :int (gpu-height gpu)
                      :int 0 :int 0 :void))
                   (with-frame
                       (context (gpu-width gpu) (gpu-height gpu)
                        :events (nreverse (wl-window-events *window*)))
                     (setf (wl-window-events *window*) nil)
                     (funcall draw))
                   (begin-gpu-frame gpu)
                   (paint-frame renderer context)
                   (present-gpu gpu)
                   (unless interactive (return context))
                   (pump-display display))))
      (when (wl-window-gpu *window*)
        (close-gpu (wl-window-gpu *window*)))
      (when (wl-window-native *window*)
        (cffi:foreign-funcall "wl_egl_window_destroy"
                              :pointer (wl-window-native *window*) :void))
      (when (wl-window-font *window*)
        (close-font (wl-window-font *window*)))
      (release-keymap *window*)
      (when (wl-window-xkb-context *window*)
        (cffi:foreign-funcall "xkb_context_unref"
                              :pointer (wl-window-xkb-context *window*)
                              :void))
      (dolist (proxy (list (wl-window-keyboard *window*)
                          (wl-window-pointer *window*)
                          (wl-window-seat *window*)
                          (wl-window-toplevel *window*)
                          (wl-window-xdg *window*)
                          (wl-window-surface *window*)
                          (wl-window-shell *window*)
                          (wl-window-compositor *window*)
                          (wl-window-registry *window*)))
        (when proxy (destroy-proxy proxy)))
      (dolist (listener (wl-window-listeners *window*))
        (cffi:foreign-free listener))
      (disconnect-display display))))

(register-backend :wayland #'run-wayland)
