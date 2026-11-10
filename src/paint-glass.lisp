(in-package #:lui.draw)

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
