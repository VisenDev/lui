(defpackage #:%lui.paint-qt
  (:use #:cl #:%lui.fn #:%lui.layout #:%lui.frame #:%lui.widgets #:lui.draw))
(in-package #:%lui.paint-qt)

(fn (qt-bevel t) ((renderer renderer) (widget widget) (box box)
                  &optional ((recessed boolean) nil) ((disabled boolean) nil))
  "Paint a Qt-style raised or recessed surface."
  (let ((light (widget-color widget (if disabled :disabled-bevel-light
                                        :bevel-light)))
        (dark (widget-color widget (if disabled :disabled-bevel-dark
                                       :bevel-dark)))
        (x (box-x box)) (y (box-y box))
        (width (box-width box)) (height (box-height box)))
    (outline renderer box 2 (widget-color widget :border) 1 1)
    (when (> (min width height) 4)
      (shape renderer (make-box :x (+ x 2) :y (+ y 1) :width (- width 4)
                                :height 1)
             0 (if recessed dark light) 1)
      (shape renderer (make-box :x (+ x 2) :y (+ y height -2) :width
                        (- width
                          4) :height 1)
             0 (if recessed light dark) 1))))

(fn (paint-qt-scrollbar t) ((renderer renderer) (node element))
  "Paint the Qt scrollbar track and thumb."
  (%paint-desktop-scrollbar renderer node #'qt-bevel))

(%register-standard-painter :qt 2 #'paint-qt-scrollbar #'qt-bevel)
