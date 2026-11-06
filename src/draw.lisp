(defpackage #:lui.draw
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame #:lui.widgets #:lui.font)
  (:export #:renderer #:make-renderer #:renderer-font #:renderer-polygons
           #:renderer-clip #:renderer-glass #:renderer-text
           #:paint-frame #:measure-widget
           #:rounded-polygon #:color-components #:trapezoids #:paint-text))

(in-package #:lui.draw)

(defstruct renderer
  "Native drawing callbacks and font shared by the graphical backends."
  (font nil :type (or null font))
  ;; POLYGONS takes contours, #rrggbb color, and opacity. Native API does rasterization.
  (polygons nil :type (or null function))
  (clip nil :type (or null function))
  ;; Optional backdrop effect: bounds, corner radius, blur radius.
  (glass nil :type (or null function))
  ;; Optional native glyph cache: font, text, baseline x/y, and color.
  (text nil :type (or null function))
  (patterns (make-hash-table :test 'equal) :type hash-table))

(fn (color-components list) ((color string) &optional ((alpha real) 1))
  "Convert #RRGGBB and ALPHA to a list of normalized red, green, blue, and alpha values."
  (assert (and (= (length color) 7) (char= (char color 0) #\#)))
  (append (loop :for start :in '(1 3 5)
                :collect (/ (parse-integer color :start start
                                                 :end (+ start 2)
                                                 :radix 16)
                            255.0f0))
          (list (max 0 (min 1 alpha)))))

(fn (rounded-polygon list) ((box box) (radius real))
  "Return contour points for BOX with corners rounded by RADIUS."
  (let* ((x (box-x box))
         (y (box-y box))
         (w (box-width box))
         (h (box-height box))
         (r (max 0 (min radius (/ w 2) (/ h 2)))))
    (when (zerop r)
      (return-from rounded-polygon
        (list (cons (+ x w) y) (cons (+ x w) (+ y h))
              (cons x (+ y h)) (cons x y))))
    (loop :for (cx cy base)
            :in (list (list (+ x w (- r)) (+ y r) -90)
                      (list (+ x w (- r)) (+ y h (- r)) 0)
                      (list (+ x r) (+ y h (- r)) 90)
                      (list (+ x r) (+ y r) 180))
          :append (loop :for i :from 0 :to 8
                        :for angle := (* (+ base (* i 11.25f0)) (/ pi 180))
                        :collect (cons (+ cx (* r (cos angle)))
                                       (+ cy (* r (sin angle))))))))

(fn trapezoids ((contours list) (emit function))
  "Convert contours into nonzero-winding trapezoids for native triangle APIs."
  (let ((edges nil)
        (ys nil))
    (dolist (points contours)
      (loop :for tail :on points
            :for a := (car tail)
            :for b := (or (cadr tail) (first points))
            :unless (= (cdr a) (cdr b))
              :do (push (cons a b) edges)
                  (push (cdr a) ys)))
    (setf ys (sort (remove-duplicates ys :test #'=) #'<))
    (labels ((at-y (edge y)
               (+ (caar edge)
                  (* (- y (cdar edge))
                     (/ (- (cadr edge) (caar edge))
                        (- (cddr edge) (cdar edge)))))))
      (loop :for (top bottom) :on ys
            :for middle := (when bottom (/ (+ top bottom) 2))
            :while bottom
            :do (let ((active
                        (sort
                         ;; Each slab must retain the full original EDGES list.
                         (loop :for edge :in edges
                               :when (< (min (cdar edge) (cddr edge))
                                        middle
                                        (max (cdar edge) (cddr edge)))
                                 :collect edge)
                         #'< :key (lambda (edge) (at-y edge middle))))
                      (winding 0)
                      (left nil))
                  (dolist (edge active)
                    (when (zerop winding) (setf left edge))
                    (incf winding (if (< (cdar edge) (cddr edge)) 1 -1))
                    (when (and left (zerop winding))
                      (funcall emit
                               (list (cons (at-y left top) top)
                                     (cons (at-y edge top) top)
                                     (cons (at-y edge bottom) bottom)
                                     (cons (at-y left bottom) bottom))))))))))

(fn widget-font ((renderer renderer) (widget widget))
  (let ((font (font-face (renderer-font renderer)
                         (widget-font-family widget)
                         (widget-font-weight widget))))
    (setf (font-size font) (widget-font-size widget))
    font))

(fn measure-widget ((renderer renderer) (widget widget) width)
  "Return intrinsic width and wrapped height using this renderer’s font metrics."
  (when (eq (widget-kind widget) :panel)
    (return-from measure-widget (values 0 0)))
  (let* ((font (widget-font renderer widget))
         (kind (widget-kind widget))
         (extra (case kind (:label 0) (:cell 8) (:checkbox 48)
                       (otherwise 24))))
    (let ((lines (wrap-text font
                            (if (eq kind :text-field)
                                (widget-value widget)
                                (widget-text widget))
                            (when width (max 0 (- width extra))))))
      (values
       (max (case kind ((:slider :text-field) 160) (otherwise 0))
            (+ extra
               (loop :for line :in lines
                     :maximize (text-width font line))))
       (+ (if (eq kind :label) 0 12)
          (* (length lines) (line-height font)))))))

(fn paint-text
    ((renderer renderer) (text string) (x real) (y real) (color string))
  "Draw TEXT at horizontal position X and baseline Y in COLOR."
  (when (zerop (length text)) (return-from paint-text nil))
  (when (renderer-text renderer)
    (return-from paint-text
      (funcall (renderer-text renderer) (renderer-font renderer)
               text x y color)))
  (let* ((font (renderer-font renderer))
         (scale (/ (font-size font) (zpb-ttf:units/em (font-loader font))))
         (cursor x)
         (previous nil))
    (loop :for char :across text
          :do (when previous
                (incf cursor
                      (* scale (zpb-ttf:kerning-offset
                                previous char (font-loader font)))))
              (funcall
               (renderer-polygons renderer)
               (mapcar
                (lambda (points)
                  (mapcar (lambda (point)
                            (cons (+ cursor (* scale (car point)))
                                  (- y (* scale (cdr point)))))
                          points))
                (glyph-polygons font char))
               color 1)
              (incf cursor
                    (* scale (zpb-ttf:advance-width
                              (zpb-ttf:find-glyph char (font-loader font)))))
              (setf previous char))))

(fn inset-box ((box box) (inset real))
  (make-box :x (+ (box-x box) inset) :y (+ (box-y box) inset)
            :width (max 0 (- (box-width box) (* 2 inset)))
            :height (max 0 (- (box-height box) (* 2 inset)))))

(fn shape
    ((renderer renderer) (box box) (radius real) (color string) (alpha real))
  (funcall (renderer-polygons renderer)
           (list (rounded-polygon box radius)) color alpha))

(fn outline
    ((renderer renderer) (box box) (radius real) (color string)
     (alpha real) (thickness real))
  (funcall (renderer-polygons renderer)
           (list (rounded-polygon box radius)
                 (reverse (rounded-polygon (inset-box box thickness)
                                           (max 0 (- radius thickness)))))
           color alpha))

(fn motif-bevel ((renderer renderer) (box box)
                 &optional pressed disabled)
  (let* ((x (box-x box))
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
             (cond (disabled "#d0d0d0") (pressed "#505050")
                   (t "#ffffff")) 1)
    (funcall (renderer-polygons renderer)
             (list (list (cons x bottom) (cons right bottom)
                         (cons right y) (cons (- right edge) (+ y edge))
                         (cons (- right edge) (- bottom edge))
                         (cons (+ x edge) (- bottom edge))))
             (cond (disabled "#989898") (pressed "#ffffff")
                   (t "#505050")) 1)))

(fn (focused-p boolean) ((node element))
  (and (element-interactive-p node)
       (boundp '*context*)
       (equal (element-id node) (context-focus *context*))
       (not (widget-disabled-p (element-content node)))))

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

(fn rectangle-path ((box box))
  (let ((x (box-x box)) (y (box-y box))
        (right (+ (box-x box) (box-width box)))
        (bottom (+ (box-y box) (box-height box))))
    (list (cons x y) (cons right y) (cons right bottom) (cons x bottom))))

(fn garnet-fill ((renderer renderer) (box box) (color string))
  (when (and (plusp (box-width box)) (plusp (box-height box)))
    (funcall (renderer-polygons renderer)
             (list (rectangle-path box)) color 1)))

(fn garnet-outline ((renderer renderer) (box box)
                   &optional ((thickness real) 1))
  (when (and (plusp (box-width box)) (plusp (box-height box)))
    (let ((inner (inset-box box thickness)))
      (funcall (renderer-polygons renderer)
               (if (and (plusp (box-width inner)) (plusp (box-height inner)))
                   (list (rectangle-path box)
                         (reverse (rectangle-path inner)))
                   (list (rectangle-path box)))
               "#000000" 1))))

(fn garnet-stipple ((renderer renderer) (box box) &optional border)
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
        (setf paths
              (loop :for y :from top :below bottom
                    :nconc (loop :for x :from (+ left (mod (+ left y) 2))
                                 :below right :by 2
                                 :when (or (null border)
                                           (< x (+ left border))
                                           (>= x (- right border))
                                           (< y (+ top border))
                                           (>= y (- bottom border)))
                                   :collect (list (cons x y) (cons (1+ x) y)
                                                  (cons (1+ x) (1+ y))
                                                  (cons x (1+ y)))))
              (gethash key cache) paths)))
    (when paths
      (funcall (renderer-polygons renderer) paths "#000000" 1))))

(fn garnet-face ((renderer renderer) (box box) (background string)
                &optional pressed ((band integer) 3))
  (let* ((shadow (make-box :x (+ (box-x box) 4) :y (+ (box-y box) 4)
                           :width (max 0 (- (box-width box) 4))
                           :height (max 0 (- (box-height box) 4))))
         (face (make-box :x (+ (box-x box) (if pressed 4 0))
                         :y (+ (box-y box) (if pressed 4 0))
                         :width (box-width shadow)
                         :height (box-height shadow))))
    (garnet-fill renderer shadow "#000000")
    (garnet-fill renderer face (if (plusp band) "#ffffff" background))
    (when (plusp band)
      (garnet-stipple renderer (inset-box face 1) band)
      (garnet-fill renderer (inset-box face (1+ band)) background)
      (garnet-outline renderer (inset-box face (1+ band))))
    (garnet-outline renderer face)
    face))

(fn garnet-text ((renderer renderer) (text string) (box box) (color string)
                &optional center)
  (let* ((font (renderer-font renderer))
         (lines (wrap-text font text (box-width box)))
         (top (+ (box-y box)
                 (if center
                     (max 0 (/ (- (box-height box)
                                  (* (length lines) (line-height font))) 2))
                     0))))
    (loop :for line :in lines
          :for y :from (+ top (baseline font)) :by (line-height font)
          :do (paint-text renderer line
                          (+ (box-x box)
                             (if center
                                 (max 0 (/ (- (box-width box)
                                              (text-width font line)) 2))
                                 0))
                          y color))))

(fn paint-garnet ((renderer renderer) (node element))
  (let* ((widget (element-content node))
         (box (element-box node))
         (kind (widget-kind widget))
         (disabled (widget-disabled-p widget))
         (hover (and (not disabled) (hovered-p (element-id node))))
         (pressed (and hover (equal (element-id node)
                                   (context-active *context*))))
         (ink (if disabled "#777777" (widget-foreground widget))))
    (case kind
      (:label (garnet-text renderer (widget-text widget) box ink))
      (:panel
       (if (and (= 0 (box-x box) (box-y box))
                (= (box-width box) (context-width *context*))
                (= (box-height box) (context-height *context*)))
           (garnet-fill renderer box (widget-background widget))
           (garnet-face renderer box (widget-background widget) nil 0)))
      ((:button :tab)
       (let* ((face (garnet-face renderer box
                                 (widget-background widget) pressed))
              (field (inset-box face 4))
              (selected (and (eq kind :tab) (widget-value widget))))
         (when selected (garnet-fill renderer field "#000000"))
         (when hover (garnet-outline renderer field 2))
         (garnet-text renderer (widget-text widget) field
                      (if selected "#ffffff" ink) t)))
      (:checkbox
       (let* ((square (make-box :x (- (+ (box-x box) (box-width box)) 24)
                               :y (+ (box-y box)
                                     (max 0 (/ (- (box-height box) 24) 2)))
                               :width 24 :height 24))
              (face (garnet-face renderer square "#ffffff" pressed)))
         (when hover (garnet-outline renderer (inset-box face 4) 2))
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
               (funcall (renderer-polygons renderer) (list stroke) ink 1))))
         (garnet-text renderer (widget-text widget)
                      (make-box :x (+ (box-x box) 12) :y (+ (box-y box) 6)
                                :width (max 0 (- (box-width box) 48))
                                :height (max 0 (- (box-height box) 12)))
                      ink)))
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
         (garnet-fill renderer track "#ffffff")
         (garnet-stipple renderer (inset-box track 1))
         (garnet-outline renderer track)
         (garnet-fill renderer thumb (widget-background widget))
         (garnet-outline renderer thumb (if hover 2 1))))
      (:text-field
       (garnet-fill renderer box (widget-background widget))
       (garnet-outline renderer box)
       (paint-text-field renderer node (+ (box-x box) 6) (+ (box-y box) 6)
                         (max 0 (- (box-width box) 12))))
      (otherwise nil))))

(fn paint-widget ((renderer renderer) (node element))
  (let ((font (renderer-font renderer)))
    (unwind-protect
         (progn
           (setf (renderer-font renderer)
                 (widget-font renderer (element-content node)))
           (paint-widget-body renderer node))
      (setf (renderer-font renderer) font))))

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

(fn paint-widget-body ((renderer renderer) (node element))
  (let* ((widget (element-content node))
         (box (element-box node))
         (kind (widget-kind widget))
         (glass (eq (toolkit-surface (widget-style widget)) :glass))
         (disabled (widget-disabled-p widget))
         (pressed (and (not disabled) (hovered-p (element-id node))
                       (equal (element-id node)
                              (context-active *context*))))
         (foreground (if disabled "#777777" (widget-foreground widget)))
         (radius (if glass (widget-radius widget) 0))
         (font (renderer-font renderer))
         (inset (if (eq kind :label) 0 12))
         (x (+ (box-x box) inset))
         (y (+ (box-y box) (if (eq kind :label) 0 6))))
    (funcall (renderer-clip renderer) (element-clip node))
    (cond
      ((widget-painter widget)
       (funcall (widget-painter widget) renderer node))
      ((eq kind :splitter)
       (shape renderer
              (make-box :x (+ (box-x box) (/ (box-width box) 2) -1)
                        :y (box-y box) :width 2 :height (box-height box))
              0 (widget-accent widget)
              (if (or pressed (hovered-p (element-id node))) 1 0.5)))
      ((eq kind :highlight)
       (shape renderer box 0 (widget-accent widget)
              (widget-opacity widget))
       (outline renderer box 0 (widget-accent widget) 1 1))
      ((eq kind :cell)
       (shape renderer box 0
              (if (widget-value widget) "#e7effa"
                  (widget-background widget)) 1)
       (outline renderer box 0
                (if (widget-value widget) (widget-accent widget) "#939ba5")
                1 (if (widget-value widget) 2 1))
       (paint-text renderer (widget-text widget)
                   (+ (box-x box) 4)
                   (+ (box-y box) 6 (baseline font))
                   (widget-foreground widget)))
      ((eq kind :list-item)
       (shape renderer box 0
              (if (widget-value widget) (widget-accent widget)
                  (widget-background widget)) 1)
       (when (and (not (widget-value widget))
                  (hovered-p (element-id node)))
         (shape renderer box 0 foreground 0.12))
       (paint-text renderer (widget-text widget)
                   (+ (box-x box) 6) (+ (box-y box) 6 (baseline font))
                   (if (widget-value widget) "#ffffff" foreground)))
      ((eq kind :gauge)
       (shape renderer box radius (widget-background widget) 1)
       (let ((fill (make-box :x (box-x box) :y (box-y box)
                             :width (* (box-width box) (widget-value widget))
                             :height (box-height box))))
         (shape renderer fill radius (widget-accent widget) 1))
       (outline renderer box radius foreground 1 1))
      ((eq kind :canvas) (paint-canvas renderer node))
      ((eq (toolkit-surface (widget-style widget)) :garnet)
       (paint-garnet renderer node))
      (t
       (unless (eq kind :label)
         (when (and glass (< (widget-opacity widget) 1)
                    (renderer-glass renderer))
           (funcall (renderer-glass renderer)
                    box radius (widget-frost widget)))
         (shape renderer box radius (widget-background widget)
                (if glass (widget-opacity widget) 1))
         (if glass
             (outline renderer box radius "#ffffff"
                      (if disabled 0.15f0 0.4f0) 1)
             (unless (eq kind :checkbox)
               (motif-bevel renderer box pressed disabled))))
       (when (and (member kind '(:button :tab :checkbox))
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
                   (if glass 7 0) (if disabled "#a0a0a0" "#ffffff") 1)))
         (:checkbox
          (let ((indicator (make-box :x x :y y :width 16 :height 16)))
            (shape renderer indicator (if glass 4 0)
                   (if glass
                       (if (widget-value widget)
                           (widget-accent widget) "#777777")
                       (widget-background widget))
                   1)
            (unless glass
              (motif-bevel renderer indicator
                           (or pressed (widget-value widget)) disabled))
            (when (widget-value widget)
              (funcall
               (renderer-polygons renderer)
               (list (mapcar (lambda (point)
                               (cons (+ x (car point)) (+ y (cdr point))))
                             '((3 . 7) (6 . 10) (12 . 3) (14 . 5)
                               (6 . 13) (2 . 9))))
               (if glass "#ffffff" foreground) 1)))
          (loop :for line :in (wrap-text
                              font (widget-text widget)
                              (max 0 (- (box-width box) 48)))
                :for baseline :from (+ y (baseline font))
                  :by (line-height font)
                :do (paint-text renderer line (+ x 24) baseline
                                foreground)))
         (:text-field
          (paint-text-field renderer node x y
                            (max 0 (- (box-width box) (* 2 inset)))))
         (otherwise
          (loop :for line :in (wrap-text
                              font (widget-text widget)
                              (max 0 (- (box-width box) (* 2 inset))))
                :for baseline :from (+ y (baseline font))
                  :by (line-height font)
                :do (paint-text renderer line x baseline
                                foreground))))))
    (when (and (focused-p node) (context-focus-visible-p *context*))
      (outline renderer (inset-box box 2) (max 0 (- radius 2))
               (widget-accent widget) 1 2))))

(defstruct text-selection
  anchor focus anchor-text focus-text anchor-key focus-key field
  (node-count 0 :type integer)
  (pending-copy-p nil :type boolean)
  (dragging-p nil :type boolean))

(fn selectable-nodes ((context context) &optional keys-p)
  (let ((nodes nil) (keys (when keys-p (make-hash-table :test 'eq))))
    (labels ((visit (node anchor path)
               (when (element-id node)
                 (setf anchor (element-id node) path nil))
               (let ((widget (element-content node)))
                 (when (and (widget-p widget)
                            (member (widget-kind widget)
                                    '(:label :text-field))
                            (not (widget-disabled-p widget)))
                   (push node nodes)
                   (when keys
                     ;; Anonymous nodes retain position under the closest ID.
                     ;; Identical siblings at unchanged positions cannot differ.
                     (setf (gethash node keys)
                           (list anchor (reverse path))))))
               (loop :for child :across (element-children node)
                     :for index :from 0
                     :do (visit child anchor (when keys (cons index path))))))
      (when (context-root context) (visit (context-root context) nil nil)))
    (values (nreverse nodes) keys)))

(fn selection-target ((context context) (x real) (y real))
  (let ((target nil))
    (walk-elements
     (context-root context)
     (lambda (node)
       (when (and (widget-p (element-content node))
                  (lui.frame::contains-p (element-clip node) x y))
         (setf target node))))
    target))

(fn selection-text ((node element))
  (let ((widget (element-content node)))
    (if (eq (widget-kind widget) :text-field)
        (widget-value widget) (widget-text widget))))

(fn selection-inset ((node element))
  (if (eq (widget-kind (element-content node)) :label) 0
      (if (eq (toolkit-surface (widget-style (element-content node)))
              :garnet) 6 12)))

(fn selection-index ((renderer renderer) (node element) (x real) (y real))
  (let* ((font (widget-font renderer (element-content node)))
         (box (element-box node)) (inset (selection-inset node))
         (text (selection-text node)) (start 0)
         (top (+ (box-y box) (if (zerop inset) 0 6)))
         (lines (wrap-text font text
                           (max 0 (- (box-width box) (* 2 inset))))))
    (dolist (line lines (length text))
      (when (< y (+ top (line-height font)))
        (let ((at (- x (box-x box) inset)) (left 0) (previous nil)
              (scale (/ (font-size font)
                        (zpb-ttf:units/em (font-loader font)))))
          (dotimes (i (length line))
            (let* ((char (char line i))
                   (right (+ left
                             (* scale
                                (+ (zpb-ttf:advance-width
                                    (zpb-ttf:find-glyph
                                     char (font-loader font)))
                                   (if previous
                                       (zpb-ttf:kerning-offset
                                        previous char (font-loader font))
                                       0))))))
              (when (< at (/ (+ left right) 2))
                (return-from selection-index (+ start i)))
              (setf left right previous char)))
          (return-from selection-index (+ start (length line)))))
      (incf start (1+ (length line)))
      (incf top (line-height font)))))

(fn selection-range ((selection text-selection) (index integer)
                    (length integer))
  (let ((a (text-selection-anchor selection))
        (b (text-selection-focus selection)))
    (when (and a b)
      (when (or (> (car a) (car b))
                (and (= (car a) (car b)) (> (cdr a) (cdr b))))
        (rotatef a b))
      (when (<= (car a) index (car b))
        (values (min length (if (= index (car a)) (cdr a) 0))
                (min length (if (= index (car b)) (cdr b) length)))))))

(fn copy-selection ((context context) (nodes list)
                    (selection text-selection))
  (let ((text
          (if (text-selection-anchor selection)
              (with-output-to-string (out)
                (let ((separator nil))
                  (loop :for node :in nodes :for i :from 0
                        :for text := (selection-text node)
                        :do (multiple-value-bind (start end)
                                (selection-range selection i (length text))
                              (when (and start (< start end))
                                (when separator (terpri out))
                                (write-string text out :start start :end end)
                                (setf separator t))))))
              (let* ((id (context-focus context))
                     (node (find id nodes :key #'element-id :test #'equal))
                     (state (gethash id (context-state context))))
                (when (and node (typep state 'edit-state))
                  (let ((text (selection-text node)))
                    (subseq text
                            (min (length text) (edit-state-anchor state)
                                 (edit-state-cursor state))
                            (min (length text)
                                 (max (edit-state-anchor state)
                                      (edit-state-cursor state))))))))))
    (when (and text (plusp (length text)) (context-copy context))
      (funcall (context-copy context) text))))

(fn selection-input ((renderer renderer) (context context) (events list))
  (unless (and events
               (or (and (context-selection context)
                        (text-selection-dragging-p
                         (context-selection context)))
                   (some (lambda (event)
                           (or (and (eq (event-kind event) :press)
                                    (eq (event-button event) :primary))
                               (and (eq (event-kind event) :key)
                                    (eq (event-key event) :copy))))
                         events)))
    (return-from selection-input nil))
  (let* ((nodes (selectable-nodes context))
         (selection (or (context-selection context)
                        (setf (context-selection context)
                              (make-text-selection)))))
    (dolist (event events)
      (let* ((kind (event-kind event))
             (x (event-x event)) (y (event-y event))
             (target
               (find-if (lambda (node)
                          (lui.frame::contains-p (element-clip node) x y))
                        nodes :from-end t)))
        (when (and (null target) (text-selection-dragging-p selection)
                   (member kind '(:move :release)))
          (let ((distance nil) (horizontal nil))
            (dolist (node nodes)
              (let* ((box (element-clip node))
                     (dx (max 0 (- (box-x box) x)
                              (- x (+ (box-x box) (box-width box)))))
                     (dy (max 0 (- (box-y box) y)
                              (- y (+ (box-y box) (box-height box)))))
                     (d dy))
                (when (and (plusp (box-width box))
                           (plusp (box-height box))
                           (or (null distance) (< d distance)
                               (and (= d distance) (< dx horizontal))))
                  (setf target node distance d horizontal dx))))))
        (cond
          ((and (eq kind :key) (eq (event-key event) :copy))
           (setf (text-selection-pending-copy-p selection) t))
          ((and (eq kind :press) (eq (event-button event) :primary))
           (setf (context-selection context)
                 (setf selection (make-text-selection)))
           (setf target (selection-target context x y))
           (when (member target nodes)
             (let ((at (selection-index renderer target x y)))
               (setf (text-selection-dragging-p selection) t)
               (if (eq (widget-kind (element-content target)) :text-field)
                   (let* ((id (element-id target))
                          (state (or (gethash id (context-state context))
                                     (setf (gethash id
                                                    (context-state context))
                                           (make-edit-state)))))
                     (setf (text-selection-field selection) id
                           (edit-state-anchor state) at
                           (edit-state-cursor state) at))
                   (multiple-value-bind (snapshot keys)
                       (selectable-nodes context t)
                     (setf (text-selection-node-count selection)
                           (length snapshot)
                           (text-selection-anchor-key selection)
                           (gethash target keys)
                           (text-selection-focus-key selection)
                           (gethash target keys)
                           (text-selection-anchor selection)
                           (cons (position target nodes) at)
                           (text-selection-focus selection)
                           (cons (position target nodes) at)
                           (text-selection-anchor-text selection)
                           (copy-seq (selection-text target))
                           (text-selection-focus-text selection)
                           (copy-seq (selection-text target))))))))
          ((and (member kind '(:move :release))
                (text-selection-dragging-p selection))
           (if (text-selection-field selection)
               (let* ((id (text-selection-field selection))
                      (node (find id nodes :key #'element-id :test #'equal))
                      (state (gethash id (context-state context))))
                 (when (and node state)
                   (setf (edit-state-cursor state)
                         (selection-index renderer node x y))))
               (when target
                 (multiple-value-bind (snapshot keys)
                     (selectable-nodes context t)
                   (declare (ignore snapshot))
                   (setf (text-selection-focus-key selection)
                         (gethash target keys)))
                 (setf (text-selection-focus selection)
                       (cons (position target nodes)
                             (selection-index renderer target x y))
                       (text-selection-focus-text selection)
                       (copy-seq (selection-text target)))))
           (when (eq kind :release)
             (setf (text-selection-dragging-p selection) nil))))))))

(fn paint-selection ((renderer renderer) (context context))
  (let ((selection (context-selection context)))
    (when (and selection (text-selection-anchor selection))
      (multiple-value-bind (nodes keys) (selectable-nodes context t)
        (unless (= (length nodes) (text-selection-node-count selection))
          (setf (context-selection context) nil)
          (return-from paint-selection nil))
        (dolist (endpoint (list (list (text-selection-anchor selection)
                                     (text-selection-anchor-key selection)
                                     (text-selection-anchor-text selection))
                               (list (text-selection-focus selection)
                                     (text-selection-focus-key selection)
                                     (text-selection-focus-text selection))))
          (let ((node (nth (caar endpoint) nodes)))
            (unless (and node (equal (gethash node keys) (second endpoint))
                         (equal (selection-text node) (third endpoint)))
              (setf (context-selection context) nil)
              (return-from paint-selection nil))))
        (loop :for node :in nodes :for i :from 0
              :for text := (selection-text node)
              :do (multiple-value-bind (start end)
                      (selection-range selection i (length text))
                    (when (and start (< start end))
                      (let* ((font (widget-font renderer
                                               (element-content node)))
                             (box (element-box node))
                             (inset (selection-inset node))
                             (offset 0))
                        (funcall (renderer-clip renderer) (element-clip node))
                        (loop :for line :in
                                   (wrap-text font text
                                              (max 0 (- (box-width box)
                                                        (* 2 inset))))
                              :for y :from (+ (box-y box)
                                              (if (zerop inset) 0 6))
                                :by (line-height font)
                              :for left := (max start offset)
                              :for right := (min end (+ offset (length line)))
                              :do
                              (when (< left right)
                                (let ((x (text-width
                                          font (subseq text offset left))))
                                  (shape renderer
                                         (make-box
                                          :x (+ (box-x box) inset x) :y y
                                          :width (- (text-width
                                                     font
                                                     (subseq text offset
                                                             right))
                                                    x)
                                          :height (line-height font))
                                         0 "#258bff" 0.4)))
                              (incf offset (1+ (length line))))))))))))

(fn paint-frame ((renderer renderer) (context context))
  "Paint the visible elements of a solved frame and its text selection."
  (unless (context-input-handler context)
    (setf (context-input-handler context)
          (lambda (context events)
            (selection-input renderer context events))))
  (let ((*context* context))
    (visible-elements
     (context-root context)
     (lambda (node)
       (when (widget-p (element-content node))
         (paint-widget renderer node))))
    (let* ((selection (context-selection context))
           (input (context-focus-input context))
           (focused (and input (equal (car input) (context-focus context))
                         (cdr input)))
           (nodes (when (and selection
                             (or (text-selection-pending-copy-p selection)
                                 (and (text-selection-anchor selection) focused)))
                    (selectable-nodes context)))
           (field (find (context-focus context) nodes :key #'element-id
                        :test #'equal)))
      (when (and selection field
                 (eq (widget-kind (element-content field)) :text-field)
                 (some (lambda (event)
                         (or (member (event-kind event) '(:text :change))
                             (and (eq (event-kind event) :key)
                                  (not (eq (event-key event) :copy)))))
                       focused))
        (setf (text-selection-anchor selection) nil
              (text-selection-focus selection) nil
              (text-selection-dragging-p selection) nil))
      (paint-selection renderer context)
      (when (and selection (eq selection (context-selection context))
                 (shiftf (text-selection-pending-copy-p selection) nil))
        (copy-selection context (or nodes (selectable-nodes context))
                        selection)))))
