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

(binding ("XRenderSetPictureTransform" set-transform)
  :void (display :pointer) (picture :ulong) (transform :pointer))

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
  (blur-levels nil :type list)
  (glass-mask 0 :type integer)
  (mask-pixmap 0 :type integer)
  (convolution-p nil :type boolean)
  format
  mask-format
  context
  (clipboard 0 :type integer)
  (clipboard-text nil :type (or null string))
  (depth 0 :type integer)
  (width 640 :type integer)
  (height 480 :type integer)
  (shapes (make-hash-table :test 'equal) :type hash-table)
  (shape-ring (make-array 256 :initial-element nil) :type simple-vector)
  (shape-index 0 :type integer) (shape-pixels 0 :type integer)
  (glyphs (make-hash-table :test 'equal) :type hash-table)
  (glyph-pixels 0 :type integer) (glyph-clock 0 :type integer)
  (glyph-builds 0 :type integer)
  (colors (make-hash-table :test 'equal) :type hash-table)
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
    (dolist (level (x-window-blur-levels window))
      (free-picture display (first level))
      (free-picture display (third level))
      (free-pixmap display (second level))
      (free-pixmap display (fourth level)))
    (setf (x-window-blur-levels window) nil)
    (dolist (picture (list (x-window-back window)
                           (x-window-backdrop window)
                           (x-window-glass-mask window)))
      (when (plusp picture) (free-picture display picture)))
    (dolist (pixmap (list (x-window-pixmap window)
                          (x-window-mask-pixmap window)))
      (when (plusp pixmap) (free-pixmap display pixmap)))
    (setf (x-window-back window) 0
          (x-window-backdrop window) 0
          (x-window-glass-mask window) 0
          (x-window-pixmap window) 0
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
              (x-window-mask-pixmap window) (pixmap 8)
              (x-window-glass-mask window)
              (picture (x-window-mask-pixmap window)
                       (x-window-mask-format window)))
        (cffi:with-foreign-object (repeat :int)
          ;; RepeatPad keeps window edges opaque through the blur kernel.
          (setf (cffi:mem-ref repeat :int) 2)
          (change-picture display (x-window-backdrop window) 1 repeat)
          (setf (x-window-blur-levels window)
                (loop :for scale :in '(1 2 4 8 16 32)
                      :collect
                      (let* ((w (ceiling (x-window-width window) scale))
                             (h (ceiling (x-window-height window) scale))
                             (a (create-pixmap display
                                  (x-window-window window) w h
                                  (x-window-depth window)))
                             (b (create-pixmap display
                                  (x-window-window window) w h
                                  (x-window-depth window)))
                             (pa (picture a (x-window-format window)))
                             (pb (picture b (x-window-format window))))
                        (change-picture display pa 1 repeat)
                        (change-picture display pb 1 repeat)
                        (list pa a pb b w h)))))))))

(fn color-picture ((window x-window) (color string) (alpha real))
  (or (gethash (list color alpha) (x-window-colors window))
      (setf (gethash (list color alpha) (x-window-colors window))
            (cffi:with-foreign-object (rgba :ushort 4)
              (loop :for component :in (color-components color alpha) :for i
                    :from 0 :do
                    (setf (cffi:mem-aref rgba :ushort i)
                          (round (* 65535 component (if (< i 3) alpha 1)))))
              (solid-fill (x-window-display window) rgba)))))

(fn rasterize-polygons
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

(defun rectangle-points-p (points)
  (and (= (length points) 4)
       (let ((a (first points)) (b (second points))
             (c (third points)) (d (fourth points)))
         (and (= (cdr a) (cdr b)) (= (cdr c) (cdr d))
              (= (car a) (car d)) (= (car b) (car c))
              (< (car a) (car b)) (< (cdr a) (cdr c))
              (every (lambda (n) (= n (round n)))
                     (list (car a) (cdr a) (car c) (cdr c)))))))

(defun discard-mask (window)
  (let* ((ring (x-window-shape-ring window))
         (index (x-window-shape-index window))
         (entry (aref ring index)))
    (when entry
      (destructuring-bind (key picture pixels) entry
        (remhash key (x-window-shapes window))
        (free-picture (x-window-display window) picture)
        (decf (x-window-shape-pixels window) pixels))
      (setf (aref ring index) nil))
    (setf (x-window-shape-index window) (mod (1+ index) (length ring)))))

(defun shape-mask (window key width height)
  (or (gethash key (x-window-shapes window))
      (let* ((display (x-window-display window)) (pixels (* width height))
             (pixmap (create-pixmap display (x-window-window window)
                                    width height 8))
             (picture (create-picture display pixmap
                                      (x-window-mask-format window)
                                      0 (cffi:null-pointer))))
        ;; The picture now owns the drawable. Cache only its alpha coverage;
        ;; color, opacity, and the destination clip can change on every draw.
        (free-pixmap display pixmap)
        (composite display 1 (color-picture window "#000000" 0) 0 picture
                   0 0 0 0 0 0 width height)
        (rasterize-polygons window key "#ffffff" 1 picture)
        (loop :while (> (+ pixels (x-window-shape-pixels window)) 16777216)
              :do (discard-mask window))
        (let ((index (x-window-shape-index window)))
          (discard-mask window)
          (setf (aref (x-window-shape-ring window) index)
                (list key picture pixels)))
        (incf (x-window-shape-pixels window) pixels)
        (setf (gethash key (x-window-shapes window)) picture))))

(defun draw-polygons (window contours color alpha &optional target)
  (let* ((points (first contours)) (origin (first points))
         (display (x-window-display window))
         (dst (or target (x-window-back window))))
    (cond
      ((null origin) nil)
      ((and (not (cdr contours)) (rectangle-points-p points))
       (let ((a origin) (c (third points)))
         (composite display 3 (color-picture window color alpha) 0 dst
                    0 0 0 0 (round (car a)) (round (cdr a))
                    (round (- (car c) (car a))) (round (- (cdr c) (cdr a))))))
      (target (rasterize-polygons window contours color alpha target))
      (t
       (let ((left (car origin)) (top (cdr origin))
             (right (car origin)) (bottom (cdr origin)))
         (dolist (contour contours)
           (dolist (p contour)
             (setf left (min left (car p)) right (max right (car p))
                   top (min top (cdr p)) bottom (max bottom (cdr p)))))
         (let* ((x (floor left)) (y (floor top))
                (width (- (ceiling right) x)) (height (- (ceiling bottom) y)))
           (when (and (plusp width) (plusp height))
             (if (or (> (* width height) 4194304)
                     (> (max width height) 32767))
                 (rasterize-polygons window contours color alpha)
                 (let* ((local (mapcar
                                (lambda (contour)
                                  (mapcar (lambda (p)
                                            (cons (- (car p) x)
                                                  (- (cdr p) y)))
                                          contour))
                                contours))
                        (mask (shape-mask window local width height)))
                   (composite display 3 (color-picture window color alpha)
                              mask dst 0 0 0 0 x y width height))))))))))

(fn gaussian-filter ((window x-window) picture (radius real)
                     horizontal-p)
  (let* ((extent (ceiling radius))
         (size (1+ (* 2 extent)))
         (sigma (max 0.5 (/ radius 2.0)))
         (weights (loop :for offset :from (- extent) :to extent
                        :collect (exp (- (/ (* offset offset)
                                            (* 2 sigma sigma))))))
         (total (reduce #'+ weights))
         (fixed (mapcar (lambda (weight) (round (* 65536 (/ weight total))))
                        weights)))
    ;; Preserve a constant background exactly despite fixed-point rounding.
    (incf (nth extent fixed) (- 65536 (reduce #'+ fixed)))
    (cffi:with-foreign-object (parameters :int32 (+ 2 size))
      (setf (cffi:mem-aref parameters :int32 0)
            (* 65536 (if horizontal-p size 1))
            (cffi:mem-aref parameters :int32 1)
            (* 65536 (if horizontal-p 1 size)))
      (loop :for weight :in fixed :for index :from 2
            :do (setf (cffi:mem-aref parameters :int32 index) weight))
      (set-filter (x-window-display window) picture "convolution"
                  parameters (+ 2 size)))))

(fn scale-picture ((window x-window) picture (scale real))
  (cffi:with-foreign-object (matrix :int32 9)
    (dotimes (i 9) (setf (cffi:mem-aref matrix :int32 i) 0))
    (setf (cffi:mem-aref matrix :int32 0) (round (* 65536 scale))
          (cffi:mem-aref matrix :int32 4) (round (* 65536 scale))
          (cffi:mem-aref matrix :int32 8) 65536)
    (set-transform (x-window-display window) picture matrix)))

(fn bilinear-picture ((window x-window) picture (scale real))
  (scale-picture window picture scale)
  (set-filter (x-window-display window) picture "bilinear"
              (cffi:null-pointer) 0))

(fn composite-blur-region ((window x-window) source target (box box)
                           (scale real) (padding integer))
  (let* ((x (max 0 (- (floor (box-x box) scale) padding)))
         (y (max 0 (- (floor (box-y box) scale) padding)))
         (right (min (ceiling (x-window-width window) scale)
                     (+ (ceiling (+ (box-x box) (box-width box)) scale)
                        padding)))
         (bottom (min (ceiling (x-window-height window) scale)
                      (+ (ceiling (+ (box-y box) (box-height box)) scale)
                         padding))))
    (composite (x-window-display window) 1 source 0 target
               x y 0 0 x y (- right x) (- bottom y))))

(fn blur-backdrop ((window x-window) (box box) (corner-radius real)
                   (blur-radius real))
  (when (and (x-window-convolution-p window) (plusp blur-radius))
    (let* ((display (x-window-display window))
           (radius (min 64 blur-radius))
           (level (min 5 (max 0 (ceiling (log (max 1 (/ radius 3)) 2)))))
           (scale (expt 2 level))
           (buffers (nth level (x-window-blur-levels window)))
           (source (x-window-backdrop window))
           (x (max 0 (floor (box-x box))))
           (y (max 0 (floor (box-y box))))
           (right (min (x-window-width window)
                       (ceiling (+ (box-x box) (box-width box)))))
           (bottom (min (x-window-height window)
                        (ceiling (+ (box-y box) (box-height box))))))
      (when (and (< x right) (< y bottom))
        ;; Repeated half-size bilinear passes average all source pixels instead
        ;; of aliasing stripes with a single large reduction. The shrinking
        ;; halo includes both Gaussian passes and each bilinear sample footprint;
        ;; global coordinates preserve phase across widgets and window edges.
        (loop :for index :from 1 :to level
              :for target := (nth index (x-window-blur-levels window))
              :do (bilinear-picture window source 2)
                  (let* ((factor (expt 2 index))
                         (remaining (/ scale factor))
                         (halo (+ (* (+ (* 2 (ceiling (/ radius scale))) 4)
                                     remaining)
                                  (1- remaining))))
                    (composite-blur-region window source (first target)
                                           box factor halo))
                  (scale-picture window source 1)
                  (setf source (first target)))
        ;; The remaining Gaussian is at most seven taps per axis, evaluated on
        ;; the reduced image. Its fractional sigma keeps frost changes smooth.
        (gaussian-filter window source (/ radius scale) t)
        (composite-blur-region window source (third buffers) box scale
                               (+ (ceiling (/ radius scale)) 2))
        (gaussian-filter window (third buffers) (/ radius scale) nil)
        (composite-blur-region window (third buffers) (first buffers)
                               box scale 2)
        (let* ((cached-p (<= (* (- right x) (- bottom y)) 4194304))
               (mask
                 (if cached-p
                     (shape-mask
                      window
                      (list (rounded-polygon
                             (make-box :x (- (box-x box) x)
                                       :y (- (box-y box) y)
                                       :width (box-width box)
                                       :height (box-height box))
                             corner-radius))
                      (- right x) (- bottom y))
                     (x-window-glass-mask window))))
          (unless cached-p
            (composite display 1 (color-picture window "#000000" 0) 0
                       mask 0 0 0 0 0 0
                       (x-window-width window) (x-window-height window))
            (draw-polygons window (list (rounded-polygon box corner-radius))
                           "#ffffff" 1 mask))
          (bilinear-picture window (first buffers) (/ scale))
          (composite display 3 (first buffers) mask (x-window-back window)
                     x y (if cached-p 0 x) (if cached-p 0 y)
                     x y (- right x) (- bottom y)))
        (scale-picture window (first buffers) 1)))))

(fn clip-window ((window x-window) (box box))
  (cffi:with-foreign-object (rect '(:struct rectangle))
    (cffi:with-foreign-slots ((x y width height) rect (:struct rectangle))
      (setf x (round (box-x box)) y (round (box-y box)) width
            (max 0 (floor (box-width box))) height
            (max 0 (floor (box-height box)))))
    (set-clip (x-window-display window) (x-window-back window) 0 0 rect 1)))

(defparameter *glyph-cache-limit* 8192)
(defparameter *glyph-cache-pixels* (* 16 1024 1024))
(defstruct glyph-mask
  (picture 0 :type integer) (left 0 :type integer) (top 0 :type integer)
  (width 0 :type integer) (height 0 :type integer) (stamp 0 :type integer))

(fn discard-glyph ((window x-window) key (mask glyph-mask))
  (when (plusp (glyph-mask-picture mask))
    (free-picture (x-window-display window) (glyph-mask-picture mask)))
  (decf (x-window-glyph-pixels window)
        (* (glyph-mask-width mask) (glyph-mask-height mask)))
  (remhash key (x-window-glyphs window)))

(fn clear-glyph-cache ((window x-window))
  (maphash (lambda (key mask) (discard-glyph window key mask))
           (x-window-glyphs window)))

(fn trim-glyph-cache ((window x-window) (pixels integer))
  (loop :while (and (plusp (hash-table-count (x-window-glyphs window)))
                   (or (>= (hash-table-count (x-window-glyphs window))
                           *glyph-cache-limit*)
                       (> (+ pixels (x-window-glyph-pixels window))
                          *glyph-cache-pixels*)))
        :do (let ((oldest nil) (old-key nil))
              (maphash (lambda (key mask)
                         (when (or (null oldest)
                                   (< (glyph-mask-stamp mask)
                                      (glyph-mask-stamp oldest)))
                           (setf oldest mask old-key key)))
                       (x-window-glyphs window))
              (discard-glyph window old-key oldest))))

(fn build-glyph-mask ((window x-window) (font font) (char character)
                      (phase-x integer) (phase-y integer))
  (let ((scale (/ (font-size font) (zpb-ttf:units/em (font-loader font))))
        (left nil) (top nil) (right nil) (bottom nil))
    (let ((contours
            (mapcar (lambda (contour)
                      (mapcar (lambda (point)
                                (let ((x (+ (* scale (car point))
                                            (/ phase-x 4)))
                                      (y (+ (* (- scale) (cdr point))
                                            (/ phase-y 4))))
                                  (setf left (if left (min left x) x)
                                        right (if right (max right x) x)
                                        top (if top (min top y) y)
                                        bottom (if bottom (max bottom y) y))
                                  (cons x y)))
                              contour))
                    (glyph-polygons font char))))
      (unless left (return-from build-glyph-mask (make-glyph-mask)))
      (let* ((x (1- (floor left))) (y (1- (floor top)))
             (width (+ 1 (- (ceiling right) x)))
             (height (+ 1 (- (ceiling bottom) y)))
             (pixels (* width height)))
        (when (or (> (max width height) 4096)
                  (> pixels *glyph-cache-pixels*))
          (return-from build-glyph-mask nil))
        (trim-glyph-cache window pixels)
        (let* ((display (x-window-display window))
               (pixmap (create-pixmap display (x-window-window window)
                                      width height 8))
               (picture (create-picture display pixmap
                                        (x-window-mask-format window)
                                        0 (cffi:null-pointer))))
          (free-pixmap display pixmap)
          (composite display 1 (color-picture window "#000000" 0) 0 picture
                     0 0 0 0 0 0 width height)
          (draw-polygons
           window (mapcar (lambda (contour)
                            (mapcar (lambda (point)
                                      (cons (- (car point) x)
                                            (- (cdr point) y)))
                                    contour))
                          contours)
           "#ffffff" 1 picture)
          (incf (x-window-glyph-pixels window) pixels)
          (incf (x-window-glyph-builds window))
          (make-glyph-mask :picture picture :left x :top y
                           :width width :height height))))))

(fn glyph-mask-for ((window x-window) (font font) glyph (char character)
                    (phase-x integer) (phase-y integer))
  (let* ((key (list font (font-size font) (zpb-ttf:font-index glyph)
                    phase-x phase-y))
         (mask (or (gethash key (x-window-glyphs window))
                   (let ((new (build-glyph-mask window font char
                                                 phase-x phase-y)))
                     (when new
                       (trim-glyph-cache window 0)
                       (setf (gethash key (x-window-glyphs window)) new))))))
    (when mask
      (setf (glyph-mask-stamp mask) (incf (x-window-glyph-clock window))))
    mask))

(fn draw-cached-text ((window x-window) (font font) (text string)
                      (x real) (y real) (color string))
  ;; Four fractional phases retain subpixel placement without position keys.
  (let ((scale (/ (font-size font) (zpb-ttf:units/em (font-loader font))))
        (cursor x) (previous nil) (qy (round (* y 4))))
    (loop :for char :across text
          :for glyph := (zpb-ttf:find-glyph char (font-loader font))
          :do (when previous
                (incf cursor (* scale (zpb-ttf:kerning-offset
                                      previous char (font-loader font)))))
              (let* ((qx (round (* cursor 4)))
                     (mask (glyph-mask-for window font glyph char
                                           (mod qx 4) (mod qy 4))))
                (cond
                  ((null mask)
                   (let ((renderer
                           (make-renderer
                            :font font :polygons
                            (lambda (contours ink alpha)
                              (draw-polygons window contours ink alpha)))))
                     (paint-text renderer (string char) cursor y color)))
                  ((plusp (glyph-mask-picture mask))
                   (composite (x-window-display window) 3
                              (color-picture window color 1)
                              (glyph-mask-picture mask) (x-window-back window)
                              0 0 0 0
                              (+ (floor qx 4) (glyph-mask-left mask))
                              (+ (floor qy 4) (glyph-mask-top mask))
                              (glyph-mask-width mask)
                              (glyph-mask-height mask)))))
              (incf cursor (* scale (zpb-ttf:advance-width glyph)))
              (setf previous char))))

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
                                   (otherwise "default"))
                         :ulong)
                        0)))
              (if (plusp cursor) cursor
                  (create-font-cursor
                   (x-window-display window)
                   (case kind (:not-allowed 0) (:pointer 60)
                         (:text 152) (:resize-horizontal 108)
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

(fn full-window-clip ((window x-window))
  (clip-window window (make-box :width (x-window-width window)
                                :height (x-window-height window))))

(fn draw-window ((window x-window) (renderer renderer) (context context)
                 (draw function) interactive (delete integer))
  (let ((display (x-window-display window)))
    (loop :for start := (get-internal-real-time)
          :do (multiple-value-bind (events quit) (read-events window delete)
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
       ;; Bound the render queue: frame intervals include server completion.
       (sync-display display 0)
       (unless interactive (return context))
       (let ((remaining (- (/ 1 60)
                           (/ (- (get-internal-real-time) start)
                              internal-time-units-per-second))))
         (when (plusp remaining) (sleep remaining)))))))

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
           (setf (x-window-clipboard window)
                 (intern-atom display "CLIPBOARD" 0))
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
                    :text (lambda (face text x y color)
                            (draw-cached-text window face text x y color))
                    :polygons (lambda (polys color alpha)
                                (draw-polygons window polys color alpha))
                    :clip (lambda (box) (clip-window window box))
                    :glass (lambda (box radius frost)
                             (blur-backdrop window box radius frost))))
                  (context
                   (make-context
                    :copy (lambda (text) (copy-clipboard window text))
                    :measure (lambda (widget width)
                               (measure-widget renderer widget width)))))
             (setf (x-window-context window) context)
             (draw-window window renderer context draw interactive delete)))
      (dotimes (i (length (x-window-shape-ring window)))
        (discard-mask window))
      (clear-glyph-cache window)
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
