(defpackage #:%lui.paint-glass
  (:use #:cl #:%lui.fn #:%lui.layout #:%lui.frame #:%lui.widgets #:lui.draw))
(in-package #:%lui.paint-glass)

(fn (paint-glass-scrollbar t) ((renderer renderer) (node element))
  "Paint a translucent glass scrollbar track and thumb."
  (let* ((widget (element-content node)) (box (element-box node))
         (thumb (scrollbar-thumb node))
         (hover (or (hovered-p (element-id node))
                    (equal (element-id node) (context-active *context*))))
         (foreground (if (widget-disabled-p widget) (widget-color widget
                                                                  :disabled)
                         (widget-foreground widget)))
         (inset (min 2 (/ (min (box-width thumb) (box-height thumb)) 4)))
         (face (inset-box thumb inset)) (radius (/ (box-width face) 2)))
    (shape renderer box (/ (box-width box) 2) foreground 0.08f0)
    (shape renderer face radius foreground (if hover 0.5f0 0.32f0))
    (outline renderer face radius foreground 0.4f0
             (min 1 (/ (box-width face) 2)))))

(%register-standard-painter :glass nil #'paint-glass-scrollbar nil
                           :translucent t)
