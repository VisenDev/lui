(in-package #:lui.draw)

(fn motif-bevel ((renderer renderer) (box box)
                 &optional recessed disabled)
  (let* ((light (if disabled "#d0d0d0" "#ffffff"))
         (dark (if disabled "#989898" "#505050"))
         (x (box-x box))
         (y (box-y box))
         (right (+ x (box-width box)))
         (bottom (+ y (box-height box)))
         (edge (min 2 (/ (box-width box) 2) (/ (box-height box) 2))))
    (funcall (renderer-polygons renderer)
             (list (list (cons x y) (cons right y)
                         (cons (- right edge) (+ y edge))
                         (cons (+ x edge) (+ y edge))
                         (cons (+ x edge) (- bottom edge))
                         (cons x bottom)))
             (if recessed dark light) 1)
    (funcall (renderer-polygons renderer)
             (list (list (cons x bottom) (cons right bottom)
                         (cons right y) (cons (- right edge) (+ y edge))
                         (cons (- right edge) (- bottom edge))
                         (cons (+ x edge) (- bottom edge))))
             (if recessed light dark) 1)))

(fn paint-motif-scrollbar ((renderer renderer) (node element))
  (let* ((widget (element-content node))
         (foreground (if (widget-disabled-p widget) "#777777"
                         (widget-foreground widget))))
    (shape renderer (element-box node) 0 foreground 0.15)
    (shape renderer (scrollbar-thumb node) 0 (widget-accent widget) 1)))

(fn paint-motif-body ((renderer renderer) (node element))
  (paint-standard-body renderer node nil #'motif-bevel))

(fn paint-motif-widget ((renderer renderer) (node element))
  (paint-shared-widget renderer node 0 0 #'paint-motif-scrollbar #'paint-motif-body))

(lui:register-toolkit-rendering :motif :paint #'paint-motif-widget
                               :measure #'standard-measure :native-labels t
                               :text-insets #'standard-text-insets)
