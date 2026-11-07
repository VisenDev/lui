(in-package #:lui.draw)

(fn (standard-measure (values number number)) ((renderer renderer) (widget widget) width)
  "Return intrinsic width and wrapped height using this renderer’s font metrics."
  (when (eq (widget-kind widget) :panel)
    (return-from standard-measure (values 0 0)))
  (let* ((font (widget-font renderer widget))
         (kind (widget-kind widget))
         (extra (case kind (:label 0) (:cell 8) (:list-item 12)
                       ((:checkbox :radio) 48)
                       (otherwise 24))))
    (let ((lines (wrap-text font
                            (if (eq kind :text-field)
                                (widget-value widget)
                                (widget-text widget))
                            (when width (max 0 (- width extra))))))
      (let ((widest 0) (count 0))
        (dolist (line lines)
          (setf widest (max widest (text-width font line)))
          (incf count))
        (values (max (case kind ((:slider :text-field) 160) (otherwise 0))
                     (+ extra widest))
                (+ (if (eq kind :label) 0 12)
                   (* count (line-height font))))))))

(defun standard-text-insets (widget &optional (field-inset 12))
  (if (eq (widget-kind widget) :label) (values 0 0) (values field-inset 6)))

(defun paint-calendar-icon (renderer box color)
  (let ((x (+ (box-x box) (/ (- (box-width box) 14) 2)))
        (y (+ (box-y box) (/ (- (box-height box) 14) 2))))
    (flet ((bar (dx dy w h)
             (shape renderer (make-box :x (+ x dx) :y (+ y dy) :width w :height h)
                    0 color 1)))
      (outline renderer (make-box :x x :y (+ y 2) :width 14 :height 12) 1 color 1 1.5)
      (bar 1 5 12 1.5) (bar 3 0 2 4) (bar 9 0 2 4))))

(fn paint-text-field
    ((renderer renderer) (node element) (x real) (y real) (width real))
  (let* ((widget (element-content node))
         (font (renderer-font renderer))
         (text (widget-value widget))
         (state (when (focused-p node)
                  (gethash (element-id node) (context-state *context*))))
         (cursor (when (typep state 'edit-state)
                   (max 0 (min (length text) (edit-state-cursor state)))))
         (anchor (when cursor
                   (max 0 (min (length text) (edit-state-anchor state)))))
         (start 0))
    (when (zerop (length text))
      (paint-text renderer (widget-text widget) x (+ y (baseline font))
                  (lui.widgets::muted-ink (widget-foreground widget) (widget-background widget))))
    (loop :for line :in (wrap-text font text width)
          :for top :from y :by (line-height font)
          :for end := (+ start (length line))
          :do (when (and cursor (/= cursor anchor))
                (let ((left (max start (min cursor anchor)))
                      (right (min end (max cursor anchor))))
                  (when (< left right)
                    (shape renderer
                           (make-box
                            :x (+ x (text-width
                                     font (subseq text start left)))
                            :y top
                            :width (- (text-width
                                       font (subseq text start right))
                                      (text-width
                                       font (subseq text start left)))
                            :height (line-height font))
                           0 (widget-accent widget) 0.35f0))))
              (paint-text renderer line x (+ top (baseline font))
                          (if (widget-disabled-p widget) "#777777"
                              (widget-foreground widget)))
              (when (and cursor (<= start cursor end))
                (shape renderer
                       (make-box :x (+ x (text-width
                                         font (subseq text start cursor)))
                                 :y top :width 1 :height (line-height font))
                       0 (widget-foreground widget) 1))
              ;; Wrapping and explicit newlines each consume one separator.
              (setf start (min (length text) (1+ end))))))

(fn paint-canvas ((renderer renderer) (node element))
  (let* ((widget (element-content node)) (box (element-box node)))
    (shape renderer box 0 (widget-background widget) 1)
    (dolist (command (widget-value widget))
      (destructuring-bind (kind cx cy radius stroke fill) command
        (assert (eq kind :circle))
        (let ((circle (make-box :x (+ (box-x box) cx (- radius))
                                :y (+ (box-y box) cy (- radius))
                                :width (* 2 radius) :height (* 2 radius))))
          (when fill (shape renderer circle radius fill 1))
          (when stroke (outline renderer circle radius stroke 1 1)))))))

(fn paint-cell ((renderer renderer) (node element))
  "Paint a spreadsheet cell with the renderer’s selected widget font."
  (let* ((widget (element-content node))
         (box (element-box node))
         (selected (widget-value widget))
         (text (widget-text widget)))
    (shape renderer box 0 (if selected "#e7effa" (widget-background widget)) 1)
    (outline renderer box 0 (if selected (widget-accent widget) "#939ba5")
             1 (if selected 2 1))
    (when (plusp (length text))
      (paint-text renderer text (+ (box-x box) 4)
                  (+ (box-y box) 6 (baseline (renderer-font renderer)))
                  (widget-foreground widget)))))

(fn paint-focus-ring ((renderer renderer) (node element) (radius real))
  (when (and (focused-p node) (context-focus-visible-p *context*))
    (let* ((widget (element-content node))
           (box (element-box node)))
      (outline renderer (inset-box box 2) (max 0 (- radius 2))
               (widget-accent widget) 1 2))))

(fn paint-shared-widget ((renderer renderer) (node element) (radius real) (shadow real)
     (scrollbar function) (body function))
  (let* ((widget (element-content node))
         (box (element-box node))
         (kind (widget-kind widget))
         (disabled (widget-disabled-p widget))
         (pressed (and (not disabled) (hovered-p (element-id node))
                       (equal (element-id node)
                              (context-active *context*))))
         (foreground (if disabled "#777777" (widget-foreground widget)))
         (font (renderer-font renderer)))
    (cond
      ((eq kind :cell) (paint-cell renderer node))
      ((eq kind :scrollbar) (funcall scrollbar renderer node))
      ((eq kind :splitter)
       (shape renderer
              (if (eq (widget-orientation widget) :horizontal)
                  (make-box :x (box-x box) :width (box-width box)
                            :y (+ (box-y box) (/ (box-height box) 2) -1)
                            :height 2)
                  (make-box :x (+ (box-x box) (/ (box-width box) 2) -1)
                            :y (box-y box) :width 2 :height (box-height box)))
              0 (widget-accent widget)
              (if (or pressed (hovered-p (element-id node))) 1 0.5)))
      ((eq kind :highlight)
       (shape renderer box 0 (widget-accent widget)
              (widget-opacity widget))
       (outline renderer box 0 (widget-accent widget) 1 1))
      ((eq (lui.widgets::widget-icon widget) :calendar)
       ;; The field owns the surface and its rounded border.
       (let* ((width (max 0 (- (box-width box) shadow)))
              (height (max 0 (- (box-height box) shadow)))
              (size (min 20 width height))
              (mark (make-box :x (+ (box-x box) (/ (- width size) 2))
                              :y (+ (box-y box) (/ (- height size) 2))
                              :width size :height size)))
         (when (hovered-p (element-id node))
           (shape renderer mark (/ size 2) foreground 0.12))
         (when (and (focused-p node) (context-focus-visible-p *context*))
           (outline renderer mark (/ size 2) foreground 1 1))
         (paint-calendar-icon renderer mark foreground)))
      ((eq kind :list-item)
       (shape renderer box 0
              (if (widget-value widget) (widget-accent widget)
                  (widget-background widget)) 1)
       (when (and (not (widget-value widget))
                  (hovered-p (element-id node)))
         (shape renderer box 0 foreground 0.12))
       (when (and (lui.widgets::widget-center-text-p widget) (focused-p node)
                  (context-focus-visible-p *context*))
         (outline renderer box 1 (if (widget-value widget) "#ffffff" foreground) 1 1))
       (loop :for line :in (wrap-text font (widget-text widget)
                                  (max 0 (- (box-width box) 12)))
             :for top :from (+ (box-y box) 6 (baseline font)) :by (line-height font)
             :for left := (if (lui.widgets::widget-center-text-p widget)
                              (/ (- (box-width box) (text-width font line)) 2) 6)
             :do (paint-text renderer line (+ (box-x box) left) top
                             (if (widget-value widget) "#ffffff" foreground))))
      ((eq kind :gauge)
       (shape renderer box radius (widget-background widget) 1)
       (let ((fill (make-box :x (box-x box) :y (box-y box)
                             :width (* (box-width box) (widget-value widget))
                             :height (box-height box))))
         (shape renderer fill radius (widget-accent widget) 1))
       (outline renderer box radius foreground 1 1))
      ((eq kind :canvas) (paint-canvas renderer node))
      (t (funcall body renderer node)))
    (paint-focus-ring renderer node radius)))

(fn paint-standard-body ((renderer renderer) (node element) translucent bevel)
  (let* ((widget (element-content node))
         (box (element-box node))
         (kind (widget-kind widget))
         (disabled (widget-disabled-p widget))
         (pressed (and (not disabled) (hovered-p (element-id node))
                       (equal (element-id node)
                              (context-active *context*))))
         (foreground (if disabled "#777777" (widget-foreground widget)))
         (radius (if translucent (widget-radius widget) 0))
         (font (renderer-font renderer))
         (inset (if (eq kind :label) 0 12))
         (x (+ (box-x box) inset))
         (y (+ (box-y box) (if (eq kind :label) 0 6))))
    (unless (eq kind :label)
      (when (and translucent (< (widget-opacity widget) 1)
                 (renderer-glass renderer))
        (funcall (renderer-glass renderer)
                 box radius (widget-frost widget)))
      (shape renderer box radius (widget-background widget)
             (if translucent (widget-opacity widget) 1))
      (if translucent
          (outline renderer box radius "#ffffff"
                   (if disabled 0.15f0 0.4f0) 1)
          (unless (member kind '(:checkbox :radio))
            (funcall bevel renderer box
                        (or (eq kind :text-field)
                            (and pressed (member kind '(:button :tab))))
                        disabled))))
    (when (and (member kind '(:button :tab :checkbox :radio))
               (not (widget-disabled-p widget)))
      (cond
        ((and (hovered-p (element-id node))
              (equal (element-id node) (context-active *context*)))
         (shape renderer box radius "#000000" 0.2f0))
        ((hovered-p (element-id node))
         (shape renderer box radius "#ffffff" 0.14f0)))
      (when (and (eq kind :tab) (widget-value widget))
        (shape renderer
               (make-box :x (+ (box-x box) 3)
                         :y (+ (box-y box) (box-height box) -3)
                         :width (max 0 (- (box-width box) 6)) :height 3)
               0 (widget-accent widget) 1)))
    (case kind
      (:panel nil)
      (:slider
       (let* ((fraction (/ (- (widget-value widget)
                             (widget-minimum widget))
                          (- (widget-maximum widget)
                             (widget-minimum widget))))
              (track (make-box
                      :x (+ (box-x box) 8)
                      :y (+ (box-y box) (/ (box-height box) 2) -2)
                      :width (max 0 (- (box-width box) 16)) :height 4)))
         (shape renderer track 2 "#777777" 1)
         (setf (box-width track) (* fraction (box-width track)))
         (shape renderer track 2
                (if disabled "#999999" (widget-accent widget)) 1)
         (shape renderer
                (make-box :x (+ (box-x track) (box-width track) -7)
                          :y (- (box-y track) 5) :width 14 :height 14)
                (if translucent 7 0) (if disabled "#a0a0a0" "#ffffff") 1)))
      (:checkbox
       (let ((indicator (make-box :x x :y y :width 16 :height 16)))
         (shape renderer indicator (if translucent 4 0)
                (if translucent
                    (if (widget-value widget)
                        (widget-accent widget) "#777777")
                    (widget-background widget))
                1)
         (unless translucent
           (funcall bevel renderer indicator
                        (or pressed (widget-value widget)) disabled))
         (when (widget-value widget)
           (funcall
            (renderer-polygons renderer)
            (list (mapcar (lambda (point)
                            (cons (+ x (car point)) (+ y (cdr point))))
                          '((3 . 7) (6 . 10) (12 . 3) (14 . 5)
                            (6 . 13) (2 . 9))))
            (if translucent "#ffffff" foreground) 1)))
       (loop :for line :in (wrap-text
                           font (widget-text widget)
                           (max 0 (- (box-width box) 48)))
             :for baseline :from (+ y (baseline font))
               :by (line-height font)
             :do (paint-text renderer line (+ x 24) baseline
                             foreground)))
      (:radio
       (let ((indicator (make-box :x x :y (+ y 1)
                                  :width 16 :height 16)))
         (shape renderer indicator 8
                (if translucent "#ffffff" (widget-background widget)) 1)
         (outline renderer indicator 8
                  (if disabled "#777777" foreground) 1 1)
         (when (widget-value widget)
           (shape renderer (inset-box indicator 5) 3
                  (if disabled "#777777"
                      (if translucent (widget-accent widget) foreground)) 1))
         (loop :for line :in (wrap-text
                             font (widget-text widget)
                             (max 0 (- (box-width box) 48)))
               :for baseline :from (+ y (baseline font))
                 :by (line-height font)
               :do (paint-text renderer line (+ x 24) baseline
                               foreground))))
      (:text-field
       (paint-text-field renderer node x y
                         (max 0 (- (box-width box) (* 2 inset)))))
      (otherwise
       (let* ((lines (wrap-text
                      font (widget-text widget)
                      (max 0 (- (box-width box) (* 2 inset)))))
              (center (member kind '(:button :tab)))
              (top (if center
                       (+ (box-y box)
                          (max 0 (/ (- (box-height box)
                                       (* (length lines)
                                          (line-height font)))
                                    2)))
                       y)))
         (loop :for line :in lines
               :for baseline :from (+ top (baseline font))
                 :by (line-height font)
               :do (paint-text
                    renderer line
                    (if center
                        (+ (box-x box)
                           (max 0 (/ (- (box-width box)
                                        (text-width font line)) 2)))
                        x)
                    baseline foreground)))))
))
