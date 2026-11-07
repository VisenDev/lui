(in-package #:lui.draw)

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
      (let* ((left (ceiling (box-x box))) (top (ceiling (box-y box)))
             (right (floor (+ (box-x box) (box-width box))))
             (bottom (floor (+ (box-y box) (box-height box)))))
        (let ((squares (loop :for y :from top :below bottom
                    :nconc (loop :for x :from (+ left (mod (+ left y) 2))
                                 :below right :by 2
                                 :when (or (null border)
                                           (< x (+ left border))
                                           (>= x (- right border))
                                           (< y (+ top border))
                                           (>= y (- bottom border)))
                                   :collect (typed-vector point (cons x y) (cons (1+ x) y)
                                                  (cons (1+ x) (1+ y))
                                                  (cons x (1+ y)))))))
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
       (let* ((indicator (make-box :x (- (+ (box-x box) (box-width box)) 22)
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
      (:text-field (setf (geometry-left g) 6 (geometry-right g) 6)))
    g))

(lui:register-toolkit-rendering :garnet :paint #'paint-garnet-widget
                               :geometry #'garnet-geometry :native-labels t)
