(in-package #:lui.draw)

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
    (shape renderer (element-box node) 0 foreground 0.15)
    (shape renderer (scrollbar-thumb node) 0 (widget-accent widget) 1)))

(fn (paint-motif-body t) ((renderer renderer) (node element))
  (paint-standard-body renderer node nil #'motif-bevel))

(fn (paint-motif-widget t) ((renderer renderer) (node element))
  (paint-shared-widget renderer node 0 0 #'paint-motif-scrollbar #'paint-motif-body))

(lui:register-toolkit-rendering :motif :paint #'paint-motif-widget
                               :geometry #'standard-geometry :native-labels t)
