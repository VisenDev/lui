(defpackage #:lui.paint-motif
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame #:lui.widgets #:lui.draw))
(in-package #:lui.paint-motif)

(fn (motif-bevel t)
    ((renderer renderer) (widget widget) (box box) &optional
     ((recessed boolean) nil) ((disabled boolean) nil))
  "Paint a raised or recessed Motif bevel around a surface."
  (let* ((light (if disabled (widget-color widget :disabled-bevel-light)
                    (widget-color widget :bevel-light)))
         (dark (if disabled (widget-color widget :disabled-bevel-dark)
                   (widget-color widget :bevel-dark)))
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
                         (typed-vector point (cons x bottom) (cons right
                                                                   bottom)
                                       (cons right y) (cons (- right edge)
                                                            (+
                                                             y edge))
                                       (cons (- right edge) (- bottom edge))
                                       (cons (+ x edge) (- bottom edge))))
             (if recessed light dark) 1)))

(fn (paint-motif-scrollbar t) ((renderer renderer) (node element))
  "Paint a Motif scrollbar track and beveled thumb."
  (let* ((widget (element-content node))
         (foreground (if (widget-disabled-p widget) (widget-color widget
                                                                  :disabled)
                         (widget-foreground widget))))
    (shape renderer (element-box node) 0 foreground 0.15f0)
    (shape renderer (scrollbar-thumb node) 0 (widget-accent widget) 1)))

(register-standard-painter :motif 0 #'paint-motif-scrollbar #'motif-bevel)
