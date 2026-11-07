(defpackage #:lui.x11
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.font #:lui.draw
        #:lui.gl)
  (:export #:run-x11))

(in-package #:lui.x11)

;; GLX needs a native Display for the libGL context used by the shared renderer.
;; CLX's GLX extension manages an indirect wire context, not libGL's current
;; context, and its GL encoders omit the shader/program commands Glass needs.
;; Keep this three-symbol Xlib bridge for GLX only; window resources, input,
;; selections and cursors belong to the CLX connection.
(cffi:define-foreign-library glx-xlib (:unix (:or "libX11.so.6" "libX11.so")))
(cffi:use-foreign-library glx-xlib)
(cffi:defcfun ("XOpenDisplay" open-glx-display) :pointer (name :pointer))
(cffi:defcfun ("XCloseDisplay" close-glx-display) :int (display :pointer))
(cffi:defcfun ("XFree" free-visual) :int (data :pointer))
(cffi:defcstruct visual-info
  (visual :pointer) (visual-id :ulong) (screen :int) (depth :int)
  (class :int) (red :ulong) (green :ulong) (blue :ulong)
  (map-size :int) (bits :int))
(cffi:defcfun ("glXChooseVisual" choose-visual) :pointer
  (display :pointer) (screen :int) (attributes :pointer))
(cffi:defcfun ("glXCreateContext" %create-glx) :pointer
  (display :pointer) (visual :pointer) (share :pointer) (direct :int))
(cffi:defcfun ("glXMakeCurrent" %make-current) :int
  (display :pointer) (window :ulong) (context :pointer))
(cffi:defcfun ("glXSwapBuffers" swap-buffers) :void
  (display :pointer) (window :ulong))
(cffi:defcfun ("glXDestroyContext" destroy-glx) :void
  (display :pointer) (context :pointer))

(fn call-glx ((function function) &rest arguments)
  ;; Mesa worker threads inherit the caller's FP exception mask when a context
  ;; starts. Keep native GLX initialization independent of Lisp's trap settings.
  #+sbcl
  (let ((modes (sb-int:get-floating-point-modes)))
    (unwind-protect
         (sb-int:with-float-traps-masked
             (:invalid :divide-by-zero :overflow :underflow :inexact)
           (apply function arguments))
      (apply #'sb-int:set-floating-point-modes modes)))
  #-sbcl (apply function arguments))

(fn create-glx (display visual share direct)
  (call-glx #'%create-glx display visual share direct))

(fn make-current (display window context)
  (call-glx #'%make-current display window context))

(defstruct x-window
  display glx-display context window colormap clipboard clipboard-text
  (width 720 :type integer) (height 520 :type integer)
  (cursors (make-hash-table :test 'eq) :type hash-table)
  cursor-kind (pointer-x -1 :type real) (pointer-y -1 :type real))

(fn copy-clipboard ((window x-window) (text string))
  (setf (x-window-clipboard-text window) (copy-seq text)
        (xlib:selection-owner (x-window-display window) :clipboard)
        (x-window-window window))
  (xlib:display-force-output (x-window-display window)))

(fn selection-request ((window x-window) requestor selection target property time)
  (let* ((display (x-window-display window))
         (target-name (symbol-name target))
         (destination (or property target))
         (text (x-window-clipboard-text window))
         (result nil))
    (when (and text (eq selection :clipboard))
      (cond ((string= target-name "TARGETS")
             (xlib:change-property requestor destination
                                   (mapcar (lambda (name) (xlib:intern-atom display name))
                                           '("TARGETS" "UTF8_STRING" "TEXT" "STRING"))
                                   :atom 32)
             (setf result destination))
            ((member target-name '("UTF8_STRING" "TEXT" "STRING") :test #'string=)
             (let* ((legacy (string= target-name "STRING"))
                    (bytes (if legacy
                               (map '(vector (unsigned-byte 8))
                                    (lambda (char)
                                      (if (< (char-code char) 256)
                                          (char-code char) 63)) text)
                               (babel:string-to-octets text :encoding :utf-8))))
               (when (< (length bytes) (- (* 4 (xlib:display-max-request-length display)) 64))
                 (xlib:change-property requestor destination bytes
                                       (if legacy :string :utf8_string) 8)
                 (setf result destination))))))
    (xlib:send-event requestor :selection-notify nil
                     :event-window requestor :window requestor
                     :selection selection :target target :property result :time time)
    (xlib:display-force-output display)))
(fn key-input (display keycode state &optional context)
  (let* ((code (xlib:keycode->keysym
                display keycode (xlib:default-keysym-index display keycode state)))
         (character (xlib:keycode->character display keycode state))
         (control (logtest state 4))
         (alt (logtest state 8))
         (shift (logtest state 1))
         (text-p (and context (lui.widgets:text-field-focused-p context)))
         (key (cdr (assoc code
                          '((#xff51 . :left) (#xff53 . :right)
                            (#xff52 . :up) (#xff54 . :down)
                            (#xff50 . :home) (#xff57 . :end)
                            (#xff08 . :backspace) (#xffff . :delete)
                            (#xff1b . :escape)))))
         (name (case code
                 (#xff51 "ArrowLeft") (#xff53 "ArrowRight")
                 (#xff08 "Backspace")
                 (otherwise (if (<= 32 code 126)
                                (string (code-char code)) ""))))
         (command (when text-p
                    (lui.widgets:readline-key name :control control
                                              :alt alt :shift shift))))
    (cond ((and control (not alt) (member code '(#x63 #x43)))
           (make-event :kind :key :key :copy))
          (command (make-event :kind :key :key command))
          ((member code '(#xff09 #xfe20))
           (make-event :kind :tab
                       :key (when (or shift (= code #xfe20)) :backward)))
          ((and (= code 32) context
                (lui.widgets:activation-focused-p context))
           (make-event :kind :activate))
          ((= code #xff0d) (make-event :kind :activate))
          (key (make-event :kind :key
                           :key (if (and text-p shift)
                                    (case key
                                      (:left :shift-left)
                                      (:right :shift-right)
                                      (otherwise key))
                                    key)))
          ((and character (not control) (not alt))
           (make-event :kind :text :value (string character))))))

(fn cursor-for ((window x-window) (kind symbol))
  (or (gethash kind (x-window-cursors window))
      (setf (gethash kind (x-window-cursors window))
            (let* ((font (xlib:open-font (x-window-display window) "cursor"))
                   (shape (case kind (:not-allowed 0) (:pointer 60)
                                (:text 152) (:resize-horizontal 108)
                                (:resize-vertical 116) (otherwise 68))))
              (unwind-protect
                   (xlib:create-glyph-cursor
                    :source-font font :source-char shape
                    :mask-font font :mask-char (1+ shape)
                    :foreground (xlib:make-color :red 0 :green 0 :blue 0)
                    :background (xlib:make-color :red 1 :green 1 :blue 1))
                (xlib:close-font font))))))

(fn update-cursor ((window x-window))
  (let ((kind (if (x-window-context window)
                  (lui.widgets:cursor-at
                   (x-window-context window)
                   (x-window-pointer-x window) (x-window-pointer-y window))
                  :default)))
    (unless (eq kind (x-window-cursor-kind window))
      (setf (xlib:window-cursor (x-window-window window))
            (cursor-for window kind))
      (setf (x-window-cursor-kind window) kind))))

(fn pointer-buttons ((state integer))
  (logior (if (logtest state #x100) 1 0)
          (if (logtest state #x400) 2 0)))

(fn read-events ((window x-window) (delete integer))
  (let ((display (x-window-display window)) (events nil) (quit nil))
    (loop while (xlib:event-listen display 0) do
      (xlib:event-case (display :timeout 0 :discard-p t)
        (:leave-notify ()
          (setf (x-window-pointer-x window) -1 (x-window-pointer-y window) -1)
          (push (make-event :kind :move :x -1 :y -1) events) t)
        ((:focus-out :unmap-notify) ()
          (push (make-event :kind :cancel :buttons 0) events) t)
        (:key-press (code state)
          (let* ((context (x-window-context window))
                 (predicted (when context
                              (pending-input-context context events
                               (x-window-width window) (x-window-height window))))
                 (input (key-input display code state predicted)))
            (when input (push input events))) t)
        ((:button-press :button-release :motion-notify :enter-notify)
         (event-key x y code state)
          (cond ((and (eq event-key :button-press) (member code '(4 5)))
                 (push (make-event :kind :scroll :x x :y y
                                   :value (if (= code 4) -32 32)) events))
                ((or (member event-key '(:motion-notify :enter-notify))
                     (member code '(1 3)))
                 (setf (x-window-pointer-x window) x (x-window-pointer-y window) y)
                 (push (make-event
                        :kind (case event-key (:button-press :press)
                                    (:button-release :release) (otherwise :move))
                        :button (if (eql code 3) :secondary :primary)
                        :buttons (unless (eq event-key :enter-notify)
                                   (let ((buttons (pointer-buttons state))
                                         (bit (if (eql code 3) 2 1)))
                                     (case event-key
                                       (:button-press (logior buttons bit))
                                       (:button-release (logandc2 buttons bit))
                                       (otherwise buttons)))) :x x :y y) events))) t)
        (:configure-notify (width height)
          (setf (x-window-width window) (max 1 width)
                (x-window-height window) (max 1 height)) t)
        (:selection-clear () (setf (x-window-clipboard-text window) nil) t)
        (:selection-request (requestor selection target property time)
          (selection-request window requestor selection target property time) t)
        (:client-message (data) (when (= (aref data 0) delete) (setf quit t)) t)
        (otherwise () t)))
    (values (nreverse events) quit)))

(fn glx-visual (display screen)
  ;; Prefer multisampling; servers without it still get double-buffered RGB.
  (cffi:with-foreign-object (attrs :int 13)
    (loop :for v :in '(4 5 8 8 9 8 10 8 100000 1 100001 4 0)
          :for i :from 0 :do (setf (cffi:mem-aref attrs :int i) v))
    (let ((visual (choose-visual display screen attrs)))
      (when (cffi:null-pointer-p visual)
        (setf (cffi:mem-aref attrs :int 8) 0
              visual (choose-visual display screen attrs)))
      (when (cffi:null-pointer-p visual)
        (error "No double-buffered OpenGL visual on this X display."))
      visual)))

(fn open-window ((window x-window) info parent)
  (let* ((visual (cffi:foreign-slot-value info '(:struct visual-info) 'visual-id))
         (depth (cffi:foreign-slot-value info '(:struct visual-info) 'depth)))
    (setf (x-window-colormap window) (xlib:create-colormap visual parent)
          (x-window-window window)
          (xlib:create-window
           :parent parent :x 0 :y 0 :width (x-window-width window)
           :height (x-window-height window) :depth depth :visual visual
           :class :input-output :colormap (x-window-colormap window) :border 0
           :event-mask '(:key-press :button-press :button-release :enter-window
                         :leave-window :pointer-motion :exposure
                         :structure-notify :focus-change)))))

(fn wait-x11 (display (context context) events)
  (xlib:event-listen display (lui.frame::frame-wait context events))
  (lui.frame::limit-frame-rate context))

(fn draw-window ((window x-window) (gpu gpu) (context context)
                 (draw function) interactive delete)
  (loop
    (multiple-value-bind (events quit) (read-events window delete)
      (when quit (return context))
      (let ((w (x-window-width window)) (h (x-window-height window)))
        (setf (gpu-width gpu) w (gpu-height gpu) h
              (gpu-logical-width gpu) w (gpu-logical-height gpu) h)
        (with-frame (context w h :events events) (funcall draw)))
      (update-cursor window)
      (begin-gpu-frame gpu)
      (paint-frame (gpu-renderer gpu) context)
      (xlib:display-force-output (x-window-display window))
      (swap-buffers (x-window-glx-display window)
                    (xlib:window-id (x-window-window window)))
      (cffi:foreign-funcall "glFinish" :void)
      (unless interactive (return context))
      (wait-x11 (x-window-display window) context events))))

(fn run-x11 ((draw function) &key title width height (interactive t))
  "Run DRAW in a CLX window with the shared OpenGL renderer via GLX."
  (let* ((display (xlib:open-default-display))
         (native (open-glx-display (cffi:null-pointer)))
         (w (or width 720)) (h (or height 520))
         (window (make-x-window :display display :glx-display native :width w :height h))
         (glx (cffi:null-pointer)) (font nil) (gpu nil) (*unit* 8))
    (unwind-protect
         (progn
           (when (cffi:null-pointer-p native) (error "Cannot open GLX display."))
           (let* ((screen (xlib:display-default-screen display))
                  (info (glx-visual native (position screen (xlib:display-roots display))))
                  (delete (xlib:intern-atom display :wm_delete_window)))
             (unwind-protect
                  (progn (open-window window info (xlib:screen-root screen))
                         (xlib:display-finish-output display)
                         (setf glx (create-glx native info (cffi:null-pointer) 1)))
               (free-visual info))
             (when (or (cffi:null-pointer-p glx)
                       (zerop (make-current native (xlib:window-id (x-window-window window)) glx)))
               (error "Cannot activate the X11 OpenGL context."))
             (setf font (open-font) gpu (attach-gpu font w h)
                   (x-window-clipboard window) (xlib:intern-atom display :clipboard))
             (xlib:set-wm-properties (x-window-window window) :name (or title "LUI"))
             (setf (xlib:wm-protocols (x-window-window window))
                   (list :wm_delete_window))
             (xlib:map-window (x-window-window window))
             (xlib:display-finish-output display)
             (let ((context (make-context
                             :copy (lambda (text) (copy-clipboard window text))
                             :measure (lambda (widget width)
                                        (measure-widget (gpu-renderer gpu) widget width)))))
               (setf (x-window-context window) context)
               (draw-window window gpu context draw interactive delete))))
      (when gpu (close-gpu gpu))
      (when font (close-font font))
      (unless (cffi:null-pointer-p glx)
        (make-current native 0 (cffi:null-pointer)) (destroy-glx native glx))
      (maphash (lambda (kind cursor) (declare (ignore kind)) (xlib:free-cursor cursor))
               (x-window-cursors window))
      (when (x-window-window window) (xlib:destroy-window (x-window-window window)))
      (when (x-window-colormap window) (xlib:free-colormap (x-window-colormap window)))
      (xlib:close-display display)
      (unless (cffi:null-pointer-p native) (close-glx-display native)))))

(register-backend :x11 #'run-x11)
