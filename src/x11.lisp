(defpackage #:lui.x11
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.font #:lui.draw)
  (:export #:run-x11))

(in-package #:lui.x11)

(cffi:define-foreign-library xlib (:unix (:or "libX11.so.6" "libX11.so")))

(cffi:define-foreign-library xrender
  (:unix (:or "libXrender.so.1" "libXrender.so")))

(cffi:use-foreign-library xlib)

(cffi:use-foreign-library xrender)

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
  format
  mask-format
  (depth 0 :type integer)
  (width 640 :type integer)
  (height 480 :type integer)
  (colors (make-hash-table :test 'equal) :type hash-table))

(fn resize-buffer ((window x-window) (width integer) (height integer))
  (let ((display (x-window-display window)))
    (when (plusp (x-window-back window))
      (free-picture display (x-window-back window)))
    (when (plusp (x-window-pixmap window))
      (free-pixmap display (x-window-pixmap window)))
    (setf (x-window-width window) (max 1 width) (x-window-height window)
      (max 1 height) (x-window-pixmap window)
      (create-pixmap display (x-window-window window) (max 1 width)
        (max 1 height) (x-window-depth window)) (x-window-back window)
      (create-picture display (x-window-pixmap window)
        (x-window-format window) 0 (cffi:null-pointer)))))

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
  ((window x-window) (contours list) (color string) (alpha real))
  (let ((triangles nil))
    (trapezoids contours
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
        (composite-triangles (x-window-display window) 3
          (color-picture window color alpha) (x-window-back window)
          (x-window-mask-format window) 0 0 data (length triangles))))))

(fn clip-window ((window x-window) (box box))
  (cffi:with-foreign-object (rect '(:struct rectangle))
    (cffi:with-foreign-slots ((x y width height) rect (:struct rectangle))
      (setf x (round (box-x box)) y (round (box-y box)) width
        (max 0 (floor (box-width box))) height
        (max 0 (floor (box-height box)))))
    (set-clip (x-window-display window) (x-window-back window) 0 0 rect 1)))

(fn key-input (event)
  (cffi:with-foreign-objects ((buffer :char 64) (symbol :ulong))
    (let*
      ((length
          (lookup-string event buffer 64 symbol (cffi:null-pointer)))
        (code (cffi:mem-ref symbol :ulong))
        (key
          (cdr
            (assoc code
              '((#xff51 . :left) (#xff53 . :right) (#xff52 . :up)
                 (#xff54 . :down) (#xff50 . :home) (#xff57 . :end)
                 (#xff08 . :backspace) (#xffff . :delete))))))
      (cond ((= code #xff09) (make-event :kind :tab))
        ((= code #xff0d) (make-event :kind :activate))
        (key (make-event :kind :key :key key))
        ((plusp length)
          (make-event :kind :text :value
            (cffi:foreign-string-to-lisp buffer :count length :encoding
              :iso-8859-1)))))))

(fn run-x11 ((draw function) &key title width height (interactive t))
  (let*
    ((display (open-display (cffi:null-pointer)))
      (window (make-x-window :display display)) (font nil) (*unit* 8))
    (when (cffi:null-pointer-p display) (error "Cannot open X11 display."))
    (unwind-protect
      (let*
        ((screen (default-screen display))
          (format
            (visual-format display (default-visual display screen)))
          (delete (intern-atom display "WM_DELETE_WINDOW" 0)))
        (when (cffi:null-pointer-p format)
          (error "XRender is unavailable."))
        (setf (x-window-depth window) (default-depth display screen)
          (x-window-format window) format (x-window-mask-format window)
          (standard-format display 2) (x-window-window window)
          (create-window display (root-window display screen) 0 0
            (or width 720) (or height 520) 0 0 0)
          (x-window-picture window)
          (create-picture display (x-window-window window) format 0
            (cffi:null-pointer)) font (open-font))
        (store-name display (x-window-window window) title)
        (select-input display (x-window-window window)
          (logior 1 4 8 64 #x8000 #x20000))
        (cffi:with-foreign-object (atom :ulong)
          (setf (cffi:mem-ref atom :ulong) delete)
          (set-protocols display (x-window-window window) atom 1))
        (resize-buffer window (or width 720) (or height 520))
        (map-window display (x-window-window window))
        (let*
          ((renderer
              (make-renderer :font font :polygons
                (lambda (polys color alpha)
                  (draw-polygons window polys color alpha)) :clip
                (lambda (box) (clip-window window box))))
            (context
              (make-context :measure
                (lambda (widget width)
                  (measure-widget renderer widget width)))) (quit nil))
          (cffi:with-foreign-object (event :long 24)
            (loop :until quit :do
              (let ((events nil))
                (loop :while (plusp (pending display)) :do
                  (next-event display event)
                  (case (cffi:mem-ref event :int)
                    (2
                      (let ((input (key-input event)))
                        (when input (push input events))))
                    ((4 5 6)
                      (cffi:with-foreign-slots
                        ((type x y code) event
                          (:struct key-event))
                        (cond
                          ((and (= type 4)
                              (member code '(4 5)))
                            (push
                              (make-event :kind :scroll :x x
                                :y y :value
                                (if (= code 4) -32 32)) events))
                          ((or (= type 6) (= code 1))
                            (push
                              (make-event :kind
                                (case type
                                  (4 :press)
                                  (5 :release)
                                  (otherwise :move)) :x x :y y)
                              events)))))
                    (22
                      (cffi:with-foreign-slots
                        ((width height) event
                          (:struct configure-event))
                        (unless
                          (and (= width (x-window-width window))
                            (= height (x-window-height window)))
                          (resize-buffer window width height))))
                    (33
                      (when
                        (=
                          (cffi:mem-ref
                            (cffi:foreign-slot-pointer event
                              '(:struct client-event) 'data)
                            :long) delete) (setf quit t)))
                    (otherwise nil)))
                (with-frame
                  (context (x-window-width window)
                    (x-window-height window) :events
                    (nreverse events)) (funcall draw))
                (clip-window window
                  (make-box :width (x-window-width window) :height
                    (x-window-height window)))
                (composite display 1
                  (color-picture window "#202532" 1) 0
                  (x-window-back window) 0 0 0 0 0 0
                  (x-window-width window) (x-window-height window))
                (paint-frame renderer context)
                (clip-window window
                  (make-box :width (x-window-width window) :height
                    (x-window-height window)))
                (composite display 1 (x-window-back window) 0
                  (x-window-picture window) 0 0 0 0 0 0
                  (x-window-width window) (x-window-height window))
                (flush-display display)
                (unless interactive (sync-display display 0)
                  (return context))
                (sleep 0.016))))))
      (when font (close-font font))
      (maphash
        (lambda (key picture) (declare (ignore key))
          (free-picture display picture)) (x-window-colors window))
      (when (plusp (x-window-back window))
        (free-picture display (x-window-back window)))
      (when (plusp (x-window-pixmap window))
        (free-pixmap display (x-window-pixmap window)))
      (when (plusp (x-window-picture window))
        (free-picture display (x-window-picture window)))
      (when (plusp (x-window-window window))
        (destroy-window display (x-window-window window)))
      (close-display display))))

(register-backend :x11 #'run-x11)
