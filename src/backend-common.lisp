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
(lui::expose-api font open-font close-font font-size text-width line-height
  baseline wrap-text glyph-polygons *font-path* *font-paths*
  *font-directories* *font-names* font-face)

(defvar *font-path* nil)
(defvar *font-paths* nil)
(defvar *font-directories* nil)
(defvar *font-names* nil)

(defstruct font
  "A browser font face with a Canvas context for measuring text."
  loader
  owner
  (faces (make-array 4 :initial-element nil))
  (size 16)
  (family :sans-serif)
  (weight :normal)
  css-value css-size
  (metrics (make-hash-table :test 'equal))
  (wrapped (make-hash-table :test 'equal)))

(fn (open-font font) (&optional path ((size real) 16))
  "Create a browser font at SIZE; PATH is accepted for API compatibility."
  (declare (ignore path))
  (let ((canvas (#j:document:createElement #j"canvas")))
    (make-font :loader ((jscl/ffi:oget canvas "getContext") #j"2d")
               :size size)))

(fn (close-font null) ((font font))
  (dotimes (index (length (font-faces font)))
    (setf (aref (font-faces font) index) nil))
  (clrhash (font-metrics font))
  (clrhash (font-wrapped font))
  (setf (font-loader font) nil))

(fn (font-face font) ((font font) (family symbol) (weight symbol))
  (let ((owner (or (font-owner font) font))
        (index (+ (ecase family (:sans-serif 0) (:monospace 2))
                  (ecase weight (:normal 0) (:bold 1)))))
    (if (zerop index) owner
        (or (aref (font-faces owner) index)
            (setf (aref (font-faces owner) index)
                  (make-font :loader (font-loader owner) :owner owner
                             :size (font-size owner)
                             :family family :weight weight))))))

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
  (error "Browser text is drawn by the renderer text callback."))

(fn (uncached-wrap-text (vector string)) ((font font) (text string) width)
  "Split TEXT into lines at newlines and spaces; NIL width preserves explicit breaks."
  (lui.text:wrap-lines text width
                      (lambda (text start end)
                        (text-width font (subseq text start end)))))


(fn (wrap-text (vector string)) ((font font) (text string) (width (or null real)))
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
(lui::expose-api font open-font close-font font-size text-width line-height
  baseline wrap-text glyph-polygons *font-path* *font-paths*
  *font-directories* *font-names* font-face)

(defvar *font-path* nil "Override the default TrueType font pathname.")

(defvar *font-paths* nil
  "Optional ((family weight) . pathname) overrides for additional font faces.")

(defstruct font
  "An open TrueType face, its pixel size, and cached glyph outlines."
  loader
  owner
  (faces (make-array 4 :initial-element nil) :type simple-vector)
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
        (error "No TrueType font for ~S. Set LUI.FONT:*FONT-PATHS*." key))))

(fn (default-font (or pathname string)) ()
  (or *font-path* (uiop:getenvp "LUI_FONT")
      (resolve-face :sans-serif :normal)))

(fn (open-font font) (&optional path ((size real) 16))
  "Open a TrueType file at SIZE; a missing PATH uses the configured base face."
  (make-font :loader (zpb-ttf:open-font-loader (or path (default-font)))
             :size size))

(fn (close-font hash-table) ((font font))
  "Release the loader, cached faces, and glyph outlines owned by FONT."
  (dotimes (index 4)
    (let ((face (aref (font-faces font) index)))
      (when face (close-font face))))
  (fill (font-faces font) nil)
  (when (font-loader font)
    (zpb-ttf:close-font-loader (font-loader font))
    (setf (font-loader font) nil))
  (clrhash (font-cache font)))

(fn (font-face font) ((font font) (family symbol) (weight symbol))
  "Resolve a sans-serif or monospace face at normal or bold weight; reuse it until the owner is closed."
  (let ((owner (or (font-owner font) font))
        (index (+ (ecase family (:sans-serif 0) (:monospace 2))
                  (ecase weight (:normal 0) (:bold 1)))))
    (if (zerop index) owner
        (or (aref (font-faces owner) index)
            (let* ((path (resolve-face family weight))
                   (face (open-font path (font-size owner))))
              (setf (font-owner face) owner
                    (aref (font-faces owner) index) face))))))

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

(fn (wrap-text (vector string)) ((font font) (text string) width)
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
                        (loop :for i :from 1 :to 12
                              :for u := (/ i 12.0f0)
                              :for v := (- 1 u)
                              :do (push
                                   (cons
                                    (+ (* v v (zpb-ttf:x p0))
                                       (* 2 u v (zpb-ttf:x p1))
                                       (* u u (zpb-ttf:x p2)))
                                    (+ (* v v (zpb-ttf:y p0))
                                       (* 2 u v (zpb-ttf:y p1))
                                       (* u u (zpb-ttf:y p2))))
                                   points))
                        (push (cons (zpb-ttf:x p2) (zpb-ttf:y p2))
                              points)))
                  (when points (push (coerce (nreverse points) 'contour) polygons))))
              (coerce (nreverse polygons) 'contours))))))

(defpackage #:lui.draw
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame #:lui.widgets #:lui.font)
  (:export #:renderer #:make-renderer #:renderer-font #:renderer-polygons
           #:renderer-clip #:renderer-glass #:renderer-text
           #:renderer-surface #:renderer-stipple
           #:paint-frame #:measure-widget #:widget-font #:focused-p #:shape
           #:outline #:inset-box
           #:geometry #:make-geometry #:geometry-left #:geometry-top
           #:geometry-right
           #:geometry-value-p #:geometry-text-p #:geometry-bottom
           #:geometry-min-width #:geometry-min-height
           #:geometry-center-x #:geometry-center-y #:geometry-offset-x
           #:geometry-offset-y
           #:widget-geometry #:text-box #:rounded-polygon #:color-components
           #:trapezoids #:paint-text))

(in-package #:lui.draw)

(lui::expose-api renderer renderer-font renderer-polygons renderer-clip
  renderer-glass renderer-text geometry make-geometry geometry-left
  geometry-top geometry-right geometry-bottom geometry-min-width
  geometry-min-height geometry-center-x geometry-center-y geometry-offset-x
  geometry-offset-y geometry-text-p geometry-value-p widget-geometry text-box
  rounded-polygon color-components paint-text shape outline inset-box
  focused-p widget-font)

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
  ;; Optional backdrop effect: bounds, corner radius, blur radius.
  (glass nil :type (or null function))
  ;; Optional native glyph cache: font, text, baseline x/y, and color.
  (text nil :type (or null function))
  ;; Optional rectangle primitives avoid contour allocation in browser APIs.
  (surface nil :type (or null function))
  (stipple nil :type (or null function))
  (patterns (make-hash-table :test 'equal) :type hash-table))

(fn (color-components (vector single-float 4)) ((color string) &optional ((alpha real) 1))
  "Return normalized red, green, blue, and alpha in a four-float vector."
  (assert (and (= (length color) 7) (char= (char color 0) #\#)))
  (let ((rgba (make-array 4 :element-type 'single-float)))
    (dotimes (i 3)
      (setf (aref rgba i) (/ (parse-integer color :start (1+ (* i 2))
                                                :end (+ 3 (* i 2)) :radix 16) 255.0f0)))
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
                        :for angle := (* (+ base (* i 11.25f0)) (/ pi 180))
                        :collect
                        (cons (+ cx (* r #-jscl (cos angle)
                                         #+jscl (#j:Math:cos angle)))
                              (+ cy (* r #-jscl (sin angle)
                                         #+jscl (#j:Math:sin angle)))))))))

(fn (trapezoids null) ((contours contours) (emit function))
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
                                     (cons (at-y left bottom) bottom))))))))))

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
  (funcall (or (lui:toolkit-geometry (widget-style widget))
               (error "Toolkit ~S has no graphical geometry." (widget-style widget))) widget))

(fn (measure-widget (values number number)) ((renderer renderer) (widget widget) width)
  "Measure current geometry, reusing matching prior-frame text measurements."
  (let* ((g (widget-geometry widget)) (font (widget-font renderer widget))
         (horizontal (+ (geometry-left g) (geometry-right g)))
         (vertical (+ (geometry-top g) (geometry-bottom g)))
         (text (when (geometry-text-p g)
                 (if (geometry-value-p g)
                     (widget-display-value widget)
                     (widget-text widget))))
         (size (lui.frame::memoized
                (list :measure font (font-loader font) (font-size font)
                      text width horizontal vertical
                      (geometry-min-width g) (geometry-min-height g))
                (lambda ()
                  (let ((lines (if text (wrap-text font text
                                        (when width (max 0 (- width horizontal))))
                                   #())) (widest 0))
                    (dotimes (i (length lines))
                      (setf widest (max widest (text-width font (aref lines i)))))
                    (cons (max (geometry-min-width g) (+ horizontal widest))
                          (max (geometry-min-height g)
                               (+ vertical (* (length lines) (line-height font))))))))))
    (values (car size) (cdr size))))

(fn (text-box box) ((widget widget) (box box) &optional pressed)
  "Return the toolkit's text area, including pressed displacement."
  (let ((g (widget-geometry widget)))
    (make-box :x (+ (box-x box) (geometry-left g) (if pressed (geometry-offset-x g) 0))
              :y (+ (box-y box) (geometry-top g) (if pressed (geometry-offset-y g) 0))
              :width (max 0 (- (box-width box) (geometry-left g) (geometry-right g)))
              :height (max 0 (- (box-height box) (geometry-top g) (geometry-bottom g))))))

(fn (paint-text t) ((renderer renderer) (text string) (x real) (y real) (color string))
  "Draw TEXT at horizontal position X and baseline Y in COLOR."
  (unless (zerop (length text))
    (if (renderer-text renderer)
        (funcall (renderer-text renderer) (renderer-font renderer)
                 text x y color)
        #+(or jscl lui-ecl-web)
        (error "The browser renderer requires a text drawing callback.")
        #-(or jscl lui-ecl-web)
        (let* ((font (renderer-font renderer))
               (scale (/ (font-size font) (zpb-ttf:units/em (font-loader font))))
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

(fn (shape t) ((renderer renderer) (box box) (radius real) (color string) (alpha real))
  "Fill BOX with COLOR at ALPHA opacity using rounded corners of RADIUS."
  (if (renderer-surface renderer)
      (funcall (renderer-surface renderer) box radius color alpha)
      (funcall (renderer-polygons renderer)
               (make-array 1 :element-type 'contour :initial-element (rounded-polygon box radius)) color alpha)))

(fn (outline t) ((renderer renderer) (box box) (radius real) (color string)
     (alpha real) (thickness real))
  "Stroke the inside edge of BOX with the given THICKNESS and corner RADIUS."
  (if (renderer-surface renderer)
      (funcall (renderer-surface renderer)
               box radius color alpha thickness)
      (funcall (renderer-polygons renderer)
               (typed-vector contour (rounded-polygon box radius)
                      (reverse (rounded-polygon (inset-box box thickness)
                                                (max 0 (- radius thickness)))))
               color alpha)))

(fn (focused-p boolean) ((node element))
  "Return true when NODE has input focus in the current frame."
  (and (element-interactive-p node)
       (boundp '*context*)
       (equal (element-id node) (context-focus *context*))
       (not (widget-disabled-p (element-content node)))))

(fn (paint-widget t) ((renderer renderer) (node element))
  (let* ((widget (element-content node))
         (paint (or (widget-painter widget) (lui:toolkit-paint (widget-style widget))
                    (error "Toolkit ~S has no graphical painter." (widget-style widget))))
         (font (renderer-font renderer)))
    (funcall (renderer-clip renderer) (element-clip node))
    (unwind-protect
         (progn (setf (renderer-font renderer) (widget-font renderer widget))
                (funcall paint renderer node))
      (setf (renderer-font renderer) font))))

(fn (paint-frame t) ((renderer renderer) (context context) &optional external-labels viewport)
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
                        (and (< (box-y clip) (+ (box-y viewport) (box-height viewport)))
                             (< (box-y viewport) (+ (box-y clip) (box-height clip))))))
                  (not (and external-labels (gethash node external-labels))))
         (paint-widget renderer node))))
    (finish-selection renderer context)))


(defstruct text-selection
  anchor focus anchor-text focus-text anchor-key focus-key field
  (node-count 0 :type integer)
  (pending-copy-p nil :type boolean)
  (dragging-p nil :type boolean))

(fn (selectable-nodes (values (vector element) (or null hash-table))) ((context context) &optional keys-p)
  (let ((nodes (make-array 0 :element-type 'element :adjustable t :fill-pointer 0)) (keys (when keys-p (make-hash-table :test 'eq))))
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
  (let ((target nil))
    (walk-elements
     (context-root context)
     (lambda (node)
       (when (and (widget-p (element-content node))
                  (lui.frame::contains-p (element-clip node) x y))
         (setf target node))))
    target))

(fn (selection-text string) ((node element))
  (let ((widget (element-content node)))
    (if (eq (widget-kind widget) :text-field)
        (widget-display-value widget) (widget-text widget))))

(fn (selection-area box) ((renderer renderer) (node element))
  (let* ((widget (element-content node)) (area (text-box widget (element-box node)))
         (font (widget-font renderer widget)) (g (widget-geometry widget)))
    (when (geometry-center-y g)
      (incf (box-y area) (max 0 (/ (- (box-height area)
                                    (* (length (wrap-text font (selection-text node)
                                                          (box-width area)))
                                       (line-height font))) 2))))
    area))

(fn (selection-left real) ((font font) (node element) (area box) (line string))
  (+ (box-x area) (if (geometry-center-x (widget-geometry (element-content node)))
                     (max 0 (/ (- (box-width area) (text-width font line)) 2)) 0)))

(fn (selection-index integer) ((renderer renderer) (node element) (x real) (y real))
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
                                           previous char (font-loader font))
                                          0))))))
                  (when (< at (/ (+ left right) 2))
                    (return-from selection-index (+ start i)))
                  (setf left right)
                  #-(or jscl lui-ecl-web) (setf previous char))))
            (return-from selection-index (+ start (length line)))))
        (incf start (1+ (length line)))
        (incf top (line-height font))
        :finally (return (length text))))))

(fn (selection-range (values (or null integer) &optional (or null integer))) ((selection text-selection) (index integer)
                    (length integer))
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

(fn (selection-input null) ((renderer renderer) (context context) (events sequence))
  (unless (and (plusp (length events))
               (or (and (context-selection context)
                        (text-selection-dragging-p
                         (context-selection context)))
                   (some (lambda (event)
                           (or (and (eq (event-kind event) :press)
                                    (eq (event-button event) :primary))
                               (and (eq (event-kind event) :key)
                                    (eq (event-key event) :copy))))
                         events)))
    (return-from selection-input nil))
  (let ((nodes (selectable-nodes context))
        (selection (or (context-selection context)
                       (setf (context-selection context)
                             (make-text-selection)))))
    (loop :for event-index :below (length events)
          :for event := (elt events event-index) :do
          (when (lui.frame::pointer-cancel-p event)
            (setf (text-selection-dragging-p selection) nil))
          (let* ((kind (event-kind event))
                 (x (event-x event)) (y (event-y event))
                 (target
                  (find-if (lambda (node)
                             (lui.frame::contains-p (element-clip node) x y))
                           nodes :from-end t)))
            (when (and (null target) (text-selection-dragging-p selection)
                       (member kind '(:move :release)))
              (let ((distance nil) (horizontal nil))
                (loop :for node :across nodes :do
                      (let* ((box (element-clip node))
                             (dx (max 0 (- (box-x box) x)
                                      (- x (+ (box-x box) (box-width box)))))
                             (dy (max 0 (- (box-y box) y)
                                      (- y (+ (box-y box) (box-height box)))))
                             (d dy))
                        (when (and (plusp (box-width box))
                                   (plusp (box-height box))
                                   (or (null distance) (< d distance)
                                       (and (= d distance) (< dx
                                                              horizontal))))
                          (setf target node distance d horizontal dx))))))
            (cond
              ((and (eq kind :key) (eq (event-key event) :copy))
               (setf (text-selection-pending-copy-p selection) t))
              ((and (eq kind :press) (eq (event-button event) :primary))
               (setf (context-selection context)
                     (setf selection (make-text-selection)))
               (setf target (selection-target context x y))
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
                               (copy-seq (selection-text target))))))))
              ((and (member kind '(:move :release))
                    (text-selection-dragging-p selection))
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
               (when (eq kind :release)
                 (setf (text-selection-dragging-p selection) nil))))))))

(fn (paint-selection null) ((renderer renderer) (context context))
  (let ((selection (context-selection context)))
    (when (and selection (text-selection-anchor selection))
      (multiple-value-bind (nodes keys) (selectable-nodes context t)
        (unless (= (length nodes) (text-selection-node-count selection))
          (setf (context-selection context) nil)
          (return-from paint-selection nil))
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
              (return-from paint-selection nil))))
        (loop :for node :across nodes :for i :from 0
              :for text := (selection-text node)
              :do (multiple-value-bind (start end)
                      (selection-range selection i (length text))
                    (when (and start (< start end))
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
                                (incf offset (1+ (length line)))))))))))))

(fn (finish-selection t) ((renderer renderer) (context context))
  (let* ((selection (context-selection context))
         (input (context-focus-input context))
         (focused (and input (equal (car input) (context-focus context))
                       (cdr input)))
         (nodes (when (and selection
                           (or (text-selection-pending-copy-p selection)
                               (and (text-selection-anchor selection) focused)))
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
  (let* ((kind (widget-kind widget))
         (left (case kind ((:label :panel :canvas :gauge :highlight :splitter :scrollbar) 0)
                     (:cell 4) (:list-item 6) ((:checkbox :radio) 36) (otherwise 12)))
         (right (case kind ((:checkbox :radio) 12) (otherwise left)))
         (top (if (member kind '(:label :panel :canvas :gauge :highlight :splitter :scrollbar)) 0 6)))
    (make-geometry :value-p (eq kind :text-field) :text-p (not (eq kind :panel)) :left left :right right :top top :bottom top
                   :min-width (if (member kind '(:slider :text-field)) 160 0)
                   :center-x (or (member kind '(:button :tab))
                                 (and (eq kind :list-item) (lui.widgets::widget-center-text-p widget)))
                   :center-y (member kind '(:button :tab)))))

(fn (paint-widget-text t) ((renderer renderer) (node element) (color string))
  (let* ((widget (element-content node)) (g (widget-geometry widget))
         (pressed (and (not (widget-disabled-p widget)) (hovered-p (element-id node))
                       (equal (element-id node) (context-active *context*))))
         (area (text-box widget (element-box node) pressed)))
    (paint-paragraph renderer (widget-text widget) (box-x area) (box-y area)
                     (box-width area) color
                     (when (geometry-center-x g) (box-width area))
                     (when (geometry-center-y g) (box-height area)))))

(fn (paint-paragraph null) ((renderer renderer) (text string) (x real) (y real)
                    (wrap-width real) (color string)
                    &optional ((center-width (or null real)) nil)
                              ((center-height (or null real)) nil))
  "Paint wrapped text, optionally centered within the supplied dimensions."
  (let* ((font (renderer-font renderer))
         (line-height (line-height font))
         (lines (wrap-text font text wrap-width))
         (top (+ y (if center-height
                       (max 0 (/ (- center-height (* (length lines) line-height)) 2))
                       0))))
    (loop :for line :across lines
          :for baseline :from (+ top (baseline font)) :by line-height
          :do (paint-text renderer line
                         (+ x (if center-width
                                  (max 0 (/ (- center-width (text-width font line)) 2))
                                  0))
                         baseline color))))

(fn (paint-calendar-icon t) ((renderer renderer) (box box) (color string))
  (let ((x (+ (box-x box) (/ (- (box-width box) 14) 2)))
        (y (+ (box-y box) (/ (- (box-height box) 14) 2))))
    (flet ((bar (dx dy w h)
             (shape renderer (make-box :x (+ x dx) :y (+ y dy) :width w :height h)
                    0 color 1)))
      (outline renderer (make-box :x x :y (+ y 2) :width 14 :height 12) 1
               color 1 1.5f0)
      (bar 1 5 12 1.5f0) (bar 3 0 2 4) (bar 9 0 2 4))))

(fn (paint-text-field null)     ((renderer renderer) (node element))
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
                  (lui.widgets::muted-ink (widget-foreground widget) (widget-background widget))))
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
                          (if (widget-disabled-p widget) (widget-color widget :disabled)
                              (widget-foreground widget)))
              (when (and cursor (<= start cursor end))
                (shape renderer
                       (make-box :x (+ x (text-width
                                         font (subseq text start cursor)))
                                 :y top :width 1 :height (line-height font))
                       0 (widget-foreground widget) 1))
              ;; Wrapping and explicit newlines each consume one separator.
              (setf start (min (length text) (1+ end))))))

(fn (paint-canvas null) ((renderer renderer) (node element))
  (let ((widget (element-content node)) (box (element-box node)))
    (shape renderer box 0 (widget-background widget) 1)
    (dolist (command (widget-value widget))
      (destructuring-bind (kind cx cy radius stroke fill) command
        (assert (eq kind :circle))
        (let ((circle (make-box :x (+ (box-x box) cx (- radius))
                                :y (+ (box-y box) cy (- radius))
                                :width (* 2 radius) :height (* 2 radius))))
          (when fill (shape renderer circle radius fill 1))
          (when stroke (outline renderer circle radius stroke 1 1)))))))

(fn (paint-cell t) ((renderer renderer) (node element))
  "Paint a spreadsheet cell with the renderer’s selected widget font."
  (let* ((widget (element-content node))
         (box (element-box node))
         (selected (widget-value widget))
         (text (widget-text widget)))
    (shape renderer box 0 (if selected (widget-color widget :selection) (widget-background widget)) 1)
    (outline renderer box 0 (if selected (widget-accent widget) (widget-color widget :border))
             1 (if selected 2 1))
    (when (plusp (length text))
      (paint-widget-text renderer node (widget-foreground widget)))))

(fn (paint-focus-ring t) ((renderer renderer) (node element) (radius real))
  (when (and (focused-p node) (context-focus-visible-p *context*))
    (let ((widget (element-content node))
          (box (element-box node)))
      (outline renderer (inset-box box 2) (max 0 (- radius 2))
               (widget-accent widget) 1 2))))

(fn (paint-shared-widget t) ((renderer renderer) (node element) (radius real) (shadow real)
     (scrollbar function) (body function))
  (let* ((widget (element-content node))
         (box (element-box node))
         (kind (widget-kind widget))
         (disabled (widget-disabled-p widget))
         (pressed (and (not disabled) (hovered-p (element-id node))
                       (equal (element-id node)
                              (context-active *context*))))
         (foreground (if disabled (widget-color widget :disabled) (widget-foreground widget))))
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
      ((eq (lui.widgets::widget-icon widget) :calendar)
       ;; The field owns the surface and its rounded border.
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
         (paint-calendar-icon renderer mark foreground)))
      ((eq kind :list-item)
       (shape renderer box 0
              (if (widget-value widget) (widget-accent widget)
                  (widget-background widget)) 1)
       (when (and (not (widget-value widget))
                  (hovered-p (element-id node)))
         (shape renderer box 0 foreground 0.12f0))
       (when (and (lui.widgets::widget-center-text-p widget) (focused-p node)
                  (context-focus-visible-p *context*))
         (outline renderer box 1 (if (widget-value widget) (widget-color widget :on-accent) foreground) 1 1))
       (paint-widget-text renderer node (if (widget-value widget) (widget-color widget :on-accent) foreground)))
      ((eq kind :gauge)
       (shape renderer box radius (widget-background widget) 1)
       (let ((fill (make-box :x (box-x box) :y (box-y box)
                             :width (* (box-width box) (widget-value widget))
                             :height (box-height box))))
         (shape renderer fill radius (widget-accent widget) 1))
       (outline renderer box radius foreground 1 1))
      ((eq kind :canvas) (paint-canvas renderer node))
      (t (funcall body renderer node)))
    (paint-focus-ring renderer node radius)))

(fn (paint-standard-body t) ((renderer renderer) (node element) translucent bevel
                                      &optional flat)
  (let* ((widget (element-content node))
         (box (element-box node))
         (kind (widget-kind widget))
         (disabled (widget-disabled-p widget))
         (pressed (and (not disabled) (hovered-p (element-id node))
                       (equal (element-id node)
                              (context-active *context*))))
         (foreground (if disabled (widget-color widget :disabled) (widget-foreground widget)))
         (radius (widget-radius widget))
         (inset (if (eq kind :label) 0 12))
         (x (+ (box-x box) inset))
         (y (+ (box-y box) (if (eq kind :label) 0 6))))
    (unless (or (eq kind :label) (and flat (member kind '(:checkbox :radio :slider))))
      (when (and translucent (< (widget-opacity widget) 1)
                 (renderer-glass renderer))
        (funcall (renderer-glass renderer)
                 box radius (widget-frost widget)))
      (shape renderer box radius (widget-background widget)
             (if translucent (widget-opacity widget) 1))
      (if translucent
          (outline renderer box radius (widget-color widget :light)
                   (if disabled 0.15f0 0.4f0) 1)
          (unless (member kind '(:checkbox :radio))
            (funcall bevel renderer widget box
                        (or (eq kind :text-field)
                            (and pressed (member kind '(:button :tab))))
                        disabled))))
    (when (and (member kind '(:button :tab :checkbox :radio))
               (not (widget-disabled-p widget)))
      (cond
        ((and (hovered-p (element-id node))
              (equal (element-id node) (context-active *context*)))
         (shape renderer box radius (widget-color widget :shadow) 0.2f0))
        ((hovered-p (element-id node))
         (shape renderer box radius (widget-color widget :light) 0.14f0)))
      (when (and (eq kind :tab) (widget-value widget))
        (if flat (shape renderer (inset-box box 1) radius (widget-color widget :selection) 1)
        (shape renderer
               (make-box :x (+ (box-x box) 3)
                         :y (+ (box-y box) (box-height box) -3)
                         :width (max 0 (- (box-width box) 6)) :height 3)
               0 (widget-accent widget) 1))))
    (case kind
      (:panel nil)
      (:slider
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
                (if disabled (widget-color widget :disabled-accent) (widget-accent widget)) 1)
         (let ((thumb (make-box :x (+ (box-x track) (box-width track) -7)
                                :y (- (box-y track) 5) :width 14 :height 14)))
           (shape renderer thumb (if (or translucent flat) 7 0)
                  (widget-color widget (if disabled :disabled-surface (if flat :thumb :light))) 1)
           (when flat (outline renderer thumb 7 (widget-color widget :border)
                               0.6f0 1)))))
      (:checkbox
       (let ((indicator (make-box :x x :y y :width 16 :height 16)))
         (shape renderer indicator (if (or translucent flat) 4 0)
                (if (or translucent flat)
                    (if (widget-value widget)
                        (if (and flat disabled) (widget-color widget :disabled-accent) (widget-accent widget))
                        (widget-color widget (if flat :light :track)))
                    (widget-background widget))
                1)
         (unless (or translucent (and flat (widget-value widget)))
           (funcall bevel renderer widget indicator
                        (or pressed (widget-value widget)) disabled))
         (when (widget-value widget)
           (funcall
            (renderer-polygons renderer)
            (make-array 1 :element-type 'contour :initial-element
             (make-array 6 :element-type 'point :initial-contents
              (mapcar (lambda (point)
                            (cons (+ x (car point)) (+ y (cdr point))))
                          '((3 . 7) (6 . 10) (12 . 3) (14 . 5)
                            (6 . 13) (2 . 9)))))
            (if (or translucent flat) (widget-color widget :on-accent) foreground) 1)))
       (paint-widget-text renderer node foreground))
      (:radio
       (let ((indicator (make-box :x x :y (+ y 1)
                                  :width 16 :height 16)))
         (shape renderer indicator 8
                (if (or translucent flat) (widget-color widget :light) (widget-background widget)) 1)
         (outline renderer indicator 8
                  (if disabled (widget-color widget :disabled)
                      (if flat (widget-color widget :border) foreground)) 1 1)
         (when (widget-value widget)
           (shape renderer (inset-box indicator 5) 3
                  (if disabled (widget-color widget :disabled)
                      (if (or translucent flat) (widget-accent widget) foreground)) 1))
         (paint-widget-text renderer node foreground)))
      (:text-field (paint-text-field renderer node))
      (otherwise (paint-widget-text renderer node foreground)))))


(fn (paint-glass-scrollbar t) ((renderer renderer) (node element))
  (let* ((widget (element-content node)) (box (element-box node))
         (thumb (scrollbar-thumb node))
         (hover (or (hovered-p (element-id node))
                    (equal (element-id node) (context-active *context*))))
         (foreground (if (widget-disabled-p widget) (widget-color widget :disabled)
                         (widget-foreground widget)))
         (inset (min 2 (/ (min (box-width thumb) (box-height thumb)) 4)))
         (face (inset-box thumb inset)) (radius (/ (box-width face) 2)))
    (shape renderer box (/ (box-width box) 2) foreground 0.08f0)
    (shape renderer face radius foreground (if hover 0.5f0 0.32f0))
    (outline renderer face radius foreground 0.4f0
             (min 1 (/ (box-width face) 2)))))

(fn (paint-glass-body t) ((renderer renderer) (node element))
  (paint-standard-body renderer node t nil))

(fn (paint-glass-widget t) ((renderer renderer) (node element))
  (paint-shared-widget renderer node (widget-radius (element-content node)) 0
                       #'paint-glass-scrollbar #'paint-glass-body))

(lui:register-toolkit-rendering :glass :paint #'paint-glass-widget
                               :geometry #'standard-geometry :native-labels t)


(fn (motif-bevel t) ((renderer renderer) (widget widget) (box box)
                 &optional recessed disabled)
  (let* ((light (if disabled (widget-color widget :disabled-bevel-light) (widget-color widget :bevel-light)))
         (dark (if disabled (widget-color widget :disabled-bevel-dark) (widget-color widget :bevel-dark)))
         (x (box-x box))
         (y (box-y box))
         (right (+ x (box-width box)))
         (bottom (+ y (box-height box)))
         (edge (min 2 (/ (box-width box) 2) (/ (box-height box) 2))))
    (funcall (renderer-polygons renderer)
             (make-array 1 :element-type 'contour :initial-element
              (typed-vector point (cons x y) (cons right y)
                         (cons (- right edge) (+ y edge))
                         (cons (+ x edge) (+ y edge))
                         (cons (+ x edge) (- bottom edge))
                         (cons x bottom)))
             (if recessed dark light) 1)
    (funcall (renderer-polygons renderer)
             (make-array 1 :element-type 'contour :initial-element
              (typed-vector point (cons x bottom) (cons right bottom)
                         (cons right y) (cons (- right edge) (+ y edge))
                         (cons (- right edge) (- bottom edge))
                         (cons (+ x edge) (- bottom edge))))
             (if recessed light dark) 1)))

(fn (paint-motif-scrollbar t) ((renderer renderer) (node element))
  (let* ((widget (element-content node))
         (foreground (if (widget-disabled-p widget) (widget-color widget :disabled)
                         (widget-foreground widget))))
    (shape renderer (element-box node) 0 foreground 0.15f0)
    (shape renderer (scrollbar-thumb node) 0 (widget-accent widget) 1)))

(fn (paint-motif-body t) ((renderer renderer) (node element))
  (paint-standard-body renderer node nil #'motif-bevel))

(fn (paint-motif-widget t) ((renderer renderer) (node element))
  (paint-shared-widget renderer node 0 0 #'paint-motif-scrollbar #'paint-motif-body))

(lui:register-toolkit-rendering :motif :paint #'paint-motif-widget
                               :geometry #'standard-geometry :native-labels t)


(fn (macos-bevel t) ((renderer renderer) (widget widget) (box box)
                    &optional recessed disabled)
  (declare (ignore recessed))
  (outline renderer box (min 6 (widget-radius widget))
           (widget-color widget (if disabled :disabled-surface :border))
           0.65f0 1))

(fn (qt-bevel t) ((renderer renderer) (widget widget) (box box)
                 &optional recessed disabled)
  (let ((light (widget-color widget (if disabled :disabled-bevel-light :bevel-light)))
        (dark (widget-color widget (if disabled :disabled-bevel-dark :bevel-dark)))
        (x (box-x box)) (y (box-y box))
        (width (box-width box)) (height (box-height box)))
    (outline renderer box 2 (widget-color widget :border) 1 1)
    (when (> (min width height) 4)
      (shape renderer (make-box :x (+ x 2) :y (+ y 1) :width (- width 4) :height 1)
             0 (if recessed dark light) 1)
      (shape renderer (make-box :x (+ x 2) :y (+ y height -2) :width (- width 4) :height 1)
             0 (if recessed light dark) 1))))

(fn (paint-macos-body t) ((renderer renderer) (node element))
  (paint-standard-body renderer node nil #'macos-bevel t))

(fn (paint-qt-body t) ((renderer renderer) (node element))
  (paint-standard-body renderer node nil #'qt-bevel))

(fn (paint-desktop-scrollbar t) ((renderer renderer) (node element) (bevel function))
  (let ((widget (element-content node)) (thumb (scrollbar-thumb node)))
    (shape renderer (element-box node) 0 (widget-color widget :track) 1)
    (shape renderer thumb 0 (widget-background widget) 1)
    (funcall bevel renderer widget thumb nil (widget-disabled-p widget))))

(fn (paint-macos-scrollbar t) ((renderer renderer) (node element))
  (shape renderer (inset-box (scrollbar-thumb node) 2) 4
         (widget-color (element-content node) :track) 0.8f0))

(fn (paint-qt-scrollbar t) ((renderer renderer) (node element))
  (paint-desktop-scrollbar renderer node #'qt-bevel))

(fn (paint-macos-widget t) ((renderer renderer) (node element))
  (paint-shared-widget renderer node 6 0 #'paint-macos-scrollbar #'paint-macos-body))

(fn (paint-qt-widget t) ((renderer renderer) (node element))
  (paint-shared-widget renderer node 2 0 #'paint-qt-scrollbar #'paint-qt-body))

(lui:register-toolkit-rendering :macos :paint #'paint-macos-widget
                               :geometry #'standard-geometry :native-labels t)
(lui:register-toolkit-rendering :qt :paint #'paint-qt-widget
                               :geometry #'standard-geometry :native-labels t)


(fn (rectangle-path contour) ((box box))
  (let ((x (box-x box)) (y (box-y box))
        (right (+ (box-x box) (box-width box)))
        (bottom (+ (box-y box) (box-height box))))
    (typed-vector point (cons x y) (cons right y) (cons right bottom) (cons x bottom))))

(fn (garnet-fill t) ((renderer renderer) (box box) (color string))
  (when (and (plusp (box-width box)) (plusp (box-height box)))
    (funcall (renderer-polygons renderer)
             (make-array 1 :element-type 'contour :initial-element (rectangle-path box)) color 1)))

(fn (garnet-outline t) ((renderer renderer) (widget widget) (box box)
                   &optional ((thickness real) 1))
  (when (and (plusp (box-width box)) (plusp (box-height box)))
    (let ((inner (inset-box box thickness)))
      (funcall (renderer-polygons renderer)
               (if (and (plusp (box-width inner)) (plusp (box-height inner)))
                   (typed-vector contour (rectangle-path box) (reverse (rectangle-path inner)))
                   (make-array 1 :element-type 'contour :initial-element (rectangle-path box)))
               (widget-color widget :outline) 1))))

(fn (garnet-stipple t) ((renderer renderer) (widget widget) (box box) &optional border)
  (when (renderer-stipple renderer)
    (return-from garnet-stipple
      (funcall (renderer-stipple renderer) box border (widget-color widget :outline))))
  ;; One cached contour batch, with opaque white underlay supplied by the face.
  (let* ((key (list (box-x box) (box-y box) (box-width box)
                    (box-height box) border))
         (cache (renderer-patterns renderer))
         (paths (gethash key cache)))
    (unless paths
      (when (>= (hash-table-count cache) 256) (clrhash cache))
      (let ((left (ceiling (box-x box))) (top (ceiling (box-y box)))
            (right (floor (+ (box-x box) (box-width box))))
            (bottom (floor (+ (box-y box) (box-height box)))))
        (let ((squares
                (loop :for y :from top :below bottom
                      :nconc
                      (loop :for x :from (+ left (mod (+ left y) 2))
                            :below right :by 2
                            :when (or (null border)
                                      (< x (+ left border))
                                      (>= x (- right border))
                                      (< y (+ top border))
                                      (>= y (- bottom border)))
                            :collect
                            (typed-vector point
                              (cons x y) (cons (1+ x) y)
                              (cons (1+ x) (1+ y)) (cons x (1+ y)))))))
          (setf paths (make-array (length squares) :element-type 'contour
                                  :initial-contents squares)
                (gethash key cache) paths))))
    (when paths
      (funcall (renderer-polygons renderer) paths (widget-color widget :outline) 1))))

(fn (garnet-slider t) ((renderer renderer) (widget widget) (track box) (thumb box)
                  (background string) hover)
  (garnet-fill renderer track (widget-color widget :light))
  (garnet-stipple renderer widget (inset-box track 1))
  (garnet-outline renderer widget track)
  (garnet-fill renderer thumb background)
  (garnet-outline renderer widget thumb (if hover 2 1)))

(defconstant +garnet-shadow-offset+ 4)

(fn (garnet-face box) ((renderer renderer) (widget widget) (box box) (background string)
                &optional pressed ((band integer) 3))
  (let* ((shadow (make-box :x (+ (box-x box) +garnet-shadow-offset+) :y (+ (box-y box) +garnet-shadow-offset+)
                           :width (max 0 (- (box-width box) +garnet-shadow-offset+))
                           :height (max 0 (- (box-height box) +garnet-shadow-offset+))))
         (face (make-box :x (+ (box-x box) (if pressed +garnet-shadow-offset+ 0))
                         :y (+ (box-y box) (if pressed +garnet-shadow-offset+ 0))
                         :width (box-width shadow)
                         :height (box-height shadow))))
    (garnet-fill renderer shadow (widget-color widget :shadow))
    (garnet-fill renderer face (if (plusp band) (widget-color widget :light) background))
    (when (plusp band)
      (garnet-stipple renderer widget (inset-box face 1) band)
      (garnet-fill renderer (inset-box face (1+ band)) background)
      (garnet-outline renderer widget (inset-box face (1+ band))))
    (garnet-outline renderer widget face)
    face))

(fn (paint-garnet t) ((renderer renderer) (node element))
  (let* ((widget (element-content node))
         (box (element-box node))
         (kind (widget-kind widget))
         (disabled (widget-disabled-p widget))
         (hover (and (not disabled) (hovered-p (element-id node))))
         (pressed (and hover (equal (element-id node)
                                   (context-active *context*))))
         (ink (if disabled (widget-color widget :disabled) (widget-foreground widget))))
    (case kind
      (:label
       (paint-widget-text renderer node ink))
      (:panel
       (if (and (= 0 (box-x box) (box-y box))
                (= (box-width box) (context-width *context*))
                (= (box-height box) (context-height *context*)))
           (garnet-fill renderer box (widget-background widget))
           (garnet-face renderer widget box (widget-background widget) nil 0)))
      ((:button :tab)
       (let* ((face (garnet-face renderer widget box
                                 (widget-background widget) pressed))
              (field (inset-box face 4))
              (selected (and (eq kind :tab) (widget-value widget))))
         (when selected (garnet-fill renderer field (widget-color widget :outline)))
         (when hover (garnet-outline renderer widget field 2))
         (paint-widget-text renderer node (if selected (widget-color widget :on-accent) ink))))
      (:checkbox
       (let* ((square (make-box :x (- (+ (box-x box) (box-width box)) 24)
                               :y (+ (box-y box)
                                     (max 0 (/ (- (box-height box) 24) 2)))
                               :width 24 :height 24))
              (face (garnet-face renderer widget square (widget-color widget :light) pressed)))
         (when hover (garnet-outline renderer widget (inset-box face 4) 2))
         (when (widget-value widget)
           (let ((x (+ (box-x face) 5)) (y (+ (box-y face) 5)))
             ;; Separate strokes avoid crossing edges within one tessellation.
             (dolist (stroke
                      (list (list (cons x y) (cons (+ x 2) y)
                                  (cons (+ x 10) (+ y 10))
                                  (cons (+ x 8) (+ y 10)))
                            (list (cons (+ x 8) y) (cons (+ x 10) y)
                                  (cons (+ x 2) (+ y 10))
                                  (cons x (+ y 10)))))
               (funcall (renderer-polygons renderer)
                        (make-array 1 :element-type 'contour
                                      :initial-element (make-array 4 :element-type 'point :initial-contents stroke)) ink 1))))
         (paint-widget-text renderer node ink)))
      (:radio
       (let ((indicator (make-box :x (- (+ (box-x box) (box-width box)) 22)
                                  :y (+ (box-y box)
                                        (max 0 (/ (- (box-height box) 18) 2)))
                                  :width 18 :height 18)))
         (shape renderer indicator 9 (widget-color widget :light) 1)
         (outline renderer indicator 9 ink 1 1)
         (when (widget-value widget)
           (shape renderer (inset-box indicator 5) 4 ink 1))
         (when hover (garnet-outline renderer widget indicator 2))
         (paint-widget-text renderer node ink)))
      (:slider
       (let* ((track (make-box :x (+ (box-x box) 8)
                               :y (+ (box-y box) (/ (box-height box) 2) -6)
                               :width (max 0 (- (box-width box) 16))
                               :height 12))
              (fraction (/ (- (widget-value widget) (widget-minimum widget))
                           (- (widget-maximum widget)
                              (widget-minimum widget))))
              (thumb (make-box :x (+ (box-x track)
                                    (* fraction
                                       (max 0 (- (box-width track) 18))))
                               :y (- (box-y track) 3) :width 18 :height 18)))
         (garnet-slider renderer widget track thumb (widget-background widget)
                        hover)))
      (:text-field
       (garnet-fill renderer box (widget-background widget))
       (garnet-outline renderer widget box)
       (paint-text-field renderer node))
      (otherwise nil))))

(fn (paint-garnet-scrollbar t) ((renderer renderer) (node element))
  (let* ((widget (element-content node)) (thumb (scrollbar-thumb node))
         (inset (min 2 (/ (min (box-width thumb) (box-height thumb)) 4))))
    (garnet-slider renderer widget (element-box node) (inset-box thumb (min 1 inset))
                   (widget-background widget)
                   (or (hovered-p (element-id node))
                       (equal (element-id node) (context-active *context*))))))

(fn (paint-garnet-widget t) ((renderer renderer) (node element))
  (paint-shared-widget renderer node 0 +garnet-shadow-offset+
                       #'paint-garnet-scrollbar #'paint-garnet))

(fn (garnet-geometry geometry) ((widget widget))
  (let ((g (standard-geometry widget)))
    (case (widget-kind widget)
      ((:button :tab)
       ;; Keep six pixels of label padding inside the four-pixel frame band.
       ;; The right edge also reserves the shadow displacement.
       (setf (geometry-left g) 10 (geometry-top g) 4
             (geometry-right g) 14 (geometry-bottom g) 8
             (geometry-offset-x g) +garnet-shadow-offset+
             (geometry-offset-y g) +garnet-shadow-offset+))
      ((:checkbox :radio) (setf (geometry-left g) 12 (geometry-right g) 36))
      (:text-field (setf (geometry-left g) 6 (geometry-right g) 6))
      (otherwise nil))
    g))

(lui:register-toolkit-rendering :garnet :paint #'paint-garnet-widget
                               :geometry #'garnet-geometry :native-labels t)
