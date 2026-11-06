(defpackage #:lui.x11
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.font #:lui.draw
        #:lui.gl)
  (:export #:run-x11))

(in-package #:lui.x11)

(cffi:define-foreign-library xlib (:unix (:or "libX11.so.6" "libX11.so")))

(cffi:use-foreign-library xlib)

(cffi:define-foreign-library xcursor
  (:unix (:or "libXcursor.so.1" "libXcursor.so")))
(ignore-errors (cffi:use-foreign-library xcursor))

(defmacro binding (name result &rest args)
  `(cffi:defcfun ,name ,result ,@args))

(binding ("XOpenDisplay" open-display) :pointer (name :pointer))

(binding ("XCloseDisplay" close-display) :int (display :pointer))

(binding ("XDefaultScreen" default-screen) :int (display :pointer))

(binding ("XRootWindow" root-window) :ulong (display :pointer) (screen :int))

(cffi:defcstruct visual-info
  (visual :pointer) (visual-id :ulong) (screen :int) (depth :int)
  (class :int) (red :ulong) (green :ulong) (blue :ulong)
  (map-size :int) (bits :int))

(cffi:defcstruct window-attributes
  (background-pixmap :ulong) (background :ulong) (border-pixmap :ulong)
  (border :ulong) (bit-gravity :int) (win-gravity :int) (backing-store :int)
  (backing-planes :ulong) (backing-pixel :ulong) (save-under :int)
  (event-mask :long) (propagate :long) (override :int) (colormap :ulong)
  (cursor :ulong))

(binding ("glXChooseVisual" choose-visual) :pointer
  (display :pointer) (screen :int) (attributes :pointer))
(binding ("glXCreateContext" create-glx) :pointer
  (display :pointer) (visual :pointer) (share :pointer) (direct :int))
(binding ("glXMakeCurrent" make-current) :int
  (display :pointer) (window :ulong) (context :pointer))
(binding ("glXSwapBuffers" swap-buffers) :void
  (display :pointer) (window :ulong))
(binding ("glXDestroyContext" destroy-glx) :void
  (display :pointer) (context :pointer))
(binding ("XCreateColormap" create-colormap) :ulong
  (display :pointer) (window :ulong) (visual :pointer) (alloc :int))
(binding ("XFreeColormap" free-colormap) :int
  (display :pointer) (colormap :ulong))
(binding ("XCreateWindow" create-window) :ulong
  (display :pointer) (parent :ulong) (x :int) (y :int)
  (width :uint) (height :uint) (border :uint) (depth :int) (class :uint)
  (visual :pointer) (mask :ulong) (attributes :pointer))

(binding ("XDestroyWindow" destroy-window)
  :int
  (display :pointer)
  (window :ulong))

(binding ("XStoreName" store-name)
  :int
  (display :pointer)
  (window :ulong)
  (name :string))

(binding ("XSelectInput" select-input)
  :int
  (display :pointer)
  (window :ulong)
  (mask :long))

(binding ("XMapWindow" map-window) :int (display :pointer) (window :ulong))

(binding ("XPending" pending) :int (display :pointer))

(binding ("XNextEvent" next-event) :int (display :pointer) (event :pointer))

(binding ("XFlush" flush-display) :int (display :pointer))

(binding ("XSync" sync-display) :int (display :pointer) (discard :int))

(binding ("XInternAtom" intern-atom)
  :ulong
  (display :pointer)
  (name :string)
  (only :int))

(binding ("XSetWMProtocols" set-protocols)
  :int
  (display :pointer)
  (window :ulong)
  (atoms :pointer)
  (count :int))

(binding ("XLookupString" lookup-string)
  :int
  (event :pointer)
  (buffer :pointer)
  (size :int)
  (keysym :pointer)
  (compose :pointer))

(binding ("XFree" free-memory) :int (data :pointer))

(binding ("XCreateFontCursor" create-font-cursor) :ulong
  (display :pointer) (shape :uint))
(binding ("XDefineCursor" define-cursor) :int
  (display :pointer) (window :ulong) (cursor :ulong))
(binding ("XFreeCursor" free-cursor) :int (display :pointer) (cursor :ulong))

(binding ("XSetSelectionOwner" set-selection-owner) :int
  (display :pointer) (selection :ulong) (owner :ulong) (time :ulong))
(binding ("XChangeProperty" change-property) :int
  (display :pointer) (window :ulong) (property :ulong) (type :ulong)
  (format :int) (mode :int) (data :pointer) (count :int))
(binding ("XSendEvent" send-event) :int
  (display :pointer) (window :ulong) (propagate :int) (mask :long)
  (event :pointer))
(binding ("XMaxRequestSize" max-request-size) :long (display :pointer))

(cffi:defcstruct selection-request
  (type :int) (serial :ulong) (send :int) (display :pointer)
  (owner :ulong) (requestor :ulong) (selection :ulong) (target :ulong)
  (property :ulong) (time :ulong))
(cffi:defcstruct selection-notify
  (type :int) (serial :ulong) (send :int) (display :pointer)
  (requestor :ulong) (selection :ulong) (target :ulong) (property :ulong)
  (time :ulong))

(cffi:defcstruct key-event
  (type :int)
  (serial :ulong)
  (send :int)
  (display :pointer)
  (window :ulong)
  (root :ulong)
  (subwindow :ulong)
  (time :ulong)
  (x :int)
  (y :int)
  (root-x :int)
  (root-y :int)
  (state :uint)
  (code :uint)
  (same-screen :int))

(cffi:defcstruct configure-event
  (type :int)
  (serial :ulong)
  (send :int)
  (display :pointer)
  (event :ulong)
  (window :ulong)
  (x :int)
  (y :int)
  (width :int)
  (height :int)
  (border :int)
  (above :ulong)
  (override :int))

(cffi:defcstruct client-event
  (type :int)
  (serial :ulong)
  (send :int)
  (display :pointer)
  (window :ulong)
  (message-type :ulong)
  (format :int)
  (data :long :count 5))

(defstruct x-window
  display context
  (window 0 :type integer) (colormap 0 :type integer)
  (clipboard 0 :type integer) (clipboard-text nil :type (or null string))
  (width 720 :type integer) (height 520 :type integer)
  (cursors (make-hash-table :test 'eq) :type hash-table)
  cursor-kind (pointer-x -1 :type real) (pointer-y -1 :type real))

(fn copy-clipboard ((window x-window) (text string))
  (setf (x-window-clipboard-text window) (copy-seq text))
  (set-selection-owner (x-window-display window) (x-window-clipboard window)
                       (x-window-window window) 0)
  (flush-display (x-window-display window)))

(fn selection-request ((window x-window) event)
  (let* ((display (x-window-display window))
         (targets (intern-atom display "TARGETS" 0))
         (utf8 (intern-atom display "UTF8_STRING" 0))
         (text-atom (intern-atom display "TEXT" 0))
         (text (x-window-clipboard-text window))
         (result 0))
    (cffi:with-foreign-slots
        ((requestor selection target property time) event
         (:struct selection-request))
      (let ((destination (if (zerop property) target property)))
        (when (and text (= selection (x-window-clipboard window)))
          (cond
            ((= target targets)
             (cffi:with-foreign-object (atoms :ulong 4)
               (loop :for atom :in (list targets utf8 text-atom 31)
                     :for index :from 0
                     :do (setf (cffi:mem-aref atoms :ulong index) atom))
               (change-property display requestor destination 4 32 0 atoms 4))
             (setf result destination))
            ((member target (list utf8 text-atom 31))
             (let ((legacy (= target 31)))
               (cffi:with-foreign-string
                   ((bytes byte-size)
                    (if legacy
                        (map 'string (lambda (char)
                                       (if (< (char-code char) 256) char #\?))
                             text) text)
                    :encoding (if legacy :iso-8859-1 :utf-8))
                 ;; Refuse an oversized direct transfer without an X error.
                 (when (< byte-size (- (* 4 (max-request-size display)) 64))
                   (change-property display requestor destination
                                    (if legacy 31 utf8) 8 0
                                    bytes (1- byte-size))
                   (setf result destination)))))))
        (cffi:with-foreign-object (reply :long 24)
          (dotimes (index 24) (setf (cffi:mem-aref reply :long index) 0))
          (setf
           (cffi:foreign-slot-value reply '(:struct selection-notify)
                                    'type) 31
           (cffi:foreign-slot-value reply '(:struct selection-notify)
                                    'display) display
           (cffi:foreign-slot-value reply '(:struct selection-notify)
                                    'requestor) requestor
           (cffi:foreign-slot-value reply '(:struct selection-notify)
                                    'selection) selection
           (cffi:foreign-slot-value reply '(:struct selection-notify)
                                    'target) target
           (cffi:foreign-slot-value reply '(:struct selection-notify)
                                    'property) result
           (cffi:foreign-slot-value reply '(:struct selection-notify)
                                    'time) time)
          (send-event display requestor 0 0 reply)
          (flush-display display))))))

(fn key-input (event &optional context)
  (cffi:with-foreign-objects ((buffer :char 64) (symbol :ulong))
    (let* ((length (lookup-string event buffer 64 symbol (cffi:null-pointer)))
           (code (cffi:mem-ref symbol :ulong))
           (state (cffi:foreign-slot-value event '(:struct key-event) 'state))
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
            ((and (plusp length) (not control) (not alt))
             (make-event :kind :text :value
                         (cffi:foreign-string-to-lisp
                          buffer :count length :encoding :iso-8859-1)))))))

(fn cursor-for ((window x-window) (kind symbol))
  (or (gethash kind (x-window-cursors window))
      (setf (gethash kind (x-window-cursors window))
            (let ((cursor
                    (if (ignore-errors
                          (cffi:foreign-symbol-pointer
                           "XcursorLibraryLoadCursor"))
                        (cffi:foreign-funcall
                         "XcursorLibraryLoadCursor"
                         :pointer (x-window-display window)
                         :string (case kind
                                   (:not-allowed "not-allowed")
                                   (:pointer "pointer") (:text "text")
                                   (:resize-horizontal "ew-resize")
                                   (:resize-vertical "ns-resize")
                                   (otherwise "default"))
                         :ulong)
                        0)))
              (if (plusp cursor) cursor
                  (create-font-cursor
                   (x-window-display window)
                   (case kind (:not-allowed 0) (:pointer 60)
                         (:text 152) (:resize-horizontal 108)
                         (:resize-vertical 116)
                         (otherwise 68))))))))

(fn update-cursor ((window x-window))
  (let ((kind (if (x-window-context window)
                  (lui.widgets:cursor-at
                   (x-window-context window)
                   (x-window-pointer-x window) (x-window-pointer-y window))
                  :default)))
    (unless (eq kind (x-window-cursor-kind window))
      (define-cursor (x-window-display window) (x-window-window window)
                     (cursor-for window kind))
      (setf (x-window-cursor-kind window) kind))))

(fn pointer-buttons ((state integer))
  (logior (if (logtest state #x100) 1 0)
          (if (logtest state #x400) 2 0)))

(fn read-events ((window x-window) (delete integer))
  (let ((display (x-window-display window))
        (events nil)
        (quit nil))
    (cffi:with-foreign-object (event :long 24)
      (loop :while (plusp (pending display))
            :do (next-event display event)
            (case (cffi:mem-ref event :int)
              (8
               (setf (x-window-pointer-x window) -1
                     (x-window-pointer-y window) -1)
               (push (make-event :kind :move :x -1 :y -1) events))
              ((10 18) (push (make-event :kind :cancel :buttons 0) events))
              (2
               (let* ((context (x-window-context window))
                      (predicted
                        (when context
                          (pending-input-context
                           context events (x-window-width window)
                           (x-window-height window))))
                      (input (key-input event predicted)))
                 (when input (push input events))))
              ((4 5 6 7)
               (cffi:with-foreign-slots
                   ((type x y code state) event (:struct key-event))
                 (cond
                   ((and (= type 4) (member code '(4 5)))
                    (push (make-event :kind :scroll :x x :y y
                                      :value (if (= code 4) -32 32))
                          events))
                   ((or (member type '(6 7)) (member code '(1 3)))
                    (setf (x-window-pointer-x window) x
                          (x-window-pointer-y window) y)
                    (push (make-event
                           :kind (case type
                                   (4 :press)
                                   (5 :release)
                                   (otherwise :move))
                           :button (if (and (member type '(4 5))
                                            (= code 3))
                                       :secondary :primary)
                           :buttons
                           (unless (= type 7)
                             (let ((buttons (pointer-buttons state))
                                   (bit (if (= code 3) 2 1)))
                               (case type
                                 (4 (logior buttons bit))
                                 (5 (logandc2 buttons bit))
                                 (otherwise buttons))))
                           :x x :y y)
                          events)))))
              (22
               (cffi:with-foreign-slots
                   ((width height) event (:struct configure-event))
                 (setf (x-window-width window) (max 1 width)
                       (x-window-height window) (max 1 height))))
              (29 (setf (x-window-clipboard-text window) nil))
              (30 (selection-request window event))
              (33
               (when (= (cffi:mem-ref
                         (cffi:foreign-slot-pointer
                          event '(:struct client-event) 'data)
                         :long)
                        delete)
                 (setf quit t)))
              (otherwise nil))))
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
  (let* ((display (x-window-display window))
         (visual (cffi:foreign-slot-value
                  info '(:struct visual-info) 'visual))
         (depth (cffi:foreign-slot-value info '(:struct visual-info) 'depth)))
    (setf (x-window-colormap window)
          (create-colormap display parent visual 0))
    (cffi:with-foreign-object (attrs '(:struct window-attributes))
      (cffi:with-foreign-slots ((colormap border) attrs
                                (:struct window-attributes))
        (setf colormap (x-window-colormap window) border 0))
      (setf (x-window-window window)
            (create-window display parent 0 0
                           (x-window-width window) (x-window-height window)
                           0 depth 1 visual #x2008 attrs)))))

(cffi:defcstruct poll-fd (fd :int) (events :short) (revents :short))

(fn wait-x11 (display (context context) events)
  (when (zerop (pending display))
    (cffi:with-foreign-object (p '(:struct poll-fd))
      (cffi:with-foreign-slots ((fd events) p (:struct poll-fd))
        (setf fd (cffi:foreign-funcall "XConnectionNumber"
                                       :pointer display :int)
              events 1))
      (cffi:foreign-funcall "poll" :pointer p :ulong 1
                            :int (ceiling (* 1000
                                             (lui.frame::frame-wait
                                              context events))) :int)))
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
      (swap-buffers (x-window-display window) (x-window-window window))
      (cffi:foreign-funcall "glFinish" :void)
      (unless interactive (return context))
      (wait-x11 (x-window-display window) context events))))

(fn run-x11 ((draw function) &key title width height (interactive t))
  "Run DRAW in an Xlib window using the shared OpenGL renderer via GLX."
  (let* ((display (open-display (cffi:null-pointer)))
         (w (or width 720)) (h (or height 520))
         (window (make-x-window :display display :width w :height h))
         (glx (cffi:null-pointer)) (font nil) (gpu nil) (*unit* 8))
    (when (cffi:null-pointer-p display) (error "Cannot open X11 display."))
    (unwind-protect
         (let* ((screen (default-screen display))
                (info (glx-visual display screen))
                (delete (intern-atom display "WM_DELETE_WINDOW" 0)))
           (unwind-protect
                (progn
                  (open-window window info (root-window display screen))
                  (setf glx (create-glx display info (cffi:null-pointer) 1)))
             (free-memory info))
           (when (or (cffi:null-pointer-p glx)
                     (zerop (make-current display (x-window-window window)
                                          glx)))
             (error "Cannot activate the X11 OpenGL context."))
           (setf font (open-font) gpu (attach-gpu font w h)
                 (x-window-clipboard window)
                 (intern-atom display "CLIPBOARD" 0))
           (store-name display (x-window-window window) title)
           (select-input display (x-window-window window)
                         (logior 1 4 8 16 32 64 #x8000 #x20000 #x200000))
           (cffi:with-foreign-object (atom :ulong)
             (setf (cffi:mem-ref atom :ulong) delete)
             (set-protocols display (x-window-window window) atom 1))
           (map-window display (x-window-window window))
           (let ((context
                   (make-context
                    :copy (lambda (text) (copy-clipboard window text))
                    :measure (lambda (widget width)
                               (measure-widget (gpu-renderer gpu)
                                               widget width)))))
             (setf (x-window-context window) context)
             (draw-window window gpu context draw interactive delete)))
      (when gpu (close-gpu gpu))
      (when font (close-font font))
      (unless (cffi:null-pointer-p glx)
        (make-current display 0 (cffi:null-pointer))
        (destroy-glx display glx))
      (maphash (lambda (kind cursor)
                 (declare (ignore kind)) (free-cursor display cursor))
               (x-window-cursors window))
      (when (plusp (x-window-window window))
        (destroy-window display (x-window-window window)))
      (when (plusp (x-window-colormap window))
        (free-colormap display (x-window-colormap window)))
      (close-display display))))

(register-backend :x11 #'run-x11)
