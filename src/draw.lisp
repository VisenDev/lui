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
    `(let ((,result (make-array ,(length elements) :element-type ',type)))
       ,@(loop for element in elements for i from 0
               collect `(setf (aref ,result ,i) ,element))
       ,result)))

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
                 (if (geometry-value-p g) (widget-value widget)
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
        #+jscl (error "The browser renderer requires a text drawing callback.")
        #-jscl
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
