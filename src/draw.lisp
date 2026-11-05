(defpackage #:lui.draw
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame #:lui.widgets #:lui.font)
  (:export #:renderer #:make-renderer #:renderer-font #:renderer-polygons
    #:renderer-clip #:renderer-glass #:paint-frame #:measure-widget
    #:rounded-polygon #:color-components #:trapezoids #:paint-text))

(in-package #:lui.draw)

(defstruct renderer
  (font nil :type (or null font))
  ;; POLYGONS takes contours, #rrggbb color, and opacity. Native API does rasterization.
  (polygons nil :type (or null function))
  (clip nil :type (or null function))
  ;; Optional backdrop effect: bounds, corner radius, blur radius.
  (glass nil :type (or null function)))

(fn (color-components list) ((color string) &optional ((alpha real) 1))
  (assert (and (= (length color) 7) (char= (char color 0) #\#)))
  (append
    (loop :for start :in '(1 3 5) :collect
      (/ (parse-integer color :start start :end (+ start 2) :radix 16)
        255.0)) (list (max 0 (min 1 alpha)))))

(fn (rounded-polygon list) ((box box) (radius real))
  (let*
    ((x (box-x box)) (y (box-y box)) (w (box-width box))
      (h (box-height box)) (r (max 0 (min radius (/ w 2) (/ h 2)))))
    (loop :for (cx cy base) :in
      (list (list (+ x w (- r)) (+ y r) -90)
        (list (+ x w (- r)) (+ y h (- r)) 0)
        (list (+ x r) (+ y h (- r)) 90) (list (+ x r) (+ y r) 180)) :append
      (loop :for i :from 0 :to 8 :for angle :=
        (* (+ base (* i 11.25)) (/ pi 180)) :collect
        (cons (+ cx (* r (cos angle))) (+ cy (* r (sin angle))))))))

(fn trapezoids ((contours list) (emit function))
  "Convert contours into nonzero-winding trapezoids for native triangle APIs."
  (let ((edges nil) (ys nil))
    (dolist (points contours)
      (loop :for tail :on points :for a := (car tail) :for b :=
        (or (cadr tail) (first points)) :unless (= (cdr a) (cdr b)) :do
        (push (cons a b) edges) :do (push (cdr a) ys)))
    (setf ys (sort (remove-duplicates ys :test #'=) #'<))
    (labels
      ((at-y (edge y)
          (+ (caar edge)
            (* (- y (cdar edge))
              (/ (- (cadr edge) (caar edge))
                (- (cddr edge) (cdar edge)))))))
      (loop :for (top bottom) :on ys :while bottom :for middle :=
        (/ (+ top bottom) 2) :do
        (let
          ((active
              (sort
                (remove-if-not
                  (lambda (edge)
                    (< (min (cdar edge) (cddr edge)) middle
                      (max (cdar edge) (cddr edge)))) edges) #'< :key
                (lambda (edge) (at-y edge middle)))) (winding 0)
            (left nil))
          (dolist (edge active) (when (zerop winding) (setf left edge))
            (incf winding (if (< (cdar edge) (cddr edge)) 1 -1))
            (when (and left (zerop winding))
              (funcall emit
                (list (cons (at-y left top) top)
                  (cons (at-y edge top) top)
                  (cons (at-y edge bottom) bottom)
                  (cons (at-y left bottom) bottom))))))))))

(fn measure-widget ((renderer renderer) (widget widget) width)
  (let*
    ((font (renderer-font renderer)) (kind (widget-kind widget))
      (extra (if (eq kind :label) 0 24)))
    (setf (font-size font) (widget-font-size widget))
    (let
      ((lines
          (wrap-text font
            (if (eq kind :text-field) (widget-value widget)
              (widget-text widget)) (when width (max 0 (- width extra))))))
      (values
        (max (case kind ((:slider :text-field) 160) (otherwise 0))
          (+ extra
            (loop :for line :in lines :maximize (text-width font line))))
        (+ (if (eq kind :label) 0 12)
          (* (length lines) (line-height font)))))))

(fn paint-text
  ((renderer renderer) (text string) (x real) (y real) (color string))
  (let*
    ((font (renderer-font renderer))
      (scale (/ (font-size font) (zpb-ttf:units/em (font-loader font))))
      (cursor x) (previous nil))
    (loop :for char :across text :do
      (when previous
        (incf cursor
          (* scale
            (zpb-ttf:kerning-offset previous char (font-loader font)))))
      (funcall (renderer-polygons renderer)
        (mapcar
          (lambda (points)
            (mapcar
              (lambda (point)
                (cons (+ cursor (* scale (car point)))
                  (- y (* scale (cdr point))))) points))
          (glyph-polygons font char)) color 1)
      (incf cursor
        (* scale
          (zpb-ttf:advance-width
            (zpb-ttf:find-glyph char (font-loader font)))))
      (setf previous char))))

(fn paint-widget ((renderer renderer) (node element))
  (let*
    ((widget (element-content node)) (box (element-box node))
      (kind (widget-kind widget)) (glass (eq (widget-style widget) :glass))
      (radius (if glass (widget-radius widget) 0))
      (font (renderer-font renderer)) (inset (if (eq kind :label) 0 12))
      (x (+ (box-x box) inset))
      (y (+ (box-y box) (if (eq kind :label) 0 6))))
    (setf (font-size font) (widget-font-size widget))
    (funcall (renderer-clip renderer) (element-clip node))
    (when (widget-painter widget)
      (funcall (widget-painter widget) renderer node)
      (return-from paint-widget nil))
    (flet
      ((shape (bounds r color alpha)
          (funcall (renderer-polygons renderer)
            (list (rounded-polygon bounds r)) color alpha)))
      (unless (eq kind :label)
        (when (and glass (renderer-glass renderer))
          (funcall (renderer-glass renderer) box radius
            (widget-frost widget)))
        (shape box radius (widget-background widget)
          (if glass (widget-opacity widget) 1))
        ;; A narrow native outline keeps each collection's edge treatment distinct.
        (let
          ((inner
              (make-box :x (+ (box-x box) 1) :y (+ (box-y box) 1)
                :width (max 0 (- (box-width box) 2)) :height
                (max 0 (- (box-height box) 2)))))
          (funcall (renderer-polygons renderer)
            (list (rounded-polygon box radius)
              (reverse (rounded-polygon inner (max 0 (1- radius)))))
            "#ffffff" (if glass 0.4 0.75))))
      (case kind
        (:slider
          (let*
            ((fraction
                (/ (- (widget-value widget) (widget-minimum widget))
                  (- (widget-maximum widget) (widget-minimum widget))))
              (track
                (make-box :x (+ (box-x box) 8) :y
                  (+ (box-y box) (/ (box-height box) 2) -2) :width
                  (max 0 (- (box-width box) 16)) :height 4)))
            (shape track 2 "#777777" 1)
            (setf (box-width track) (* fraction (box-width track)))
            (shape track 2 (widget-accent widget) 1)
            (shape
              (make-box :x (+ (box-x track) (box-width track) -7) :y
                (- (box-y track) 5) :width 14 :height 14)
              (if glass 7 0) "#ffffff" 1)))
        (:checkbox
          (shape (make-box :x x :y y :width 16 :height 16)
            (if glass 4 0)
            (if (widget-value widget) (widget-accent widget) "#777777")
            1)
          (when (widget-value widget)
            (paint-text renderer "x" (+ x 3) (+ y 13) "#ffffff"))
          (paint-text renderer (widget-text widget) (+ x 24)
            (+ y (baseline font)) (widget-foreground widget)))
        (otherwise
          (loop :for line :in
            (wrap-text font
              (if (eq kind :text-field) (widget-value widget)
                (widget-text widget))
              (max 0 (- (box-width box) (* 2 inset)))) :for baseline
            :from (+ y (baseline font)) :by (line-height font) :do
            (paint-text renderer line x baseline
              (widget-foreground widget))))))))

(fn paint-frame ((renderer renderer) (context context))
  (visible-elements (context-root context)
    (lambda (node)
      (when (widget-p (element-content node)) (paint-widget renderer node)))))
