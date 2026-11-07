(in-package #:lui.draw)

(fn (macos-bevel t) ((renderer renderer) (widget widget) (box box)
                    &optional recessed disabled)
  (declare (ignore recessed))
  (outline renderer box (min 6 (widget-radius widget))
           (widget-color widget (if disabled :disabled-surface :border)) 0.65 1))

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
  (let* ((widget (element-content node)) (thumb (scrollbar-thumb node)))
    (shape renderer (element-box node) 0 (widget-color widget :track) 1)
    (shape renderer thumb 0 (widget-background widget) 1)
    (funcall bevel renderer widget thumb nil (widget-disabled-p widget))))

(fn (paint-macos-scrollbar t) ((renderer renderer) (node element))
  (shape renderer (inset-box (scrollbar-thumb node) 2) 4
         (widget-color (element-content node) :track) 0.8))

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
