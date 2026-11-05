(defpackage #:lui.x11
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.font #:lui.draw)
  (:export #:run-x11))

(in-package #:lui.x11)

(cffi:define-foreign-library xlib (:unix (:or "libX11.so.6" "libX11.so")))

(cffi:define-foreign-library xrender
  (:unix (:or "libXrender.so.1" "libXrender.so")))

(cffi:use-foreign-library xlib)

(cffi:use-foreign-library xrender)

(cffi:define-foreign-library xcursor
  (:unix (:or "libXcursor.so.1" "libXcursor.so")))
(ignore-errors (cffi:use-foreign-library xcursor))

(defmacro binding (name result &rest args)
  `(cffi:defcfun ,name ,result ,@args))

(binding ("XOpenDisplay" open-display) :pointer (name :pointer))

(binding ("XCloseDisplay" close-display) :int (display :pointer))

(binding ("XDefaultScreen" default-screen) :int (display :pointer))

(binding ("XRootWindow" root-window) :ulong (display :pointer) (screen :int))

(binding ("XDefaultVisual" default-visual)
  :pointer
  (display :pointer)
  (screen :int))

(binding ("XDefaultDepth" default-depth)
  :int
  (display :pointer)
  (screen :int))

(binding ("XCreateSimpleWindow" create-window)
  :ulong
  (display :pointer)
  (parent :ulong)
  (x :int)
  (y :int)
  (width :uint)
  (height :uint)
  (border :uint)
  (border-pixel :ulong)
  (background :ulong))

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

(binding ("XCreatePixmap" create-pixmap)
  :ulong
  (display :pointer)
  (drawable :ulong)
  (width :uint)
  (height :uint)
  (depth :uint))

(binding ("XFreePixmap" free-pixmap) :int (display :pointer) (pixmap :ulong))

(binding ("XLookupString" lookup-string)
  :int
  (event :pointer)
  (buffer :pointer)
  (size :int)
  (keysym :pointer)
  (compose :pointer))

(binding ("XFree" free-memory) :int (data :pointer))

(binding ("XRenderQueryFilters" query-filters)
  :pointer (display :pointer) (drawable :ulong))

(binding ("XRenderSetPictureFilter" set-filter)
  :void
  (display :pointer)
  (picture :ulong)
  (filter :string)
  (parameters :pointer)
  (count :int))

(binding ("XRenderChangePicture" change-picture)
  :void
  (display :pointer)
  (picture :ulong)
  (mask :ulong)
  (attributes :pointer))

(cffi:defcstruct filters
  (count :int)
  (names :pointer)
  (alias-count :int)
  (aliases :pointer))

(binding ("XRenderFindVisualFormat" visual-format)
  :pointer
  (display :pointer)
  (visual :pointer))

(binding ("XRenderFindStandardFormat" standard-format)
  :pointer
  (display :pointer)
  (format :int))

(binding ("XRenderCreatePicture" create-picture)
  :ulong
  (display :pointer)
  (drawable :ulong)
  (format :pointer)
  (mask :ulong)
  (attributes :pointer))

(binding ("XRenderFreePicture" free-picture)
  :void
  (display :pointer)
  (picture :ulong))

(binding ("XRenderCreateSolidFill" solid-fill)
  :ulong
  (display :pointer)
  (color :pointer))

(binding ("XRenderSetPictureClipRectangles" set-clip)
  :void
  (display :pointer)
  (picture :ulong)
  (x :int)
  (y :int)
  (rectangles :pointer)
  (count :int))

(binding ("XRenderCompositeTriangles" composite-triangles)
  :void
  (display :pointer)
  (op :int)
  (src :ulong)
  (dst :ulong)
  (mask-format :pointer)
  (x :int)
  (y :int)
  (triangles :pointer)
  (count :int))

(binding ("XRenderComposite" composite)
  :void
  (display :pointer)
  (op :int)
  (src :ulong)
  (mask :ulong)
  (dst :ulong)
  (sx :int)
  (sy :int)
  (mx :int)
  (my :int)
  (dx :int)
  (dy :int)
  (width :uint)
  (height :uint))

(binding ("XCreateFontCursor" create-font-cursor) :ulong
  (display :pointer) (shape :uint))
(binding ("XDefineCursor" define-cursor) :int
  (display :pointer) (window :ulong) (cursor :ulong))
(binding ("XFreeCursor" free-cursor) :int (display :pointer) (cursor :ulong))

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

(cffi:defcstruct rectangle
  (x :short)
  (y :short)
  (width :ushort)
  (height :ushort))

(defstruct x-window
  display
  (window 0 :type integer)
  (picture 0 :type integer)
  (back 0 :type integer)
  (pixmap 0 :type integer)
  (backdrop 0 :type integer)
  (scratch 0 :type integer)
  (scratch-pixmap 0 :type integer)
  (glass-mask 0 :type integer)
  (mask-pixmap 0 :type integer)
  (convolution-p nil :type boolean)
  format
  mask-format
  context
  (depth 0 :type integer)
  (width 640 :type integer)
  (height 480 :type integer)
  (colors (make-hash-table :test 'equal) :type hash-table)
  (cursors (make-hash-table :test 'eq) :type hash-table)
  cursor-kind (pointer-x -1 :type real) (pointer-y -1 :type real))

(fn convolution-supported-p ((window x-window))
  (let ((filters (query-filters (x-window-display window)
                                (x-window-window window))))
    (unless (cffi:null-pointer-p filters)
      (unwind-protect
           (cffi:with-foreign-slots ((count names) filters (:struct filters))
             (loop :for index :below count
                   :thereis (string= "convolution"
                                     (cffi:foreign-string-to-lisp
                                      (cffi:mem-aref names :pointer index)))))
        (free-memory filters)))))

(fn free-buffer ((window x-window))
  (let ((display (x-window-display window)))
    (dolist (picture (list (x-window-back window)
                           (x-window-backdrop window)
                           (x-window-scratch window)
                           (x-window-glass-mask window)))
      (when (plusp picture) (free-picture display picture)))
    (dolist (pixmap (list (x-window-pixmap window)
                          (x-window-scratch-pixmap window)
                          (x-window-mask-pixmap window)))
      (when (plusp pixmap) (free-pixmap display pixmap)))
    (setf (x-window-back window) 0
          (x-window-backdrop window) 0
          (x-window-scratch window) 0
          (x-window-glass-mask window) 0
          (x-window-pixmap window) 0
          (x-window-scratch-pixmap window) 0
          (x-window-mask-pixmap window) 0)))

(fn resize-buffer ((window x-window) (width integer) (height integer))
  (free-buffer window)
  (setf (x-window-width window) (max 1 width)
        (x-window-height window) (max 1 height))
  (let ((display (x-window-display window)))
    (flet ((pixmap (depth)
             (create-pixmap display (x-window-window window)
                            (x-window-width window)
                            (x-window-height window) depth))
           (picture (pixmap format)
             (create-picture display pixmap format 0 (cffi:null-pointer))))
      (setf (x-window-pixmap window) (pixmap (x-window-depth window))
            (x-window-back window)
            (picture (x-window-pixmap window) (x-window-format window)))
      (when (x-window-convolution-p window)
        ;; The independent source picture has no widget clip. Sampling the
        ;; clipped destination would discard pixels needed by the blur kernel.
        (setf (x-window-backdrop window)
              (picture (x-window-pixmap window) (x-window-format window))
              (x-window-scratch-pixmap window)
              (pixmap (x-window-depth window))
              (x-window-scratch window)
              (picture (x-window-scratch-pixmap window)
                       (x-window-format window))
              (x-window-mask-pixmap window) (pixmap 8)
              (x-window-glass-mask window)
              (picture (x-window-mask-pixmap window)
                       (x-window-mask-format window)))
        (cffi:with-foreign-object (repeat :int)
          ;; RepeatPad extends the window edge through the convolution kernel.
          (setf (cffi:mem-ref repeat :int) 2)
          (change-picture display (x-window-backdrop window) 1 repeat)
          (change-picture display (x-window-scratch window) 1 repeat))))))

(fn color-picture ((window x-window) (color string) (alpha real))
  (or (gethash (list color alpha) (x-window-colors window))
      (setf (gethash (list color alpha) (x-window-colors window))
            (cffi:with-foreign-object (rgba :ushort 4)
              (loop :for component :in (color-components color alpha) :for i
                    :from 0 :do
                    (setf (cffi:mem-aref rgba :ushort i)
                          (round (* 65535 component (if (< i 3) alpha 1)))))
              (solid-fill (x-window-display window) rgba)))))

(fn draw-polygons
    ((window x-window) (contours list) (color string) (alpha real)
     &optional target)
  (let ((triangles nil))
    (trapezoids
     contours
     (lambda (quad)
       (push (list (first quad) (second quad) (third quad)) triangles)
       (push (list (first quad) (third quad) (fourth quad)) triangles)))
    (when triangles
      (cffi:with-foreign-object (data :int32 (* 6 (length triangles)))
        (loop :for triangle :in triangles :for i :from 0 :do
              (loop :for point :in triangle :for j :from (* i 6) :by 2 :do
                    (setf (cffi:mem-aref data :int32 j)
                          (round (* 65536 (car point)))
                          (cffi:mem-aref data :int32 (1+ j))
                          (round (* 65536 (cdr point))))))
        (composite-triangles
         (x-window-display window) 3 (color-picture window color alpha)
         (or target (x-window-back window)) (x-window-mask-format window)
         0 0 data (length triangles))))))

(fn gaussian-filter ((window x-window) picture (radius integer)
                     horizontal-p)
  (let* ((size (1+ (* 2 radius)))
         (sigma (max 0.5 (/ radius 2.0)))
         (weights (loop :for offset :from (- radius) :to radius
                        :collect (exp (- (/ (* offset offset)
                                            (* 2 sigma sigma))))))
         (total (reduce #'+ weights))
         (fixed (mapcar (lambda (weight) (round (* 65536 (/ weight total))))
                        weights)))
    ;; Preserve a constant background exactly despite fixed-point rounding.
    (incf (nth radius fixed) (- 65536 (reduce #'+ fixed)))
    (cffi:with-foreign-object (parameters :int32 (+ 2 size))
      (setf (cffi:mem-aref parameters :int32 0)
            (* 65536 (if horizontal-p size 1))
            (cffi:mem-aref parameters :int32 1)
            (* 65536 (if horizontal-p 1 size)))
      (loop :for weight :in fixed :for index :from 2
            :do (setf (cffi:mem-aref parameters :int32 index) weight))
      (set-filter (x-window-display window) picture "convolution"
                  parameters (+ 2 size)))))

(fn blur-backdrop ((window x-window) (box box) (corner-radius real)
                   (blur-radius real))
  (when (and (x-window-convolution-p window) (plusp blur-radius))
    (let* ((display (x-window-display window))
           ;; Bound native filter size while retaining a useful frosted radius.
           (radius (min 64 (ceiling blur-radius)))
           (x (max 0 (floor (box-x box))))
           (y (max 0 (floor (box-y box))))
           (right (min (x-window-width window)
                       (ceiling (+ (box-x box) (box-width box)))))
           (bottom (min (x-window-height window)
                        (ceiling (+ (box-y box) (box-height box)))))
           (top (max 0 (- y radius)))
           (end (min (x-window-height window) (+ bottom radius))))
      (when (and (< x right) (< y bottom))
        (gaussian-filter window (x-window-backdrop window) radius t)
        (composite display 1 (x-window-backdrop window) 0
                   (x-window-scratch window) x top 0 0 x top
                   (- right x) (- end top))
        (composite display 1 (color-picture window "#000000" 0) 0
                   (x-window-glass-mask window) 0 0 0 0 0 0
                   (x-window-width window) (x-window-height window))
        (draw-polygons window (list (rounded-polygon box corner-radius))
                       "#ffffff" 1 (x-window-glass-mask window))
        (gaussian-filter window (x-window-scratch window) radius nil)
        (composite display 3 (x-window-scratch window)
                   (x-window-glass-mask window) (x-window-back window)
                   x y x y x y (- right x) (- bottom y))))))

(fn clip-window ((window x-window) (box box))
  (cffi:with-foreign-object (rect '(:struct rectangle))
    (cffi:with-foreign-slots ((x y width height) rect (:struct rectangle))
      (setf x (round (box-x box)) y (round (box-y box)) width
            (max 0 (floor (box-width box))) height
            (max 0 (floor (box-height box)))))
    (set-clip (x-window-display window) (x-window-back window) 0 0 rect 1)))

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
                              (#xff08 . :backspace) (#xffff . :delete)))))
           (name (case code
                   (#xff51 "ArrowLeft") (#xff53 "ArrowRight")
                   (#xff08 "Backspace")
                   (otherwise (if (<= 32 code 126)
                                  (string (code-char code)) ""))))
           (command (when text-p
                      (lui.widgets:readline-key name :control control
                                                :alt alt :shift shift))))
      (cond (command (make-event :kind :key :key command))
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
                                   (otherwise "default"))
                         :ulong)
                        0)))
              (if (plusp cursor) cursor
                  (create-font-cursor
                   (x-window-display window)
                   (case kind (:not-allowed 0) (:pointer 60)
                         (:text 152) (otherwise 68))))))))

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
              (2
               (let ((input (key-input event (x-window-context window))))
                 (when input (push input events))))
              ((4 5 6 7)
               (cffi:with-foreign-slots
                   ((type x y code) event (:struct key-event))
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
                           :x x :y y)
                          events)))))
              (22
               (cffi:with-foreign-slots
                   ((width height) event (:struct configure-event))
                 (unless (and (= width (x-window-width window))
                              (= height (x-window-height window)))
                   (resize-buffer window width height))))
              (33
               (when (= (cffi:mem-ref
                         (cffi:foreign-slot-pointer
                          event '(:struct client-event) 'data)
                         :long)
                        delete)
                 (setf quit t)))
              (otherwise nil))))
    (values (nreverse events) quit)))

(fn full-window-clip ((window x-window))
  (clip-window window (make-box :width (x-window-width window)
                                :height (x-window-height window))))

(fn draw-window ((window x-window) (renderer renderer) (context context)
                 (draw function) interactive (delete integer))
  (let ((display (x-window-display window)))
    (loop
     (multiple-value-bind (events quit) (read-events window delete)
       (when quit (return context))
       (with-frame (context (x-window-width window) (x-window-height window)
                            :events events)
         (funcall draw))
       (update-cursor window)
       (full-window-clip window)
       (composite display 1 (color-picture window "#202532" 1) 0
                  (x-window-back window) 0 0 0 0 0 0
                  (x-window-width window) (x-window-height window))
       (paint-frame renderer context)
       ;; A source clip also clips the final copy. Restore the whole frame.
       (full-window-clip window)
       (composite display 1 (x-window-back window) 0
                  (x-window-picture window) 0 0 0 0 0 0
                  (x-window-width window) (x-window-height window))
       (flush-display display)
       (unless interactive
         (sync-display display 0)
         (return context))
       (sleep 0.016)))))

(fn run-x11 ((draw function) &key title width height (interactive t))
  (let* ((display (open-display (cffi:null-pointer)))
         (window (make-x-window :display display))
         (font nil)
         (*unit* 8))
    (when (cffi:null-pointer-p display) (error "Cannot open X11 display."))
    (unwind-protect
         (let* ((screen (default-screen display))
                (format
                 (visual-format display (default-visual display screen)))
                (delete (intern-atom display "WM_DELETE_WINDOW" 0)))
           (when (cffi:null-pointer-p format)
             (error "XRender is unavailable."))
           (setf (x-window-depth window) (default-depth display screen)
                 (x-window-format window) format
                 (x-window-mask-format window)
                 (standard-format display 2)
                 (x-window-window window)
                 (create-window display (root-window display screen) 0 0
                                (or width 720) (or height 520) 0 0 0)
                 (x-window-picture window)
                 (create-picture display (x-window-window window) format 0
                                 (cffi:null-pointer))
                 font (open-font))
           (store-name display (x-window-window window) title)
           (select-input display (x-window-window window)
                         (logior 1 4 8 16 32 64 #x8000 #x20000))
           (cffi:with-foreign-object (atom :ulong)
             (setf (cffi:mem-ref atom :ulong) delete)
             (set-protocols display (x-window-window window) atom 1))
           (setf (x-window-convolution-p window)
                 (not (null (convolution-supported-p window))))
           (unless (x-window-convolution-p window)
             (warn
              "XRender convolution is unavailable; glass uses tint and rim only."))
           (resize-buffer window (or width 720) (or height 520))
           (map-window display (x-window-window window))
           (let* ((renderer
                   (make-renderer
                    :font font
                    :polygons (lambda (polys color alpha)
                                (draw-polygons window polys color alpha))
                    :clip (lambda (box) (clip-window window box))
                    :glass (lambda (box radius frost)
                             (blur-backdrop window box radius frost))))
                  (context
                   (make-context
                    :measure (lambda (widget width)
                               (measure-widget renderer widget width)))))
             (setf (x-window-context window) context)
             (draw-window window renderer context draw interactive delete)))
      (when font (close-font font))
      (maphash
       (lambda (key picture)
         (declare (ignore key))
         (free-picture display picture)) (x-window-colors window))
      (maphash (lambda (kind cursor)
                 (declare (ignore kind)) (free-cursor display cursor))
               (x-window-cursors window))
      (free-buffer window)
      (when (plusp (x-window-picture window))
        (free-picture display (x-window-picture window)))
      (when (plusp (x-window-window window))
        (destroy-window display (x-window-window window)))
      (close-display display))))

(register-backend :x11 #'run-x11)
