(defpackage #:lui.font
  (:use #:cl #:lui.fn #:lui.layout)
  (:export #:font #:open-font #:close-font #:font-size #:font-loader
           #:text-width #:line-height #:baseline #:wrap-text #:glyph-polygons
           #:*font-path* #:*font-paths* #:*font-directories*
           #:*font-names* #:font-face #:font-css))

(in-package #:lui.font)

;;; Browser fonts measure text through Canvas.
#+(or jscl lui-ecl-web)
(progn
  (defvar *font-path* nil)
  (defvar *font-paths* nil)
  (defvar *font-directories* nil)
  (defvar *font-names* nil)

  (defstruct font
    "A browser font face with a Canvas context for measuring text."
    loader
    owner
    (faces (make-array 4 :element-type '(or null font) :initial-element nil)
           :type (vector (or null font) 4))
    (size 16)
    (family :sans-serif)
    (weight :normal)
    css-value css-size
    (metrics (make-hash-table :test 'equal))
    (wrapped (make-hash-table :test 'equal)))

  (fn (open-font font)
    (&optional ((path (or null string pathname)) nil) ((size real) 16))
    "Create a browser font at SIZE; PATH is accepted for API compatibility."
    (declare (ignore path))
    (let ((canvas (#j:document:createElement #j"canvas")))
      (make-font :loader ((jscl/ffi:oget canvas "getContext") #j"2d")
                 :size size)))

  (fn (close-font (values)) ((font font))
    (dotimes (index (length (font-faces font)))
      (setf (aref (font-faces font) index) nil))
    (clrhash (font-metrics font))
    (clrhash (font-wrapped font))
    (setf (font-loader font) nil)
    (values))

  (fn (font-css string) ((font font))
    "Return the CSS font shorthand used by measurement and drawing."
    (unless (eql (font-css-size font) (font-size font))
      (setf (font-css-size font) (font-size font)
            (font-css-value font)
            (format nil "~A ~Apx ~A"
                    (if (eq (font-weight font) :bold) "bold" "normal")
                    (jscl/ffi:clstring (#j:String (font-size font)))
                    (if (eq (font-family font) :monospace)
                        "monospace" "sans-serif"))))
    (font-css-value font))

  (fn (measure-text t) ((font font) (text string))
    (let ((css (font-css font))
          (cache (font-metrics font))
          (key (list (font-size font) text)))
      (or (gethash key cache)
          (let ((context (font-loader font)))
            (when (>= (hash-table-count cache) 2048) (clrhash cache))
            (setf (jscl/ffi:oget context "font") (jscl/ffi:jsstring css))
            (setf (gethash key cache)
                  ((jscl/ffi:oget context "measureText")
                   (jscl/ffi:jsstring text)))))))

  (fn (text-width real) ((font font) (text string))
    (jscl/ffi:oget (measure-text font text) "width"))

  (fn (baseline real) ((font font))
    (let ((ascent (jscl/ffi:oget (measure-text font "Mg")
                                 "fontBoundingBoxAscent")))
      (if (and (numberp ascent) (plusp ascent))
          ascent (* (font-size font) 0.8f0))))

  (fn (line-height real) ((font font))
    (let* ((metrics (measure-text font "Mg"))
           (ascent (jscl/ffi:oget metrics "fontBoundingBoxAscent"))
           (descent (jscl/ffi:oget metrics "fontBoundingBoxDescent")))
      (if (and (numberp ascent) (numberp descent)
               (plusp (+ ascent descent)))
          (max (* (font-size font) 1.2f0) (+ ascent descent))
          (* (font-size font) 1.2f0))))

  (fn (glyph-polygons nil) ((font font) (char character))
    (declare (ignore font char))
    (error 'lui.conditions:backend-error
           :backend :web
           :operation :glyph-polygons
           :format-control "Browser text is drawn by the renderer text callback."))

  (fn (uncached-wrap-text (vector string))
    ((font font) (text string) (width (or null real)))
    "Split TEXT into lines at newlines and spaces; NIL width preserves explicit breaks."
    (lui.text:wrap-lines text width
                         (lambda (text start end)
                           (text-width font (subseq text start end)))))

  (fn (wrap-text (vector string))
      ((font font) (text string) (width (or null
                                            real)))
    (let ((cache (font-wrapped font))
          (key (list (font-size font) text width)))
      (cond ((gethash key cache))
            (t
             (when (>= (hash-table-count cache) 512) (clrhash cache))
             (setf (gethash key cache)
                   (uncached-wrap-text font text width)))))))

;;; Native fonts measure and outline text through zpb-ttf.
#-(or jscl lui-ecl-web)
(progn
  (defvar *font-path* nil "Override the default TrueType font pathname.")

  (defvar *font-paths* nil
    "Optional ((family weight) . pathname) overrides for additional font faces.")

  (defstruct font
    "An open TrueType face, its pixel size, and cached glyph outlines."
    loader
    owner
    (faces (make-array 4 :element-type '(or null font) :initial-element nil)
           :type (vector (or null font) 4))
    (size 16 :type real)
    (cache (make-hash-table) :type hash-table))

  (defvar *font-directories*
    '("/usr/share/fonts/dejavu-sans-fonts/"
      "/usr/share/fonts/dejavu-sans-mono-fonts/"
      "/usr/share/fonts/truetype/dejavu/"
      "/usr/share/fonts/liberation-sans-fonts/"
      "/usr/share/fonts/liberation-mono-fonts/"
      "/usr/share/fonts/truetype/liberation2/"
      "/usr/share/fonts/truetype/liberation/"
      "C:/Windows/Fonts/" "/System/Library/Fonts/Supplemental/")
    "Ordered font directories, as directory pathnames or namestrings.")

  (defvar *font-names*
    '(((:sans-serif :normal) "DejaVuSans.ttf" "arial.ttf" "Arial.ttf"
       "LiberationSans-Regular.ttf")
      ((:sans-serif :bold) "DejaVuSans-Bold.ttf" "arialbd.ttf" "Arial Bold.ttf"
       "LiberationSans-Bold.ttf")
      ((:monospace :normal) "LiberationMono-Regular.ttf" "DejaVuSansMono.ttf"
       "cour.ttf" "Courier New.ttf")
      ((:monospace :bold) "LiberationMono-Bold.ttf" "DejaVuSansMono-Bold.ttf"
       "courbd.ttf" "Courier New Bold.ttf"))
    "Candidate filenames in preference order for each (family weight).")

  (fn (resolve-face (or pathname string)) ((family symbol) (weight symbol))
    (let ((key (list family weight)))
      (or (cdr (assoc key *font-paths* :test #'equal))
          (loop :with extra := (uiop:getenvp "LUI_FONT_DIR")
                :with dirs := (if extra
                                  (cons (uiop:ensure-directory-pathname extra)
                                        *font-directories*)
                                  *font-directories*)
                :for name :in (cdr (assoc key *font-names* :test #'equal))
                :thereis (loop :for dir :in dirs
                               :thereis (probe-file
                                         (merge-pathnames name dir))))
          (error 'lui.conditions:font-error
                 :backend :native :request key
                 :operation :resolve-face
                 :format-control "No TrueType font for ~S. Set LUI.FONT:*FONT-PATHS*."
                 :format-arguments (list key)))))

  (fn (default-font (or pathname string)) ()
    (or *font-path* (uiop:getenvp "LUI_FONT")
        (resolve-face :sans-serif :normal)))

  (fn (open-font font)
    (&optional ((path (or null string pathname)) nil) ((size real) 16))
    "Open a TrueType file at SIZE; a missing PATH uses the configured base face."
    (make-font :loader (zpb-ttf:open-font-loader (or path (default-font)))
               :size size))

  (fn (close-font (values)) ((font font))
    "Release the loader, cached faces, and glyph outlines owned by FONT."
    (dotimes (index 4)
      (let ((face (aref (font-faces font) index)))
        (when face (close-font face))))
    (fill (font-faces font) nil)
    (when (font-loader font)
      (zpb-ttf:close-font-loader (font-loader font))
      (setf (font-loader font) nil))
    (clrhash (font-cache font))
    (values))

  (fn (scale-font real) ((font font))
    (/ (font-size font) (zpb-ttf:units/em (font-loader font))))

  (fn (baseline real) ((font font))
    "Return the ascent from the top of a line to its baseline."
    (* (scale-font font) (zpb-ttf:ascender (font-loader font))))

  (fn (line-height real) ((font font))
    "Return baseline-to-baseline spacing including the font’s line gap."
    (* (scale-font font)
       (+ (zpb-ttf:ascender (font-loader font))
          (- (zpb-ttf:descender (font-loader font)))
          (zpb-ttf:line-gap (font-loader font)))))

  (fn (text-width real) ((font font) (text string))
    "Measure a string using glyph advances and pair kerning at the current size."
    (let ((previous nil)
          (width 0))
      (loop :for char :across text
            :do (incf width
                      (+ (zpb-ttf:advance-width
                          (zpb-ttf:find-glyph char (font-loader font)))
                         (if previous
                             (zpb-ttf:kerning-offset
                              previous char (font-loader font))
                             0)))
            (setf previous char))
      (* (scale-font font) width)))

  (fn (wrap-text (vector string))
    ((font font) (text string) (width (or null real)))
    "Split TEXT into lines at newlines and spaces; NIL width preserves explicit breaks."
    (lui.text:wrap-lines text width
                         (lambda (text start end)
                           (text-width font (subseq text start end)))))

  (fn (glyph-polygons contours) ((font font) (char character))
    "Flatten TrueType curves into geometric contours, never pixels. Cache in font units."
    (or (gethash char (font-cache font))
        (setf (gethash char (font-cache font))
              (let ((polygons nil))
                (zpb-ttf:do-contours
                    (contour (zpb-ttf:find-glyph char (font-loader font)))
                  (let ((points nil))
                    (zpb-ttf:do-contour-segments (p0 p1 p2) contour
                                                 (if p1
                                                     (loop :for i :from 1 :to
                                                           12
                                                           :for u :=
                                                           (/ i 12.0f0)
                                                           :for v := (- 1 u)
                                                           :do
                                                           (push
                                                            (cons
                                                             (+
                                                              (* v v
                                                                 (zpb-ttf:x
                                                                  p0))
                                                              (* 2 u v
                                                                 (zpb-ttf:x
                                                                  p1))
                                                              (* u u
                                                                 (zpb-ttf:x
                                                                  p2)))
                                                             (+
                                                              (* v v
                                                                 (zpb-ttf:y
                                                                  p0))
                                                              (* 2 u v
                                                                 (zpb-ttf:y
                                                                  p1))
                                                              (* u u
                                                                 (zpb-ttf:y
                                                                  p2))))
                                                            points))
                                                     (push
                                                      (cons (zpb-ttf:x p2)
                                                            (zpb-ttf:y p2))
                                                      points)))
                    (when points (push (coerce (nreverse points) 'contour)
                                       polygons))))
                (coerce (nreverse polygons) 'contours))))))

(fn (font-face font) ((font font) (family symbol) (weight symbol))
  "Resolve a sans-serif or monospace face at normal or bold weight; reuse it until the owner is closed."
  (let ((owner (or (font-owner font) font))
        (index (+ (ecase family (:sans-serif 0) (:monospace 2))
                  (ecase weight (:normal 0) (:bold 1)))))
    (if (zerop index) owner
        (or (aref (font-faces owner) index)
            (let ((face
                   #+(or jscl lui-ecl-web)
                   (make-font :loader (font-loader owner)
                              :size (font-size owner)
                              :family family :weight weight)
                   #-(or jscl lui-ecl-web)
                   (open-font (resolve-face family weight)
                              (font-size owner))))
              (setf (font-owner face) owner
                    (aref (font-faces owner) index) face))))))

(defpackage #:lui.draw
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame #:lui.widgets #:lui.font)
  (:export #:typed-vector #:renderer-patterns #:rectangle-path
           #:standard-geometry #:paint-widget-text #:paint-text-field
           #:paint-shared-widget #:paint-desktop-scrollbar
           #:register-standard-painter #:copy-selection #:make-text-selection
           #:selectable-nodes
           #:selection-area
           #:renderer #:make-renderer #:renderer-font #:renderer-polygons
           #:renderer-clip #:renderer-backdrop-effect #:renderer-text
           #:renderer-surface #:renderer-stipple
           #:make-render-context #:paint-frame #:measure-widget #:widget-font
           #:focused-p #:shape
           #:outline #:inset-box
           #:geometry #:make-geometry #:geometry-left #:geometry-top
           #:geometry-right #:geometry-value-p #:geometry-text-p
           #:geometry-bottom
           #:geometry-min-width #:geometry-min-height
           #:geometry-center-x #:geometry-center-y #:geometry-offset-x
           #:geometry-offset-y
           #:widget-geometry #:text-box #:rounded-polygon #:color-components
           #:trapezoids #:paint-text))

(in-package #:lui.draw)

(defmacro typed-vector (type &rest elements)
  "Construct a typed vector without an intermediate list of its elements."
  (let ((result (gensym "VECTOR")))
    (if (null elements)
        `(make-array 0 :element-type ',type)
        `(let ((,result (make-array ,(length elements) :element-type ',type
                                    :initial-element ,(first elements))))
           ,@(loop :for element :in (rest elements) :for i :from 1
                   :collect `(setf (aref ,result ,i) ,element))
           ,result))))

(defstruct renderer
  "Native drawing callbacks and font shared by the graphical backends."
  (font nil :type (or null font))
  ;; POLYGONS takes contours, #rrggbb color, and opacity. Native API does rasterization.
  (polygons nil :type (or null function))
  (clip nil :type (or null function))
  ;; Optional toolkit-independent backdrop effect: bounds, corner radius,
  ;; blur radius. Sample the existing surface before painting its tint.
  (backdrop-effect nil :type (or null function))
  ;; Optional native glyph cache: font, text, baseline x/y, and color.
  (text nil :type (or null function))
  ;; Optional rectangle primitives avoid contour allocation in browser APIs.
  (surface nil :type (or null function))
  (stipple nil :type (or null function))
  (patterns (make-hash-table :test 'equal) :type hash-table))

(fn (color-components (vector single-float 4))
    ((color string) &optional
                      ((alpha real) 1))
  "Return normalized red, green, blue, and alpha in a four-float vector."
  (assert (and (= (length color) 7) (char= (char color 0) #\#)))
  (let ((rgba (make-array 4 :element-type 'single-float)))
    (dotimes (i 3)
      (setf (aref rgba i) (/ (parse-integer color :start (1+ (* i 2))
                                            :end (+ 3 (* i 2)) :radix 16)
                             255.0f0)))
    (setf (aref rgba 3) (coerce (max 0 (min 1 alpha)) 'single-float))
    rgba))

(fn (rounded-polygon contour) ((box box) (radius real))
  "Return contour points for BOX with corners rounded by RADIUS."
  (let* ((x (box-x box))
         (y (box-y box))
         (w (box-width box))
         (h (box-height box))
         (r (max 0 (min radius (/ w 2) (/ h 2)))))
    (when (zerop r)
      (return-from rounded-polygon
        (typed-vector point (cons (+ x w) y) (cons (+ x w) (+ y h))
                      (cons x (+ y h)) (cons x y))))
    (make-array 36 :element-type 'point :initial-contents
                (loop :for (cx cy base)
                      :in (list (list (+ x w (- r)) (+ y r) -90)
                                (list (+ x w (- r)) (+ y h (- r)) 0)
                                (list (+ x r) (+ y h (- r)) 90)
                                (list (+ x r) (+ y r) 180))
                      :append (loop :for i :from 0 :to 8
                                    :for angle := (* (+ base (* i 11.25f0))
                                                     (/ pi 180))
                                    :collect
                                    (cons (+ cx (* r #-jscl (cos angle)
                                                   #+jscl (#j:Math:cos
                                                           angle)))
                                          (+ cy (* r #-jscl (sin angle)
                                                   #+jscl (#j:Math:sin
                                                           angle)))))))))

(fn (trapezoids (values)) ((contours contours) (emit function))
  "Convert contours into nonzero-winding trapezoids for native triangle APIs."
  (let ((edges nil)
        (ys nil))
    (loop :for points :across contours :do
          (loop :for i :below (length points)
                :for a := (aref points i)
                :for b := (aref points (mod (1+ i) (length points)))
                :unless (= (cdr a) (cdr b))
                :do (push (cons a b) edges)
                (push (cdr a) ys)))
    (setf ys (sort (remove-duplicates ys :test #'=) #'<))
    (labels ((at-y (edge y)
               (+ (caar edge)
                  (* (- y (cdar edge))
                     (/ (- (cadr edge) (caar edge))
                        (- (cddr edge) (cdar edge)))))))
      (loop :for (top bottom) :on ys
            :for middle := (when bottom (/ (+ top bottom) 2))
            :while bottom
            :do (let ((active
                       (sort
                        ;; Each slab must retain the full original EDGES list.
                        (loop :for edge :in edges
                              :when (< (min (cdar edge) (cddr edge))
                                       middle
                                       (max (cdar edge) (cddr edge)))
                              :collect edge)
                        #'< :key (lambda (edge) (at-y edge middle))))
                      (winding 0)
                      (left nil))
                  (dolist (edge active)
                    (when (zerop winding) (setf left edge))
                    (incf winding (if (< (cdar edge) (cddr edge)) 1 -1))
                    (when (and left (zerop winding))
                      (funcall emit
                               (typed-vector point (cons (at-y left top) top)
                                             (cons (at-y edge top) top)
                                             (cons (at-y edge bottom) bottom)
                                             (cons (at-y left bottom)
                                                   bottom)))))))))
  (values))

(fn (widget-font font) ((renderer renderer) (widget widget))
  "Select the widget’s font face and size for this renderer."
  (let ((font (font-face (renderer-font renderer)
                         (widget-font-family widget)
                         (widget-font-weight widget))))
    (setf (font-size font) (widget-font-size widget))
    font))

(defstruct geometry
  "Toolkit text insets, intrinsic minimum size, alignment, and pressed displacement."
  (left 0) (top 0) (right 0) (bottom 0) (min-width 0) (min-height 0)
  (text-p t) value-p center-x center-y (offset-x 0) (offset-y 0))

(fn (widget-geometry geometry) ((widget widget))
  "Return the active toolkit's shared text geometry for WIDGET."
  (funcall (or (lui.toolkit:toolkit-geometry (widget-style widget))
               (error 'lui.conditions:configuration-error
                      :setting :geometry :value (widget-style widget)
                      :operation :widget-geometry
                      :format-control "Toolkit ~S has no graphical geometry."
                      :format-arguments (list (widget-style widget))))
           widget))

(fn (make-render-context context) ((renderer renderer) &rest (options list))
  "Create a frame context measured by RENDERER, with backend-specific OPTIONS."
  (apply #'make-context
         :measure (lambda (widget width)
                    (measure-widget renderer widget width))
         options))

(fn (measure-widget (values number number))
    ((renderer renderer) (widget
                          widget) (width (or null real)))
  "Measure current geometry, reusing matching prior-frame text measurements."
  (let* ((g (widget-geometry widget)) (font (widget-font renderer widget))
         (horizontal (+ (geometry-left g) (geometry-right g)))
         (vertical (+ (geometry-top g) (geometry-bottom g)))
         (text (when (geometry-text-p g)
                 (if (geometry-value-p g)
                     (widget-display-value widget)
                     (widget-text widget))))
         (size (lui.frame:memoized
                (list :measure font (font-loader font) (font-size font)
                      text width horizontal vertical
                      (geometry-min-width g) (geometry-min-height g))
                (lambda ()
                  (let ((lines (if text
                                   (wrap-text font text
                                              (when width
                                                (max 0
                                                     (-
                                                      width horizontal))))
                                   #())) (widest 0))
                    (dotimes (i (length lines))
                      (setf widest (max widest (text-width font (aref lines
                                                                      i)))))
                    (cons (max (geometry-min-width g) (+ horizontal widest))
                          (max (geometry-min-height g)
                               (+ vertical (* (length lines) (line-height
                                                              font))))))))))
    (values (car size) (cdr size))))

(fn (text-box box)
    ((widget widget) (box box) &optional ((pressed boolean) nil))
  "Return the toolkit's text area, including pressed displacement."
  (let ((g (widget-geometry widget)))
    (make-box :x (+ (box-x box) (geometry-left g)
                   (if pressed
                     (geometry-offset-x g) 0))
              :y (+ (box-y box) (geometry-top g) (if pressed
                                                     (geometry-offset-y g) 0))
              :width (max 0 (- (box-width box) (geometry-left g)
                               (geometry-right g)))
              :height (max 0 (- (box-height box) (geometry-top g)
                                (geometry-bottom g))))))

(fn (paint-text t) ((renderer renderer) (text string) (x real) (y real)
                    (color string))
  "Draw TEXT at horizontal position X and baseline Y in COLOR."
  (unless (zerop (length text))
    (if (renderer-text renderer)
        (funcall (renderer-text renderer) (renderer-font renderer)
                 text x y color)
        #+(or jscl lui-ecl-web)
        (error 'lui.conditions:configuration-error
               :setting :text-renderer :value nil
               :operation :paint-text
               :format-control "The browser renderer requires a text drawing callback.")
        #-(or jscl lui-ecl-web)
        (let* ((font (renderer-font renderer))
               (scale (/ (font-size font) (zpb-ttf:units/em (font-loader
                                                             font))))
               (cursor x)
               (previous nil))
          (loop :for char :across text
                :do (when previous
                      (incf cursor
                            (* scale (zpb-ttf:kerning-offset
                                      previous char (font-loader font)))))
                (funcall
                 (renderer-polygons renderer)
                 (map 'contours
                      (lambda (points)
                        (map 'contour (lambda (point)
                                        (cons (+ cursor (* scale (car point)))
                                              (- y (* scale (cdr point)))))
                             points))
                      (glyph-polygons font char))
                 color 1)
                (incf cursor
                      (* scale (zpb-ttf:advance-width
                                (zpb-ttf:find-glyph char
                                                    (font-loader font)))))
                (setf previous char))))))

(fn (inset-box box) ((box box) (inset real))
  "Return a new box inset on every edge, clamping dimensions to zero."
  (make-box :x (+ (box-x box) inset) :y (+ (box-y box) inset)
            :width (max 0 (- (box-width box) (* 2 inset)))
            :height (max 0 (- (box-height box) (* 2 inset)))))

(fn (shape t) ((renderer renderer) (box box) (radius real) (color string)
               (alpha real))
  "Fill BOX with COLOR at ALPHA opacity using rounded corners of RADIUS."
  (if (renderer-surface renderer)
      (funcall (renderer-surface renderer) box radius color alpha)
      (funcall (renderer-polygons renderer)
               (make-array 1 :element-type 'contour :initial-element
                           (rounded-polygon box radius)) color alpha)))

(fn (outline t) ((renderer renderer) (box box) (radius real) (color string)
                 (alpha real) (thickness real))
  "Stroke the inside edge of BOX with the given THICKNESS and corner RADIUS."
  (if (renderer-surface renderer)
      (funcall (renderer-surface renderer)
               box radius color alpha thickness)
      (funcall (renderer-polygons renderer)
               (typed-vector contour (rounded-polygon box radius)
                             (reverse
                               (rounded-polygon (inset-box box
                                                                  thickness)
                                                       (max 0
                                                         (- radius
                                                           thickness)))))
               color alpha)))

(fn (focused-p boolean) ((node element))
  "Return true when NODE has input focus in the current frame."
  (and (element-interactive-p node)
       (boundp '*context*)
       (equal (element-id node) (context-focus *context*))
       (not (widget-disabled-p (element-content node)))))

(fn (paint-widget t) ((renderer renderer) (node element))
  "Dispatch widget painting to its explicit painter or its registered toolkit painter."
  (let* ((widget (element-content node))
         (paint (or (widget-painter widget)
                    (lui.toolkit:toolkit-paint (widget-style widget))
                    (error 'lui.conditions:configuration-error
                           :setting :painter :value (widget-style widget)
                           :operation :paint-widget
                           :format-control "Toolkit ~S has no graphical painter."
                           :format-arguments (list (widget-style widget)))))
         (font (renderer-font renderer)))
    (funcall (renderer-clip renderer) (element-clip node))
    (unwind-protect
         (progn (setf (renderer-font renderer) (widget-font renderer widget))
                (funcall paint renderer node))
      (setf (renderer-font renderer) font))))

(fn (paint-frame t)
    ((renderer renderer) (context context) &optional
     ((external-labels (or null hash-table)) nil)
     ((viewport (or null box)) nil))
  "Paint the visible elements of a solved frame and its text selection."
  (unless (context-input-handler context)
    (setf (context-input-handler context)
          (lambda (context events)
            (selection-input renderer context events))))
  (let ((*context* context))
    (visible-elements
     (context-root context)
     (lambda (node)
       (when (and (widget-p (element-content node))
                  (or (null viewport)
                      (let ((clip (element-clip node)))
                        (and (< (box-y clip) (box-bottom viewport))
                             (< (box-y viewport) (box-bottom clip)))))
                  (not (and external-labels (gethash node external-labels))))
         (paint-widget renderer node))))
    (finish-selection renderer context)))

(defstruct text-selection
  anchor focus anchor-text focus-text anchor-key focus-key field
  (node-count 0 :type integer)
  (pending-copy-p nil :type boolean)
  (dragging-p nil :type boolean))

(fn (selectable-nodes (values (vector element) (or null hash-table)))
    ((context context) &optional ((keys-p boolean) nil))
  "Collect visible selectable text nodes in layout order."
  (let ((nodes (make-array 0 :element-type 'element :adjustable t
                           :fill-pointer 0)) (keys (when keys-p
                           (make-hash-table :test 'eq))))
    (labels ((visit (node anchor path)
               (when (element-id node)
                 (setf anchor (element-id node) path nil))
               (let ((widget (element-content node)))
                 (when (and (widget-p widget)
                            (member (widget-kind widget)
                                    '(:label :text-field))
                            (not (widget-disabled-p widget)))
                   (vector-push-extend node nodes)
                   (when keys
                     ;; Anonymous nodes retain position under the closest ID.
                     ;; Identical siblings at unchanged positions cannot differ.
                     (setf (gethash node keys)
                           (list anchor (reverse path))))))
               (loop :for child :across (element-children node)
                     :for index :from 0
                     :do (visit child anchor (when keys (cons index path))))))
      (when (context-root context) (visit (context-root context) nil nil)))
    (values nodes keys)))

(fn (selection-target (or null element)) ((context context) (x real) (y real))
  "Find the selectable text node under a pointer position."
  (let ((target nil))
    (walk-elements
     (context-root context)
     (lambda (node)
       (when (and (widget-p (element-content node))
                  (lui.frame:contains-p (element-clip node) x y))
         (setf target node))))
    target))

(fn (selection-text string) ((node element))
  "Return the text represented by a selectable node."
  (let ((widget (element-content node)))
    (if (eq (widget-kind widget) :text-field)
        (widget-display-value widget) (widget-text widget))))

(fn (selection-area box) ((renderer renderer) (node element))
  "Compute the text selection bounds using the widget's resolved geometry."
  (let* ((widget (element-content node)) (area (text-box widget (element-box
                                                                 node)))
         (font (widget-font renderer widget)) (g (widget-geometry widget)))
    (when (geometry-center-y g)
      (incf (box-y area) (max 0 (/ (- (box-height area)
                                      (* (length
                                          (wrap-text font
                                                     (selection-text node)
                                                     (box-width area)))
                                         (line-height font))) 2))))
    area))

(fn (selection-left real) ((font font) (node element) (area box) (line
                                                                  string))
  "Compute a line's left edge, accounting for centered text."
  (+ (box-x area) (if (geometry-center-x (widget-geometry (element-content
                                                           node)))
                      (max 0 (/ (- (box-width area) (text-width font line))
                                2)) 0)))

(fn (selection-index integer) ((renderer renderer) (node element) (x real)
                               (y
                                real))
  "Map a pointer position to a character index using rendered glyph widths."
  (let ((area (selection-area renderer node)))
    (let* ((font (widget-font renderer (element-content node)))
           (text (selection-text node)) (start 0)
           (top (box-y area))
           (lines (wrap-text font text
                             (box-width area))))
      (loop :for line :across lines :do
            (when (< y (+ top (line-height font)))
              (let ((at (- x (selection-left font node area line))) (left 0)
                    #-(or jscl lui-ecl-web) (previous nil)
                    #-(or jscl lui-ecl-web)
                    (scale (/ (font-size font)
                              (zpb-ttf:units/em (font-loader font)))))
                (dotimes (i (length line))
                  (let (#-(or jscl lui-ecl-web) (char (char line i)))
                    (let ((right #+(or jscl lui-ecl-web)
                                 (text-width font (subseq line 0 (1+ i)))
                                 #-(or jscl lui-ecl-web)
                                 (+ left
                                    (* scale
                                       (+ (zpb-ttf:advance-width
                                           (zpb-ttf:find-glyph
                                            char (font-loader font)))
                                          (if previous
                                              (zpb-ttf:kerning-offset
                                               previous char (font-loader
                                                              font))
                                              0))))))
                      (when (< at (/ (+ left right) 2))
                        (return-from selection-index (+ start i)))
                      (setf left right)
                      #-(or jscl lui-ecl-web) (setf previous char))))
                (return-from selection-index (+ start (length line)))))
            (incf start (1+ (length line)))
            (incf top (line-height font))
            :finally (return (length text))))))

(fn (selection-range (values (or null integer) &optional (or null integer)))
    ((selection text-selection) (index integer)
     (length integer))
  "Return ordered selection endpoints for a node in the selection sequence."
  (let ((a (text-selection-anchor selection))
        (b (text-selection-focus selection)))
    (when (and a b)
      (when (or (> (car a) (car b))
                (and (= (car a) (car b)) (> (cdr a) (cdr b))))
        (rotatef a b))
      (when (<= (car a) index (car b))
        (values (min length (if (= index (car a)) (cdr a) 0))
                (min length (if (= index (car b)) (cdr b) length)))))))

(fn (copy-selection t) ((context context) (nodes (vector element))
                        (selection text-selection))
  "Copy selected text to the registered clipboard callback."
  (let ((text
         (if (text-selection-anchor selection)
             (with-output-to-string (out)
               (let ((separator nil))
                 (loop :for node :across nodes :for i :from 0
                       :for text := (selection-text node)
                       :do (multiple-value-bind (start end)
                               (selection-range selection i (length text))
                             (when (and start (< start end))
                               (when separator (terpri out))
                               (write-string text out :start start :end end)
                               (setf separator t))))))
             (let* ((id (context-focus context))
                    (node (find id nodes :key #'element-id :test #'equal))
                    (state (gethash id (context-state context))))
               (when (and node (typep state 'edit-state))
                 (let ((text (selection-text node)))
                   (subseq text
                           (min (length text) (edit-state-anchor state)
                                (edit-state-cursor state))
                           (min (length text)
                                (max (edit-state-anchor state)
                                     (edit-state-cursor state))))))))))
    (when (and text (plusp (length text)) (context-copy context))
      (funcall (context-copy context) text))))

(fn (nearest-selection-node (or null element))
    ((nodes (vector element)) (x real) (y real) &optional
     ((target (or null element)) nil))
  "Find the nearest visible text node, preferring vertical proximity before horizontal distance."
  (let ((distance nil) (horizontal nil))
    (loop :for node :across nodes :do
          (let* ((box (element-clip node))
                 (dx (max 0 (- (box-x box) x)
                          (- x (box-right box))))
                 (dy (max 0 (- (box-y box) y)
                          (- y (box-bottom box))))
                 (d dy))
            (when (and (plusp (box-width box))
                       (plusp (box-height box))
                       (or (null distance) (< d distance)
                           (and (= d distance) (< dx
                                                  horizontal))))
              (setf target node distance d horizontal dx)))))
  target)

(fn (start-text-selection text-selection)
    ((renderer renderer) (context context) (nodes (vector element))
     (x real) (y real))
  "Begin a pointer selection in an editor or across selectable text nodes."
  (let ((selection (make-text-selection))
        (target (selection-target context x y)))
    (setf (context-selection context) selection)

    (when (find target nodes)
      (let ((at (selection-index renderer target x y)))
        (setf (text-selection-dragging-p selection) t)
        (if (eq (widget-kind (element-content target)) :text-field)
            (let* ((id (element-id target))
                   (state (or (gethash id (context-state context))
                              (setf (gethash id
                                             (context-state
                                              context))
                                    (make-edit-state)))))
              (setf (text-selection-field selection) id
                    (edit-state-anchor state) at
                    (edit-state-cursor state) at))
            (multiple-value-bind (snapshot keys)
                (selectable-nodes context t)
              (setf (text-selection-node-count selection)
                    (length snapshot)
                    (text-selection-anchor-key selection)
                    (gethash target keys)
                    (text-selection-focus-key selection)
                    (gethash target keys)
                    (text-selection-anchor selection)
                    (cons (position target nodes) at)
                    (text-selection-focus selection)
                    (cons (position target nodes) at)
                    (text-selection-anchor-text selection)
                    (copy-seq (selection-text target))
                    (text-selection-focus-text selection)
                    (copy-seq (selection-text target)))))))
    selection))

(fn (extend-text-selection (values))
    ((renderer renderer) (context context) (selection text-selection)
     (nodes (vector element)) (target (or null element)) (x real) (y real))
  "Extend an editor caret or a multi-node text selection to the pointer position."
  (if (text-selection-field selection)
      (let* ((id (text-selection-field selection))
             (node (find id nodes :key #'element-id :test
                         #'equal))
             (state (gethash id (context-state context))))
        (when (and node state)
          (setf (edit-state-cursor state)
                (selection-index renderer node x y))))
      (when target
        (multiple-value-bind (snapshot keys)
            (selectable-nodes context t)
          (declare (ignore snapshot))
          (setf (text-selection-focus-key selection)
                (gethash target keys)))
        (setf (text-selection-focus selection)
              (cons (position target nodes)
                    (selection-index renderer target x y))
              (text-selection-focus-text selection)
              (copy-seq (selection-text target)))))
  (values))

(fn (selection-input-needed-p boolean)
    ((context context) (events sequence))
  "Test whether input can start, extend, or copy a native text selection."
  (or (and (context-selection context)
           (text-selection-dragging-p
            (context-selection context)))
      (some (lambda (event)
              (or (and (eq (event-kind event) :press)
                       (eq (event-button event) :primary))
                  (and (eq (event-kind event) :key)
                       (eq (event-key event) :copy))))
            events)))

(fn (selection-input (values))
    ((renderer renderer) (context context) (events sequence))
  "Route native pointer and keyboard input to text selection and editor caret state."
  (unless (and (plusp (length events))
               (selection-input-needed-p context events))
    (return-from selection-input (values)))
  (let ((nodes (selectable-nodes context))
        (selection (or (context-selection context)
                       (setf (context-selection context)
                             (make-text-selection)))))
    (loop :for event-index :below (length events)
          :for event := (elt events event-index) :do
          (when (lui.frame:pointer-cancel-p event)
            (setf (text-selection-dragging-p selection) nil))
          (let* ((kind (event-kind event))
                 (x (event-x event)) (y (event-y event))
                 (target
                  (find-if (lambda (node)
                             (lui.frame:contains-p (element-clip node) x y))
                           nodes :from-end t)))
            (when (and (null target) (text-selection-dragging-p selection)
                       (member kind '(:move :release)))
              (setf target (nearest-selection-node nodes x y)))
            (cond
              ((and (eq kind :key) (eq (event-key event) :copy))
               (setf (text-selection-pending-copy-p selection) t))
              ((and (eq kind :press) (eq (event-button event) :primary))
               (setf selection
                     (start-text-selection renderer context nodes x y)))
              ((and (member kind '(:move :release))
                    (text-selection-dragging-p selection))
               (extend-text-selection renderer context selection nodes target
                                      x y)
               (when (eq kind :release)
                 (setf (text-selection-dragging-p selection) nil)))))))
  (values))

(fn (paint-node-selection (values))
    ((renderer renderer) (node element) (text string) (start integer)
     (end integer))
  "Paint the selected character range across the node's wrapped text lines."
  (let ((area (selection-area renderer node)))
    (let ((font (widget-font renderer
                             (element-content node)))
          (offset 0))
      (funcall (renderer-clip renderer) (element-clip node))
      (loop :for line :across
            (wrap-text font text
                       (box-width area))
            :for y :from (box-y area)
            :by (line-height font)
            :for left := (max start offset)
            :for right := (min end (+ offset (length line)))
            :do
            (when (< left right)
              (let ((x (text-width
                        font (subseq text offset left))))
                (shape renderer
                       (make-box
                        :x (+ (selection-left font node area line) x) :y y
                        :width (- (text-width
                                   font
                                   (subseq text offset
                                           right))
                                  x)
                        :height (line-height font))
                       0 (widget-color (element-content
                                        node) :accent)
                       0.4f0)))
            (incf offset (1+ (length line))))))
  (values))

(fn (paint-selection (values)) ((renderer renderer) (context context))
  "Paint selected text ranges using the same wrapping and geometry as text rendering."
  (let ((selection (context-selection context)))
    (when (and selection (text-selection-anchor selection))
      (multiple-value-bind (nodes keys) (selectable-nodes context t)
        (unless (= (length nodes) (text-selection-node-count selection))
          (setf (context-selection context) nil)
          (return-from paint-selection (values)))
        (dolist (endpoint (list (list (text-selection-anchor selection)
                                      (text-selection-anchor-key selection)
                                      (text-selection-anchor-text selection))
                                (list (text-selection-focus selection)
                                      (text-selection-focus-key selection)
                                      (text-selection-focus-text selection))))
          (let ((node (aref nodes (caar endpoint))))
            (unless (and node (equal (gethash node keys) (second endpoint))
                         (equal (selection-text node) (third endpoint)))
              (setf (context-selection context) nil)
              (return-from paint-selection (values)))))
        (loop :for node :across nodes :for i :from 0
              :for text := (selection-text node)
              :do (multiple-value-bind (start end)
                      (selection-range selection i (length text))
                    (when (and start (< start end))
                      (paint-node-selection renderer node text start
                                            end)))))))
  (values))

(fn (finish-selection t) ((renderer renderer) (context context))
  "Reconcile selection against the completed frame and synchronize editor selection."
  (let* ((selection (context-selection context))
         (input (context-focus-input context))
         (focused (and input (equal (car input) (context-focus context))
                       (cdr input)))
         (nodes (when (and selection
                           (or (text-selection-pending-copy-p selection)
                               (and (text-selection-anchor selection)
                                    focused)))
                  (selectable-nodes context)))
         (field (find (context-focus context) nodes :key #'element-id
                      :test #'equal)))
    (when (and selection field
               (eq (widget-kind (element-content field)) :text-field)
               (some (lambda (event)
                       (or (member (event-kind event) '(:text :change))
                           (and (eq (event-kind event) :key)
                                (not (eq (event-key event) :copy)))))
                     focused))
      (setf (text-selection-anchor selection) nil
            (text-selection-focus selection) nil
            (text-selection-dragging-p selection) nil))
    (paint-selection renderer context)
    (when (and selection (eq selection (context-selection context))
               (shiftf (text-selection-pending-copy-p selection) nil))
      (copy-selection context (or nodes (selectable-nodes context))
                      selection))))

(fn (standard-geometry geometry) ((widget widget))
  "Return shared widget geometry for standard toolkit painting and measurement."
  (let* ((kind (widget-kind widget))
         (left (case kind ((:label :panel :canvas :gauge :highlight :splitter
                                   :scrollbar) 0)
                     (:cell 4) (:list-item 6) ((:checkbox :radio) 36)
                     (otherwise 12)))
         (right (case kind ((:checkbox :radio) 12) (otherwise left)))
         (top (if (member kind '(:label :panel :canvas :gauge :highlight
                                 :splitter :scrollbar)) 0 6)))
    (make-geometry
     :value-p (eq kind :text-field) :text-p (not (eq kind :panel))
     :left left :right right :top top :bottom top
     :min-width (if (member kind '(:slider :text-field)) 160 0)
     :center-x (or (member kind '(:button :tab))
                   (and (eq kind :list-item)
                        (lui.widgets:widget-center-text-p widget)))
     :center-y (member kind '(:button :tab)))))

(fn (paint-widget-text t) ((renderer renderer) (node element) (color string))
  "Paint wrapped widget text with resolved font, alignment, and pressed offsets."
  (let* ((widget (element-content node)) (g (widget-geometry widget))
         (pressed (and (not (widget-disabled-p widget)) (hovered-p
                                                         (element-id node))
                       (equal (element-id node) (context-active *context*))))
         (area (text-box widget (element-box node) pressed)))
    (paint-paragraph renderer (widget-text widget) (box-x area) (box-y area)
                     (box-width area) color
                     (when (geometry-center-x g) (box-width area))
                     (when (geometry-center-y g) (box-height area)))))

(fn (paint-paragraph (values))
    ((renderer renderer) (text string) (x real) (y real)
     (wrap-width real) (color string)
     &optional ((center-width (or null real)) nil)
       ((center-height (or null real)) nil))
  "Paint wrapped text, optionally centered within the supplied dimensions."
  (let* ((font (renderer-font renderer))
         (line-height (line-height font))
         (lines (wrap-text font text wrap-width))
         (top (+ y (if center-height
                       (max 0 (/ (- center-height (* (length lines)
                                                     line-height)) 2))
                       0))))
    (loop :for line :across lines
          :for baseline :from (+ top (baseline font)) :by line-height
          :do (paint-text renderer line
                          (+ x
                             (if center-width
                                 (max 0
                                      (/
                                       (- center-width (text-width font
                                                                   line)) 2))
                                 0))
                          baseline color)))
  (values))

(fn (paint-calendar-icon t) ((renderer renderer) (box box) (color string))
  "Draw the compact calendar glyph used by date-picker buttons."
  (let ((x (+ (box-x box) (/ (- (box-width box) 14) 2)))
        (y (+ (box-y box) (/ (- (box-height box) 14) 2))))
    (flet ((bar (dx dy w h)
             (shape renderer (make-box :x (+ x dx) :y (+ y dy) :width w
                                       :height h)
                    0 color 1)))
      (outline renderer (make-box :x x :y (+ y 2) :width 14 :height 12) 1
               color 1 1.5f0)
      (bar 1 5 12 1.5f0) (bar 3 0 2 4) (bar 9 0 2 4))))

(fn (paint-text-field (values))     ((renderer renderer) (node element))
  "Paint editor contents, selection, and caret within the text field's inner clip."
  (let* ((widget (element-content node))
         (font (renderer-font renderer))
         (area (text-box widget (element-box node)))
         (x (box-x area)) (y (box-y area)) (width (box-width area))
         (text (widget-display-value widget))
         (state (when (focused-p node)
                  (gethash (element-id node) (context-state *context*))))
         (cursor (when (typep state 'edit-state)
                   (max 0 (min (length text) (edit-state-cursor state)))))
         (anchor (when cursor
                   (max 0 (min (length text) (edit-state-anchor state)))))
         (start 0))
    (when (zerop (length text))
      (paint-text renderer (widget-text widget) x (+ y (baseline font))
                  (lui.widgets:muted-ink (widget-foreground widget)
                                          (widget-background widget))))
    (loop :for line :across (wrap-text font text width)
          :for top :from y :by (line-height font)
          :for end := (+ start (length line))
          :do (when (and cursor (/= cursor anchor))
                (let ((left (max start (min cursor anchor)))
                      (right (min end (max cursor anchor))))
                  (when (< left right)
                    (shape renderer
                           (make-box
                            :x (+ x (text-width
                                     font (subseq text start left)))
                            :y top
                            :width (- (text-width
                                       font (subseq text start right))
                                      (text-width
                                       font (subseq text start left)))
                            :height (line-height font))
                           0 (widget-accent widget) 0.35f0))))
          (paint-text renderer line x (+ top (baseline font))
                      (if (widget-disabled-p widget) (widget-color widget
                                                                   :disabled)
                          (widget-foreground widget)))
          (when (and cursor (<= start cursor end))
            (shape renderer
                   (make-box :x (+ x (text-width
                                      font (subseq text start cursor)))
                             :y top :width 1 :height (line-height font))
                   0 (widget-foreground widget) 1))
          ;; Wrapping and explicit newlines each consume one separator.
          (setf start (min (length text) (1+ end)))))
  (values))

(fn (paint-canvas (values)) ((renderer renderer) (node element))
  "Execute a widget's custom canvas commands through the active renderer."
  (let ((widget (element-content node)) (box (element-box node)))
    (shape renderer box 0 (widget-background widget) 1)
    (dolist (command (widget-value widget))
      (destructuring-bind (kind cx cy radius stroke fill) command
        (assert (eq kind :circle))
        (let ((circle (make-box :x (+ (box-x box) cx (- radius))
                                :y (+ (box-y box) cy (- radius))
                                :width (* 2 radius) :height (* 2 radius))))
          (when fill (shape renderer circle radius fill 1))
          (when stroke (outline renderer circle radius stroke 1 1))))))
  (values))

(fn (paint-cell t) ((renderer renderer) (node element))
  "Paint a spreadsheet cell with the renderer’s selected widget font."
  (let* ((widget (element-content node))
         (box (element-box node))
         (selected (widget-value widget))
         (text (widget-text widget)))
    (shape renderer box 0 (if selected (widget-color widget :selection)
                              (widget-background widget)) 1)
    (outline renderer box 0 (if selected (widget-accent widget)
                                (widget-color
                                 widget :border))
             1 (if selected 2 1))
    (when (plusp (length text))
      (paint-widget-text renderer node (widget-foreground widget)))))

(fn (paint-focus-ring t) ((renderer renderer) (node element) (radius real))
  "Paint a keyboard-focus outline inside the widget bounds."
  (when (and (focused-p node) (context-focus-visible-p *context*))
    (let ((widget (element-content node))
          (box (element-box node)))
      (outline renderer (inset-box box 2) (max 0 (- radius 2))
               (widget-accent widget) 1 2))))

(fn (paint-calendar-button (values))
    ((renderer renderer) (node element) (box box) (shadow real)
     (foreground string))
  "Paint the calendar button icon with hover and keyboard-focus feedback."
  (let* ((width (max 0 (- (box-width box) shadow)))
         (height (max 0 (- (box-height box) shadow)))
         (size (min 20 width height))
         (mark (make-box :x (+ (box-x box) (/ (- width size) 2))
                         :y (+ (box-y box) (/ (- height size) 2))
                         :width size :height size)))
    (when (hovered-p (element-id node))
      (shape renderer mark (/ size 2) foreground 0.12f0))
    (when (and (focused-p node) (context-focus-visible-p *context*))
      (outline renderer mark (/ size 2) foreground 1 1))
    (paint-calendar-icon renderer mark foreground))
  (values))

(fn (paint-list-item (values))
    ((renderer renderer) (node element) (widget widget) (box box)
     (foreground string))
  "Paint a selectable list row, its focus outline, and its text."
  (shape renderer box 0
         (if (widget-value widget) (widget-accent widget)
             (widget-background widget)) 1)
  (when (and (not (widget-value widget))
             (hovered-p (element-id node)))
    (shape renderer box 0 foreground 0.12f0))
  (when (and (lui.widgets:widget-center-text-p widget) (focused-p node)
             (context-focus-visible-p *context*))
    (outline renderer box 1 (if (widget-value widget)
                                (widget-color widget
                                              :on-accent) foreground) 1 1))
  (paint-widget-text renderer node (if (widget-value widget)
                                       (widget-color
                                        widget :on-accent) foreground))
  (values))

(fn (paint-shared-widget t) ((renderer renderer) (node element) (radius real)
                             (shadow real)
                             (scrollbar function) (body function))
  "Paint shared controls, delegate toolkit bodies, and finish keyboard-focus feedback."
  (let* ((widget (element-content node))
         (box (element-box node))
         (kind (widget-kind widget))
         (disabled (widget-disabled-p widget))
         (pressed (and (not disabled) (hovered-p (element-id node))
                       (equal (element-id node)
                              (context-active *context*))))
         (foreground (if disabled (widget-color widget :disabled)
                         (widget-foreground widget))))
    (cond
      ((eq kind :cell) (paint-cell renderer node))
      ((eq kind :scrollbar) (funcall scrollbar renderer node))
      ((eq kind :splitter)
       (shape renderer
              (if (eq (widget-orientation widget) :horizontal)
                  (make-box :x (box-x box) :width (box-width box)
                            :y (+ (box-y box) (/ (box-height box) 2) -1)
                            :height 2)
                  (make-box :x (+ (box-x box) (/ (box-width box) 2) -1)
                            :y (box-y box) :width 2 :height (box-height box)))
              0 (widget-accent widget)
              (if (or pressed (hovered-p (element-id node))) 1 0.5f0)))
      ((eq kind :highlight)
       (shape renderer box 0 (widget-accent widget)
              (widget-opacity widget))
       (outline renderer box 0 (widget-accent widget) 1 1))
      ((eq (lui.widgets:widget-icon widget) :calendar)
       ;; The field owns the surface and its rounded border.
       (paint-calendar-button renderer node box shadow foreground))
      ((eq kind :list-item)
       (paint-list-item renderer node widget box foreground))
      ((eq kind :gauge)
       (shape renderer box radius (widget-background widget) 1)
       (let ((fill (make-box :x (box-x box) :y (box-y box)
                             :width (* (box-width box) (widget-value widget))
                             :height (box-height box))))
         (shape renderer fill radius (widget-accent widget) 1))
       (outline renderer box radius foreground 1 1))
      ((member kind '(:hr :vr))
       (shape renderer box 0 (widget-foreground widget) 1))
      ((eq kind :canvas) (paint-canvas renderer node))
      (t (funcall body renderer node)))
    (paint-focus-ring renderer node radius)))

(fn (paint-standard-slider (values))
    ((renderer renderer) (widget widget) (box box) (disabled boolean)
     (translucent boolean) (flat boolean))
  "Paint the standard slider indicator using the toolkit surface policy."
  (let ((fraction (/ (- (widget-value widget)
                        (widget-minimum widget))
                     (- (widget-maximum widget)
                        (widget-minimum widget))))
        (track (make-box
                :x (+ (box-x box) 8)
                :y (+ (box-y box) (/ (box-height box) 2) -2)
                :width (max 0 (- (box-width box) 16)) :height 4)))
    (shape renderer track 2 (widget-color widget :track) 1)
    (setf (box-width track) (* fraction (box-width track)))
    (shape renderer track 2
           (if disabled (widget-color widget :disabled-accent) (widget-accent
                                                                widget)) 1)
    (let ((thumb (make-box :x (+ (box-x track) (box-width track) -7)
                           :y (- (box-y track) 5) :width 14 :height 14)))
      (shape renderer thumb (if (or translucent flat) 7 0)
             (widget-color widget (if disabled :disabled-surface
                                      (if flat
                                          :thumb :light))) 1)
      (when flat (outline renderer thumb 7 (widget-color widget :border)
                          0.6f0 1))))
  (values))

(fn (checkbox-fill-color string)
    ((widget widget) (translucent boolean) (flat boolean) (disabled boolean))
  "Resolve the checkbox indicator fill for toolkit style, selection, and disabled state."
  (if (or translucent flat)
      (if (widget-value widget)
          (if (and flat disabled) (widget-color widget :disabled-accent)
              (widget-accent widget))
          (widget-color widget (if flat :light :track)))
      (widget-background widget)))

(fn (paint-standard-checkbox (values))
    ((renderer renderer) (node element) (widget widget) (x real) (y real)
     (disabled boolean) (pressed boolean) (translucent boolean)
     (flat boolean) (bevel (or null function)) (foreground string))
  "Paint the standard checkbox indicator using the toolkit surface policy."
  (let ((indicator (make-box :x x :y y :width 16 :height 16)))
    (shape renderer indicator (if (or translucent flat) 4 0)
           (checkbox-fill-color widget translucent flat disabled)
           1)
    (unless (or translucent (and flat (widget-value widget)))
      (funcall bevel renderer widget indicator
               (or pressed (not (null (widget-value widget)))) disabled))
    (when (widget-value widget)
      (funcall
       (renderer-polygons renderer)
       (make-array 1 :element-type 'contour :initial-element
                   (make-array 6 :element-type 'point :initial-contents
                               (mapcar
                                (lambda (point)
                                  (cons (+ x (car point)) (+ y (cdr
                                                                point))))
                                '((3 . 7) (6 . 10) (12 . 3) (14 . 5)
                                  (6 . 13) (2 . 9)))))
       (if (or translucent flat) (widget-color widget :on-accent) foreground)
       1)))
  (paint-widget-text renderer node foreground)
  (values))

(fn (paint-standard-radio (values))
    ((renderer renderer) (node element) (widget widget) (x real) (y real)
     (disabled boolean) (translucent boolean) (flat boolean)
     (foreground string))
  "Paint the standard radio indicator using the toolkit surface policy."
  (let ((indicator (make-box :x x :y (+ y 1)
                             :width 16 :height 16)))
    (shape renderer indicator 8
           (if (or translucent flat) (widget-color widget :light)
               (widget-background widget)) 1)
    (outline renderer indicator 8
             (if disabled (widget-color widget :disabled)
                 (if flat (widget-color widget :border) foreground)) 1 1)
    (when (widget-value widget)
      (shape renderer (inset-box indicator 5) 3
             (if disabled (widget-color widget :disabled)
                 (if (or translucent flat) (widget-accent widget)
                     foreground)) 1))
    (paint-widget-text renderer node foreground))
  (values))

(fn (paint-standard-surface (values))
    ((renderer renderer) (widget widget) (box box) (kind symbol)
     (radius real) (disabled boolean) (pressed boolean) (translucent boolean)
     (flat boolean) (bevel (or null function)))
  "Paint the control background, optional backdrop effect, and toolkit bevel."
  (unless (or (eq kind :label) (and flat (member kind '(:checkbox :radio
                                                        :slider))))
    (when (and translucent (< (widget-opacity widget) 1)
               (renderer-backdrop-effect renderer))
      (funcall (renderer-backdrop-effect renderer)
               box radius (widget-frost widget)))
    (shape renderer box radius (widget-background widget)
           (if translucent (widget-opacity widget) 1))
    (if translucent
        (outline renderer box radius (widget-color widget :light)
                 (if disabled 0.15f0 0.4f0) 1)
        (unless (member kind '(:checkbox :radio))
          (funcall bevel renderer widget box
                   (or (eq kind :text-field)
                       (and pressed
                            (not (null (member kind '(:button :tab))))))
                   disabled))))
  (values))

(fn (paint-standard-body t)
    ((renderer renderer) (node element) (translucent boolean)
     (bevel (or null function)) &optional ((flat boolean) nil))
  "Paint standard control bodies with the selected toolkit's surface treatment."
  (let* ((widget (element-content node))
         (box (element-box node))
         (kind (widget-kind widget))
         (disabled (widget-disabled-p widget))
         (pressed (and (not disabled) (hovered-p (element-id node))
                       (equal (element-id node)
                              (context-active *context*))))
         (foreground (if disabled (widget-color widget :disabled)
                         (widget-foreground widget)))
         (radius (widget-radius widget))
         (inset (if (eq kind :label) 0 12))
         (x (+ (box-x box) inset))
         (y (+ (box-y box) (if (eq kind :label) 0 6))))
    (paint-standard-surface renderer widget box kind radius disabled pressed
                            translucent flat bevel)
    (when (and (member kind '(:button :tab :checkbox :radio))
               (not (widget-disabled-p widget)))
      (cond
        ((and (hovered-p (element-id node))
              (equal (element-id node) (context-active *context*)))
         (shape renderer box radius (widget-color widget :shadow) 0.2f0))
        ((hovered-p (element-id node))
         (shape renderer box radius (widget-color widget :light) 0.14f0)))
      (when (and (eq kind :tab) (widget-value widget))
        (if flat (shape renderer (inset-box box 1) radius
                   (widget-color
                     widget :selection) 1)
            (shape renderer
                   (make-box :x (+ (box-x box) 3)
                             :y (+ (box-y box) (box-height box) -3)
                             :width (max 0 (- (box-width box) 6)) :height 3)
                   0 (widget-accent widget) 1))))
    (case kind
      (:panel nil)
      (:slider
       (paint-standard-slider renderer widget box disabled translucent flat))
      (:checkbox
       (paint-standard-checkbox renderer node widget x y disabled pressed
                                translucent flat bevel foreground))
      (:radio
       (paint-standard-radio renderer node widget x y disabled translucent
                             flat foreground))
      (:text-field (paint-text-field renderer node))
      (otherwise (paint-widget-text renderer node foreground)))))

(fn (paint-desktop-scrollbar t)
    ((renderer renderer) (node element) (bevel
                                         function))
  "Paint a desktop scrollbar using the supplied track and thumb colors."
  (let ((widget (element-content node)) (thumb (scrollbar-thumb node)))
    (shape renderer (element-box node) 0 (widget-color widget :track) 1)
    (shape renderer thumb 0 (widget-background widget) 1)
    (funcall bevel renderer widget thumb nil (widget-disabled-p widget))))

(fn (register-standard-painter symbol)
    ((name symbol) (radius (or null real)) (scrollbar function)
     (bevel (or null function)) &key ((translucent boolean) nil)
     ((flat boolean) nil))
  "Register standard control painting with toolkit-specific surface callbacks."
  (let ((body (lambda (renderer node)
                (paint-standard-body renderer node translucent bevel flat))))
    (lui.toolkit:register-toolkit-rendering
     name :geometry #'standard-geometry :native-labels t
     :paint (lambda (renderer node)
              (paint-shared-widget
               renderer node
               (or radius (widget-radius (element-content node)))
               0 scrollbar body)))))

(fn (rectangle-path contour) ((box box))
  "Return a polygon contour tracing a rectangular box."
  (let ((x (box-x box)) (y (box-y box))
        (right (box-right box))
        (bottom (box-bottom box)))
    (typed-vector point (cons x y) (cons right y) (cons right bottom)
                  (cons x
                        bottom))))
