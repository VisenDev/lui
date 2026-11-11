(defpackage #:lui.tests.native
  (:use #:cl #:lui.layout #:lui.frame #:lui.widgets #:lui.font #:lui.draw)
  (:export #:run-tests))

(in-package #:lui.tests.native)

(defun near (a b &optional (epsilon 0.001f0))
  (< (abs (- a b)) epsilon))

(defun rectangle (x y width height)
  (coerce (list (cons x y) (cons (+ x width) y)
                (cons (+ x width) (+ y height)) (cons x (+ y height)))
    'contour))

(defun polygon-area (points)
  (/ (abs (loop :for i :below (length points)
                :for a := (aref points i)
                :for b := (aref points (mod (1+ i) (length points)))
                :sum (- (* (car a) (cdr b)) (* (car b) (cdr a)))))
     2))

(defun filled-area (contours)
  (let ((area 0))
    (trapezoids contours
                (lambda (points) (incf area (polygon-area points))))
    area))

(defun test-winding ()
  (let ((rgba (color-components "#ff8000" 1/2)))
    (assert (typep rgba '(vector single-float 4)))
    (assert (near (aref rgba 0) 1))
    (assert (near (aref rgba 1) (/ 128 255)))
    (assert (near (aref rgba 2) 0))
    (assert (near (aref rgba 3) 0.5)))
  (let ((outer (rectangle 0 0 10 10))
        (inner (rectangle 3 3 4 4)))
    (assert (= 100 (filled-area (vector outer inner))))
    (assert (= 84 (filled-area (vector outer (reverse inner)))))
    (assert (= 84 (filled-area (vector (reverse outer) inner))))
    (assert (= 104 (filled-area
                   (vector outer (rectangle 20 20 2 2))))))
  (assert (= 12 (filled-area
                 '#(#((0 . 0) (4 . 0) (4 . 2)
                       (2 . 2) (2 . 4) (0 . 4))))))
  (assert (zerop (filled-area '#(#() #((1 . 1)) #((1 . 1) (3 . 1))))))
  (let* ((box (make-box :x 10 :y 20 :width 40 :height 20))
         (rounded (rounded-polygon box 100)))
    (let ((square (rounded-polygon box 0)))
      (assert (= 4 (length square)))
      (assert (= 800 (filled-area (vector square)))))
    (assert (typep rounded 'contour))
    (assert (= 36 (length rounded)))
    (assert (every (lambda (point)
                     (and (<= 10 (car point) 50)
                          (<= 20 (cdr point) 40)))
                   rounded))
    (assert (< 600 (polygon-area rounded) 800))))

(defun test-outlines (font)
  (let ((curves 0) (contour-index 0)
        (contours (glyph-polygons font #\O)))
    (assert (typep contours 'contours))
    (assert (every (lambda (points) (typep points 'contour)) contours))
    (assert (>= (length contours) 2))
    (zpb-ttf:do-contours
        (contour (zpb-ttf:find-glyph #\O (font-loader font)))
      (let ((samples (aref contours contour-index)) (index 0))
        (incf contour-index)
        (zpb-ttf:do-contour-segments (p0 p1 p2) contour
          (if p1
              (progn
                (incf curves)
                ;; A quadratic's midpoint is 1/4 P0 + 1/2 P1 + 1/4 P2.
                (let ((middle (aref samples (+ index 5))))
                  (assert (near (car middle)
                                (/ (+ (zpb-ttf:x p0)
                                      (* 2 (zpb-ttf:x p1))
                                      (zpb-ttf:x p2))
                                   4)))
                  (assert (near (cdr middle)
                                (/ (+ (zpb-ttf:y p0)
                                      (* 2 (zpb-ttf:y p1))
                                      (zpb-ttf:y p2))
                                   4))))
                (assert (near (car (aref samples (+ index 11))) (zpb-ttf:x
                      p2)))
                (assert (near (cdr (aref samples (+ index 11))) (zpb-ttf:y
                      p2)))
                (incf index 12))
              (progn
                (assert (= (car (aref samples index)) (zpb-ttf:x p2)))
                (assert (= (cdr (aref samples index)) (zpb-ttf:y p2)))
                (incf index))))
        (assert (= index (length samples)))))
    (assert (plusp curves))
    (assert (eq (glyph-polygons font #\O) (glyph-polygons font #\O)))
    (assert (zerop (length (glyph-polygons font #\Space))))))

(defun test-font-metrics (font)
  (let* ((loader (font-loader font))
         (scale (/ (font-size font) (zpb-ttf:units/em loader)))
         (table (zpb-ttf::kerning-table loader))
         (key (logior
               (ash (zpb-ttf:font-index (zpb-ttf:find-glyph #\A loader)) 16)
               (zpb-ttf:font-index (zpb-ttf:find-glyph #\V loader)))))
    ;; A controlled nonzero pair also catches measuring/painting disagreement
    ;; when a system font has no legacy kern table (for example, GPOS only).
    (multiple-value-bind (old present) (gethash key table)
      (unwind-protect
           (progn
             (setf (gethash key table) -100)
             (assert (near (text-width font "AV")
                           (+ (text-width font "A")
                              (text-width font "V") (* scale -100)))))
        (if present (setf (gethash key table) old) (remhash key table))))
    (assert (near (line-height font)
                  (* scale (+ (zpb-ttf:ascender loader)
                              (- (zpb-ttf:descender loader))
                              (zpb-ttf:line-gap loader)))))
    (assert (near (baseline font) (* scale (zpb-ttf:ascender loader))))
    (assert (zerop (text-width font "")))
    (let ((width (text-width font "alpha beta")))
      (assert (equalp #("alpha beta" "gamma")
                     (wrap-text font "alpha beta gamma" width)))
      (assert (equalp #("unbreakable")
                     (wrap-text font "unbreakable" 1))))
    (assert (equalp #("a" "" "b" "")
                   (wrap-text font (format nil "a~%~%b~%") nil)))))

(defun test-shared-wrapping ()
  (flet ((measure (text start end)
           (declare (ignore text)) (- end start)))
    (dolist (case '(("" nil #("")) ("a b c" 3 #("a b" "c"))
                    ("long word" 1 #("long" "word"))
                    ("a  b " 2 #("a " "b ")) ("  a" 1 #(" " "a"))))
      (destructuring-bind (text width expected) case
        (assert (equalp expected (lui.text:wrap-lines text width
                #'measure))))))
  (assert (typep (lui.text:wrap-lines "a b" 1 (lambda (text start end)
          (declare (ignore text)) (- end start)))
                 '(vector string)))
  (let ((longest 0)
        (text (format nil "~{~A~^ ~}" (make-list 1000 :initial-element
              "word"))))
    (lui.text:wrap-lines text 10
      (lambda (text start end)
        (declare (ignore text))
        (setf longest (max longest (- end start)))
        (- end start)))
    (assert (<= longest 14))))

(defun test-measurement (font)
  (let* ((renderer (make-renderer :font font))
         (widget (make-widget :kind :button :text "alpha beta gamma")))
    (setf (font-size font) (widget-font-size widget))
    (let ((width (+ 24 (text-width font "alpha beta"))))
      (multiple-value-bind (measured height)
          (measure-widget renderer widget width)
        (assert (near measured width))
        (assert (near height (+ 12 (* 2 (line-height font)))))))
    (multiple-value-bind (width height)
        (measure-widget renderer
                        (make-widget :kind :checkbox :text "Enabled") nil)
      (assert (near width (+ 48 (text-width font "Enabled"))))
      (assert (near height (+ 12 (line-height font)))))
    (multiple-value-bind (width height)
        (measure-widget renderer (make-widget :kind :panel) 30)
      (assert (zerop width))
      (assert (zerop height)))))

(defun test-measurement-cache ()
  (let* ((font (open-font)) (renderer (make-renderer :font font))
         (context (make-context))
         (text (copy-seq "alpha beta gamma"))
         (widget (make-widget :kind :label :text text :style :test-cache))
         (wrap (symbol-function 'wrap-text))
         (wraps 0) (geometries 0) (inset 0) (value-p nil) (text-p t)
         (result nil))
    (lui:register-toolkit
     :test-cache :parent :qt
     :geometry (lambda (widget)
                 (declare (ignore widget))
                 (incf geometries)
                 (make-geometry :left inset :top inset :value-p value-p
                                :text-p text-p)))
    (unwind-protect
         (progn
           (setf (symbol-function 'wrap-text)
                 (lambda (font text width)
                   (incf wraps) (funcall wrap font text width)))
           (labels ((frame (width)
                      (with-frame (context 200 100)
                        (setf result
                              (multiple-value-list
                               (measure-widget renderer widget width)))))
                    (miss (width)
                      (let ((before wraps))
                        (frame width)
                        (assert (= wraps (1+ before)))))
                    (hit (width)
                      (let ((before wraps))
                        (frame width)
                        (assert (= wraps before)))))
             (miss nil)
             (hit nil)
             (assert (= geometries 2))
             ;; Width and editable strings are inputs, even with stable widgets.
             (let ((height (second result)))
               (miss 60)
               (assert (> (second result) height)))
             (hit 60)
             (setf (char text 0) #\W)
             (miss 60)
             (setf (widget-font-size widget) 22)
             (miss 60)
             (setf (widget-font-weight widget) :bold)
             (miss 60)
             (setf (widget-font-family widget) :monospace)
             (miss 60)
             ;; Dynamic toolkit geometry is evaluated before looking up a result.
             (setf inset 12)
             (miss 60)
             (hit 60)
             (setf value-p t (widget-value widget) "New value")
             (miss 60)
             (setf (widget-value widget) "Edited value")
             (miss 60)
             (setf text-p nil)
             (frame 60)
             (assert (equal '(12 12) result))
             ;; Restoring text, an aborted frame, and font replacement all miss.
             (setf text-p t)
             (miss 60)
             (catch 'abort
               (with-frame (context 200 100)
                 (measure-widget renderer widget 60)
                 (throw 'abort nil)))
             (miss 60)
             (let ((replacement (open-font)))
               (unwind-protect
                    (progn (setf (renderer-font renderer) replacement)
                           (miss 60) (hit 60))
                 (setf (renderer-font renderer) font)
                 (close-font replacement)))
             ;; Removing all measurements drops the previous entries entirely.
             (with-frame (context 200 100))
             (miss 60)))
      (setf (symbol-function 'wrap-text) wrap)
      (close-font font))))

(defun bounds (contours)
  (let ((left nil) (top nil) (right nil) (bottom nil))
    (loop :for points :across contours :do
      (loop :for point :across points :for x := (car point) :for y := (cdr
            point) :do
        (setf left (if left (min left x) x) top (if top (min top y) y)
              right (if right (max right x) x) bottom (if bottom (max bottom
                y) y))))
    (list left top (- right left) (- bottom top))))

(defun test-edit-painting (font)
  (let* ((calls nil)
         (clips nil)
         (renderer
           (make-renderer
            :font font
            :polygons (lambda (contours color alpha)
                        (push (list contours color alpha) calls))
            :clip (lambda (box) (push box clips))))
         (context (make-context
                   :measure (lambda (widget width)
                              (measure-widget renderer widget width)))))
    (with-frame (context 240 120)
      (lui.glass:text-field
        (lui:opt
          :id :name
          :value "AV"
          :width (fixed 180)
          :height (fixed 40)
          :accent "#ff5500")))
    (let* ((node (aref (element-children (context-root context)) 0))
           (state (gethash (lui:widget-id :name context) (context-state
                context))))
      (setf (context-focus context) (lui:widget-id :name context)
            (context-focus-visible-p context) t
            (edit-state-anchor state) 0
            (edit-state-cursor state) 2)
      (paint-frame renderer context)
      (assert (= 1 (length clips)))
      (let ((selection
              (find-if (lambda (call)
                         (and (string= "#ff5500" (second call))
                              (= 0.35f0 (third call))))
                       calls))
            (focus (find-if
                    (lambda (call)
                      (and (string= "#ff5500" (second call))
                           (= 1 (third call))
                           (= 2 (length (first call)))))
                    calls))
            (caret (find-if
                    (lambda (call)
                      (and (first call)
                           (near 1 (third (bounds (first call))))))
                    calls)))
        (assert selection)
        (assert focus)
        (assert caret)
        (destructuring-bind (x y width height) (bounds (first selection))
          (assert (near x (+ 12 (box-x (element-box node)))))
          (assert (near y (+ 6 (box-y (element-box node)))))
          (assert (near width (text-width font "AV")))
          (assert (near height (line-height font))))
        (assert (near (first (bounds (first caret)))
                      (+ 12 (box-x (element-box node))
                         (text-width font "AV")))))
      (setf calls nil
            (widget-disabled-p (element-content node)) t)
      (paint-frame renderer context)
      (assert (not (find "#ff5500" calls :key #'second :test #'equal)))
      (setf calls nil
            (widget-disabled-p (element-content node)) nil
            (widget-value (element-content node)) (format nil "a~%b")
            (edit-state-anchor state) 0
            (edit-state-cursor state) 3
            (box-height (element-box node)) 80
            (box-height (element-clip node)) 80)
      (paint-frame renderer context)
      (let ((selections
              (remove-if-not
               (lambda (call)
                 (and (string= "#ff5500" (second call))
                      (= 0.35f0 (third call))))
               calls))
            (caret
              (find-if (lambda (call)
                         (and (first call)
                              (near 1 (third (bounds (first call))))))
                       calls)))
        (assert (= 2 (length selections)))
        (assert (near (second (bounds (first caret)))
                      (+ 6 (box-y (element-box node))
                         (line-height font))))))))

(defun test-panel-painting (font)
  (let* ((calls 0)
         (saw-context nil)
         (renderer
           (make-renderer :font font
                          :polygons (lambda (contours color alpha)
                                      (declare (ignore contours color alpha))
                                      (incf calls))
                          :clip (lambda (box)
                                          (declare (ignore box)))))
         (context (make-context)))
    (setf (context-root context)
          (make-element :content (make-widget :kind :panel :text "ignored")
                        :box (make-box :width 100 :height 60)
                        :clip (make-box :width 100 :height 60)))
    (paint-frame renderer context)
    (assert (= calls 2))
    (setf (widget-painter (element-content (context-root context)))
          (lambda (renderer node)
            (declare (ignore renderer node))
            (setf saw-context (eq *context* context))))
    (paint-frame renderer context)
    (assert saw-context)))

(defun test-custom-toolkit (font)
  ;; A new widget kind has no built-in graphical surface to fall back on.
  (let* ((painted nil) (measured nil) (colors nil) (texts nil)
         (renderer
           (make-renderer
            :font font
            :clip (lambda (box) (declare (ignore box)))
            :polygons (lambda (contours color alpha)
                        (declare (ignore contours alpha)) (push color colors))
            :text (lambda (font text x y color)
                    (declare (ignore font x y color)) (push text texts))))
         (context (make-context
                   :measure (lambda (widget width)
                              (measure-widget renderer widget width)))))
    (lui:register-toolkit
     :test-graphical
     :paint (lambda (target node)
              (push (widget-kind (element-content node)) painted)
              (lui.draw:shape target (element-box node) 3 "#123456" 1)
              (lui.draw:outline target (element-box node) 3 "#654321" 1 1)
              (lui.draw:paint-text target "Badge" 4 16 "#ffffff"))
     :geometry (lambda (widget)
                 (push (widget-kind widget) measured)
                 (lui.draw:make-geometry :min-width 73 :min-height 29))
     :controls
     (list (cons :badge
                 (lambda (id text &rest options)
                   (apply #'declare-widget :badge (lui:current-toolkit)
                          id text options)))))
    (lui:register-toolkit :test-graphical-child :parent :test-graphical)
    (with-frame (context 200 100)
      (lui:with-toolkit (:test-graphical-child)
        (lui:control :badge :badge "Badge")))
    (let* ((node (gethash (lui:widget-id :badge context)
                   (lui.frame::context-ids context)))
           (widget (element-content node)))
      (assert (eq :test-graphical-child (widget-style widget)))
      (assert measured)
      (assert (= 73 (box-width (element-box node))))
      (assert (= 29 (box-height (element-box node))))
      (assert (equal '(73 29)
                     (multiple-value-list (measure-widget renderer widget
                120))))
      (assert (eq :badge (first measured)))
      (paint-frame renderer context)
      (assert (member :badge painted))
      (assert (member "#123456" colors :test #'equal))
      (assert (member "#654321" colors :test #'equal))
      (assert (member "Badge" texts :test #'equal))
      (setf painted nil colors nil texts nil
            (widget-painter widget)
            (lambda (target element)
              (assert (eq target renderer))
              (assert (eq element node))
              (lui.draw:shape target (element-box element) 0 "#abcdef" 1)))
      (paint-frame renderer context)
      (assert (null painted))
      (assert (equal '("#abcdef") colors))
      (assert (null texts)))))

(defun test-button-feedback (font)
  (let* ((calls nil)
         (renderer
           (make-renderer
            :font font
            :clip (lambda (box) (declare (ignore box)))
            :polygons (lambda (contours color alpha)
                        (push (list color alpha (length contours)) calls))))
         (context (make-context
                   :measure (lambda (widget width)
                              (measure-widget renderer widget width)))))
    (with-frame (context 240 120)
      (lui.glass:button "Action" (lui:opt :id :action :accent "#ff5500")))
    (flet ((paint ()
             (setf calls nil)
             (paint-frame renderer context)))
      (setf (context-focus context) (lui:widget-id :action context)
        (context-hover context) (lui:widget-id :action context))
      (paint)
      (assert (member '("#ffffff" 0.14f0 1) calls :test #'equal))
      (assert (not (member '("#ff5500" 1 2) calls :test #'equal)))
      (setf (context-active context) (lui:widget-id :action context))
      (paint)
      (assert (member '("#000000" 0.2f0 1) calls :test #'equal))
      (setf (context-focus-visible-p context) t)
      (paint)
      (assert (member '("#ff5500" 1 2) calls :test #'equal)))))

(defun test-motif-states (font)
  (let* ((calls nil)
         (renderer
           (make-renderer
            :font font
            :clip (lambda (box) (declare (ignore box)))
            :polygons (lambda (contours color alpha)
                        (push (list contours color alpha) calls))))
         (context (make-context
                   :measure (lambda (widget width)
                              (measure-widget renderer widget width)))))
    (with-frame (context 240 120)
      (lui.motif:button "Disabled" (lui:opt :id :disabled :disabled-p t)))
    (paint-frame renderer context)
    (assert (find "#777777" calls :key #'second :test #'equal))
    (assert (find "#989898" calls :key #'second :test #'equal))
    (dolist (disabled '(nil t))
      (with-frame (context 240 120)
        (lui.motif:text-field
          (lui:opt :id :editor :value "" :disabled-p disabled)))
      (setf calls nil)
      (paint-frame renderer context)
      (let ((edges (loop :for (paths color) :in (reverse calls)
                         :when (= 6 (length (aref paths 0)))
                           :collect color)))
        (assert (equal edges (if disabled '("#989898" "#d0d0d0")
                                 '("#505050" "#ffffff"))))))
    (with-frame (context 240 120)
      (lui.motif:checkbox "Enabled" (lui:opt :id :toggle :value nil)))
    (setf (context-hover context) (lui:widget-id :toggle context) calls nil)
    (paint-frame renderer context)
    (assert (find-if (lambda (call)
                       (and (equal "#ffffff" (second call))
                            (= 0.14f0 (third call)))) calls))
    (let ((unchecked (length calls)))
      (setf (widget-value
             (element-content
              (aref (element-children (context-root context)) 0))) t
            calls nil)
      (paint-frame renderer context)
      (assert (= (1+ unchecked) (length calls))))))

(defun test-font-faces ()
  (let* ((base (open-font))
         (normal (font-face base :monospace :normal))
         (bold (font-face base :monospace :bold))
         (sans-bold (font-face base :sans-serif :bold))
         (renderer (make-renderer
                    :font base
                    :clip (lambda (box) (declare (ignore box)))
                    :polygons (lambda (&rest arguments)
                                (declare (ignore arguments)))))
         (context (make-context
                   :measure (lambda (widget width)
                              (measure-widget renderer widget width)))))
    (unwind-protect
         (progn
           (assert (eq bold (font-face base :monospace :bold)))
           (assert (eq normal (font-face bold :monospace :normal)))
           (assert (eq base (font-face bold :sans-serif :normal)))
           (assert (near (text-width bold "i") (text-width bold "W")))
           (assert (not (equalp (glyph-polygons normal #\W)
                               (glyph-polygons bold #\W))))
           (let ((saw-font nil))
             (with-frame (context 240 80)
               (lui.garnet:button
              "Selected face"
              (lui:opt
                :id :custom
                :font-size 20
                :painter
                  (lambda (renderer node)
                    (declare (ignore node))
                                                            (setf saw-font
                          (and (eq bold (renderer-font renderer))
                               (= 20 (font-size bold))))))))
             (paint-frame renderer context)
             (assert saw-font)
             (assert (eq base (renderer-font renderer)))
             (setf (widget-painter
                    (element-content
                     (aref (element-children (context-root context)) 0)))
                   (lambda (renderer node)
                     (declare (ignore node))
                     (assert (eq bold (renderer-font renderer)))
                     (error "Expected painter failure.")))
             (assert (handler-case (progn (paint-frame renderer context) nil)
                       (error () t)))
             (assert (eq base (renderer-font renderer)))))
      (close-font base))
    (dolist (face (list base normal bold sans-bold))
      (assert (null (font-loader face))))
    (close-font base)))

(defun test-garnet-states (font)
  (let* ((calls nil) (texts nil) (glass-calls 0)
         (renderer
           (make-renderer
            :font font
            :clip (lambda (box) (declare (ignore box)))
            :backdrop-effect (lambda (&rest arguments)
                     (declare (ignore arguments)) (incf glass-calls))
            :text (lambda (face text x y color)
                    (push (list text x y color face) texts))
            :polygons (lambda (contours color alpha)
                        (push (list contours color alpha) calls))))
         (context (make-context
                   :measure (lambda (widget width)
                              (measure-widget renderer widget width)))))
    (with-frame (context 400 400)
      (lui.garnet:panel (lui:opt :id :window :width (grow) :height (grow)
                                 :padding 8 :gap 8)
        (lui.garnet:label "Garnet")
        (lui.garnet:button "Push" (lui:opt :id :push))
        (lui.garnet:button "Disabled" (lui:opt :id :disabled :disabled-p t))
        (lui.garnet:checkbox "Checked" (lui:opt :id :check
                                         :value t))
        (lui.garnet:slider (lui:opt :id :range :value 0.5))
        (lui.garnet:text-field (lui:opt :id :text :value "Edit"))
        (lui.garnet:tab "Selected" (lui:opt :id :tab
                                     :selected-p t))))
    (flet ((paint ()
             (setf calls nil texts nil)
             (paint-frame renderer context)))
      (paint)
      (assert (zerop glass-calls))
      (assert (every (lambda (call) (= 1 (third call))) calls))
      (let ((first (car (last calls))))
        ;; The root is one opaque rectangle, without a window-sized shadow.
        (assert (equal '("#ffffff" 1) (rest first)))
        (assert (equal '(0 0 400 400) (bounds (first first)))))
      (assert (find "#777777" texts :key #'fourth :test #'equal))
      (assert (equal "#ffffff" (fourth (find "Selected" texts
                                            :key #'first :test #'equal))))
      (assert (every (lambda (text)
                       (eq (fifth text) (font-face font :monospace :bold)))
                     texts))
      (let* ((pattern (first (find-if
                             (lambda (call) (> (length (first call)) 2))
                             calls)))
             (push-text (find "Push" texts :key #'first :test #'equal))
             (count (length calls)))
        (assert pattern)
        (loop :for square :across pattern :do
          (assert (equal '(1 1) (cddr (bounds (vector square))))))
        (paint)
        (assert (find pattern calls :key #'first :test #'eq))
        (setf (context-hover context) (lui:widget-id :disabled context))
        (paint)
        (assert (= count (length calls)))
        (setf (context-hover context) (lui:widget-id :push context)
          (context-active context) (lui:widget-id :push context))
        (paint)
        (let ((pressed (find "Push" texts :key #'first :test #'equal)))
          (assert (near (+ 4 (second push-text)) (second pressed)))
          (assert (near (+ 4 (third push-text)) (third pressed)))))
      ;; Crossed contours in one tessellation can swap edge order mid-slab.
      ;; Render independent strokes, each centered in the 20px checkbox face.
      (let* ((strokes
               (remove-if-not
                (lambda (call)
                  (and (= 1 (length (first call)))
                       (equal '(10 10) (cddr (bounds (first call))))
                       (near 20 (filled-area (first call))))) calls))
             (box (element-box
                    (gethash (lui:widget-id :check context)
                      (lui.frame::context-ids context))))
             (center-x (- (+ (box-x box) (box-width box)) 14))
             (center-y (+ (box-y box) (/ (box-height box) 2) -2)))
        (assert (= 2 (length strokes)))
        (dolist (stroke strokes)
          (destructuring-bind (x y width height) (bounds (first stroke))
            (assert (near (+ x (/ width 2)) center-x))
            (assert (near (+ y (/ height 2)) center-y))))))))

(defun test-pointer-selection (font)
  (let* ((copied nil)
         (renderer (make-renderer :font font
                                  :polygons (lambda (&rest args)
                                              (declare (ignore args)))
                                  :clip (lambda (box)
                                          (declare (ignore box)))))
         (context (make-context
                   :copy (lambda (text) (setf copied text))
                   :measure (lambda (widget width)
                              (measure-widget renderer widget width)))))
    (labels ((draw ()
               (lui.glass:label "Alpha beta")
               (lui.glass:label "Gamma")
          (lui.glass:text-field
            (lui:opt :id :copy-field :value "Unicode lambda")))
             (frame (&rest events)
               (with-frame (context 400 200 :events events) (draw))
               (paint-frame renderer context)))
      (frame)
      (frame (make-event :kind :press :x 0 :y 1)
             (make-event :kind :move :x 300 :y 1)
             (make-event :kind :release :x 300 :y 1))
      (frame (make-event :kind :key :key :copy))
      (assert (equal "Alpha beta" copied))
      ;; A label owns its selection gesture without an interactive capture.
      (frame (make-event :kind :press :x 0 :y 1 :buttons 1))
      (let* ((selection (context-selection context))
             (before (lui.draw::text-selection-focus selection)))
        (frame (make-event :kind :move :x 300 :y 1 :buttons 0))
        (assert (not (lui.draw::text-selection-dragging-p selection)))
        (assert (equal before (lui.draw::text-selection-focus selection))))
      ;; Multi-label drag copies text in document order.
      (frame (make-event :kind :press :x 0 :y 1)
             (make-event :kind :release :x 300
                         :y (+ 1 (line-height font))))
      (frame (make-event :kind :key :key :copy))
      (assert (equal (format nil "Alpha beta~%Gamma") copied))
      ;; Fields use the same font hit testing as their caret/selection painter.
      (let* ((node (gethash (lui:widget-id :copy-field context)
                     (lui.frame::context-ids context)))
             (y (+ (box-y (element-box node)) 7)))
        (frame (make-event :kind :press :x 12 :y y)
               (make-event :kind :release :x 300 :y y))
        (frame (make-event :kind :key :key :copy))
        (assert (equal "Unicode lambda" copied)))
      (with-frame (context 401 200) (draw))
      (assert (null (context-selection context))))))

(defun test-selection-regressions (font)
  (let* ((copied nil) (copies 0) (clicked 0) (cover nil)
         (text (copy-seq "Same text")) (order '(:first :second))
         (extra nil) (value "Edited value")
         (renderer (make-renderer :font font
                                  :polygons (lambda (&rest args)
                                              (declare (ignore args)))
                                  :clip (lambda (box)
                                          (declare (ignore box)))))
         (context (make-context
                   :copy (lambda (text) (setf copied text) (incf copies))
                   :measure (lambda (widget width)
                              (measure-widget renderer widget width)))))
    (labels ((draw ()
               (column (:width (grow) :height (grow))
                 (dolist (id order)
                   (column (:id id) (lui.glass:label text)))
                 (when extra (lui.glass:label "Added"))
                 (setf value (lui.interaction:edit-value :field value))
                 (lui:text-field (lui:opt :id :field :value value))
                 (case cover
                   (:button
                    (column (:floating-p t)
                       (when
                    (lui.glass:button
                      "Covered"
                      (lui:opt
                        :id :cover
                        :width (fixed 150)
                                                      :height (fixed 50)))
                        (incf clicked))))
                   (:panel
                    (lui.glass:panel (lui:opt :floating-p t :width (fixed 150)
                                              :height (fixed 50)))))))
             (frame (&rest events)
               (with-frame (context 400 200 :events events) (draw))
               (paint-frame renderer context))
             (select-label ()
               (frame (make-event :kind :press :x 0 :y 1)
                      (make-event :kind :release :x 300 :y 1)))
             (anchor-p ()
               (let ((selection (context-selection context)))
                 (and selection
                      (lui.draw::text-selection-anchor selection)))))
      (frame)
      (setf cover :button)
      (frame)
      (frame (make-event :kind :press :x 3 :y 1)
             (make-event :kind :release :x 3 :y 1))
      (assert (= clicked 1))
      (assert (not (anchor-p)))
      (setf cover :panel)
      (frame)
      (select-label)
      (assert (not (anchor-p)))
      (setf cover nil)
      (frame)
      (select-label)
      (assert (anchor-p))
      ;; Keyboard field selection supersedes label selection in the same batch.
      (setf (context-focus context) (lui:widget-id :field context))
      (frame (make-event :kind :key :key :select-all)
             (make-event :kind :key :key :copy))
      (assert (equal "Edited value" copied))
      (assert (not (anchor-p)))
      (let ((count copies))
        (paint-frame renderer context)
        (assert (= count copies)))
      (frame (make-event :kind :text :value "Replacement")
             (make-event :kind :key :key :select-all)
             (make-event :kind :key :key :copy))
      (assert (equal "Replacement" copied))
      ;; Label selection still wins over an earlier focused field selection.
      (select-label)
      (frame (make-event :kind :key :key :copy))
      (assert (equal text copied))
      ;; Endpoint strings are snapshots, even when the app mutates its buffer.
      (setf (char text 0) #\s)
      (frame)
      (assert (null (context-selection context)))
      ;; Identical text under different IDs cannot silently move the selection.
      (select-label)
      (setf order (reverse order))
      (frame)
      (assert (null (context-selection context)))
      ;; Structural changes conservatively invalidate the previous range.
      (select-label)
      (setf extra t)
      (frame)
      (assert (null (context-selection context)))
      ;; Ordinary redraws preserve an unchanged keyed range and its clipping.
      (select-label)
      (frame)
      (assert (anchor-p))
      (frame (make-event :kind :key :key :copy))
      (assert (equal text copied)))))

(defun test-selection-clipping (font)
  (let* ((clip nil) (highlight nil)
         (renderer (make-renderer
                    :font font
                    :clip (lambda (box) (setf clip box))
                    :polygons (lambda (paths color alpha)
                                (declare (ignore paths))
                                (when (and (equal color "#258bff")
                                           (= alpha 0.4))
                                  (setf highlight t)))))
         (context (make-context
                   :measure (lambda (widget width)
                              (measure-widget renderer widget width)))))
    (labels ((frame (&rest events)
               (with-frame (context 400 200 :events events)
                 (column (:width (fixed 100) :height (fixed 12)
                          :padding 2 :clip-p t)
                   (lui.glass:label "Clipped text selection")))
               (paint-frame renderer context)))
      (frame)
      (frame (make-event :kind :press :x 0 :y 0))
      (assert (null (lui.draw::text-selection-anchor
                     (context-selection context))))
      (frame (make-event :kind :press :x 2 :y 3)
             (make-event :kind :release :x 200 :y 3))
      (assert highlight)
      (assert (= (box-x clip) 2))
      (assert (= (box-y clip) 2))
      (assert (= (box-width clip) 96))
      (assert (= (box-height clip) 8)))))

(defun test-long-selection-index (font)
  (let* ((text (make-string 4096 :initial-element #\W))
         (widget (lui.widgets:make-widget :kind :label :text text))
         (node (make-element :content widget
                             :box (make-box :width 100000 :height 40)))
         (renderer (make-renderer :font font))
         (face (lui.draw::widget-font renderer widget)))
    (assert (= 2048 (lui.draw::selection-index
                     renderer node (* 2048 (text-width face "W")) 1)))
    (assert (= 0 (lui.draw::selection-index renderer node -1 1)))
    (assert (= 4096 (lui.draw::selection-index renderer node 100000 1)))))

(defun test-flat-cells (font)
  (dolist (style '(:glass :motif :garnet :macos :qt))
    (let* ((paths nil) (glass 0) (texts nil)
           (renderer (make-renderer
                      :font font
                      :polygons (lambda (contours color alpha)
                                  (push (list contours color alpha) paths))
                      :clip (lambda (box) (declare (ignore box)))
                      :text (lambda (face text x y color)
                              (declare (ignore face x y))
                              (push (list text color) texts))
                      :backdrop-effect (lambda (&rest args)
                               (declare (ignore args)) (incf glass))))
           (context (make-context
                     :measure (lambda (widget width)
                                (measure-widget renderer widget width)))))
      (with-frame (context 200 80)
        (lui:with-toolkit (style)
          (lui:cell "2" (lui:opt :id :normal :width (fixed 100)))
          (lui:cell
            "3"
            (lui:opt :id :selected :width (fixed 100) :selected-p t))))
      (paint-frame renderer context)
      (assert (zerop glass))
      ;; Two flat fills and two hairlines; no bevel, stipple, or hard shadow.
      (assert (= 4 (length paths)))
      (assert (every (lambda (entry) (= 1 (third entry))) paths))
      (assert (every (lambda (entry)
                       (every (lambda (contour)
                                (= 4 (length (remove-duplicates
                                              contour :test #'equalp))))
                              (first entry)))
                     paths))
      (assert (member '("2" "#202430") texts :test #'equal))
      (assert (member '("3" "#202430") texts :test #'equal))
      (assert (find (getf (lui:toolkit-palette style) :selection) paths :key
            #'second :test #'equal)))))

(defun test-debug-highlight (font)
  (dolist (style '(:glass :motif :garnet :macos :qt))
    (let* ((paints nil)
           (renderer (make-renderer
                      :font font :clip (constantly nil)
                      :polygons (lambda (paths color alpha)
                                  (declare (ignore paths))
                                  (push (list color alpha) paints))))
           (context (make-context)))
      (with-frame (context 80 40)
        (emit (make-element
               :width (fixed 40) :height (fixed 20)
               :content (make-widget :kind :highlight :style style
                                     :accent "#ff8c00" :opacity 0.18))))
      (paint-frame renderer context)
      (assert (find '("#ff8c00" 0.18) paints :test #'equal))
      (assert (find '("#ff8c00" 1) paints :test #'equal))
      (assert (null (lui:widget-key (lui.frame::hit context 5 5)))))))

(defun test-button-text-centering (font)
  ;; A compact close glyph must stay centered in a generously sized control.
  (let* ((position nil)
         (renderer
           (make-renderer
            :font font :clip (lambda (box) (declare (ignore box)))
            :polygons (lambda (&rest args) (declare (ignore args)))
            :text (lambda (face text x y color)
                    (declare (ignore face color))
                    (when (string= text "×")
                      (setf position (cons x y))))))
         (context (make-context
                   :measure (lambda (widget width)
                              (measure-widget renderer widget width)))))
    (with-frame (context 200 100)
      (lui.glass:button
        "×"
        (lui:opt :id :close :width (fixed 80) :height (fixed 50))))
    (paint-frame renderer context)
    (let* ((node (gethash (lui:widget-id :close context)
                   (lui.frame::context-ids context)))
           (box (element-box node)))
      (assert position)
      (assert (near (+ (car position) (/ (text-width font "×") 2))
                    (+ (box-x box) (/ (box-width box) 2))))
      (assert (near (- (cdr position) (baseline font)
                       (- (/ (line-height font) 2)))
                    (+ (box-y box) (/ (box-height box) 2)))))))

(defun test-toolkit-geometry (font)
  ;; Asymmetric custom geometry must determine both wrapping and hit positions.
  (lui:register-toolkit
   :test-geometry :parent :glass
   :geometry (lambda (widget)
               (declare (ignore widget))
               (make-geometry :left 7 :right 19 :top 11 :bottom 5)))
  (let* ((positions nil)
         (renderer (make-renderer :font font
                                 :clip (lambda (box) (declare (ignore box)))
                                 :polygons (lambda (&rest args) (declare
                (ignore args)))
                                 :text (lambda (font text x y color)
                                         (declare (ignore font color))
                                         (push (list text x y) positions))))
         (widget (make-widget :kind :label :style :test-geometry :text "alpha beta"))
         (width (+ 26 (text-width font "alpha")))
         (box (make-box :x 20 :y 30 :width width :height 100))
         (node (make-element :content widget :box box :clip box)))
    (multiple-value-bind (w h) (measure-widget renderer widget width)
      (assert (near w width))
      (assert (near h (+ 16 (* 2 (line-height font))))))
    (let ((*context* (make-context)))
      (lui.draw::paint-widget renderer node))
    (assert (= 2 (length positions)))
    (assert (every (lambda (position) (= 27 (second position))) positions))
    (assert (= 6 (lui.draw::selection-index renderer node 27
                                           (+ 41 (line-height font) 1)))))
  ;; Fit-sized buttons and tabs need breathing room inside their frame band.
  (dolist (kind '(:button :tab))
    (let* ((text-x nil)
           (renderer (make-renderer :font font
                       :clip (lambda (box) (declare (ignore box)))
                       :polygons (lambda (&rest args) (declare (ignore args)))
                       :text (lambda (face text x y color)
                               (declare (ignore face text y color)) (setf
                  text-x x))))
           (widget (make-widget :kind kind :style :garnet :text "Push"))
           (label-width (text-width (widget-font renderer widget) "Push")))
      (multiple-value-bind (width height) (measure-widget renderer widget nil)
        (let* ((box (make-box :x 20 :y 30 :width width :height height))
               (node (make-element :content widget :box box :clip box))
               (*context* (make-context)))
          (lui.draw::paint-widget renderer node)
          (assert (near (- text-x (+ (box-x box) 4)) 6))
          (assert (near (- (+ (box-x box) width -8) (+ text-x label-width))
                6))))))
  ;; Garnet fields retain their narrower horizontal inset in shared measurement.
  (let ((widget (make-widget :kind :text-field :style :garnet :value "alpha beta")))
    (multiple-value-bind (w h)
        (measure-widget (make-renderer :font font) widget (+ 12 (text-width
              font "alpha")))
      (declare (ignore w))
      (assert (near h (+ 12 (* 2 (line-height font))))))))

(defun test-macos-surfaces (font)
  (dolist (palette '(:default :dark))
    (let* ((surfaces nil)
           (renderer (make-renderer :font font
                       :clip (lambda (&rest args) (declare (ignore args)))
                       :text (lambda (&rest args) (declare (ignore args)))
                       :polygons (lambda (&rest args) (declare (ignore args)))
                       :surface (lambda (box radius color alpha &optional
                  stroke)
                                  (declare (ignore alpha))
                                  (push (list (box-width box) (box-height box)
                    radius color stroke) surfaces))))
           (context (make-context :measure (lambda (widget width)
              (measure-widget renderer widget width)))))
      (with-frame (context 300 200)
        (lui:with-toolkit (:macos)
          (lui:with-palette (palette)
            (lui:checkbox "Checked" (lui:opt :id :check :value t))
            (lui:radio :one "Selected" (lui:opt :id :radio :value :one))
            (lui:slider (lui:opt :id :slider :value 0.5)))))
      (paint-frame renderer context)
      ;; Indicators use accent color; slider has a round thumb and no outer frame.
      (assert (find (if (eq palette :dark) "#79b8ff" "#007aff") surfaces
                    :key #'fourth :test #'equal))
      (assert (find-if (lambda (surface) (and (equal (subseq surface 0 3) '(14
                    14 7))
              (equal (fourth surface) "#ffffff") (null (fifth surface))))
            surfaces))
      (assert (notany (lambda (surface) (and (> (first surface) 30) (> (second
                    surface) 10))) surfaces)))))

(defun test-control-background-overrides (font)
  (dolist (palette '(:default :dark))
    (let* ((fills nil) (texts nil)
           (renderer (make-renderer :font font
                       :clip (lambda (&rest args) (declare (ignore args)))
                       :polygons (lambda (&rest args) (declare (ignore args)))
                       :text (lambda (face text x y color)
                               (declare (ignore face x y)) (push (list text
                    color) texts))
                       :surface (lambda (box radius color alpha &optional
                  stroke)
                                  (declare (ignore box radius alpha))
                                  (unless stroke (push color fills)))))
           (context (make-context :measure (lambda (widget width)
              (measure-widget renderer widget width)))))
      (with-frame (context 400 200)
        (lui:with-toolkit (:macos)
          (lui:with-palette (palette)
            (lui:button "Default" (lui:opt :id :default))
            (lui:button
              "Preview"
              (lui:opt
                :id :custom
                :background "#335d91"
                :foreground "#ffffff"))
            (lui:text-field
              (lui:opt
                :id :field
                :value "Custom field"
                :background "#81456d"
                :foreground "#ffffff")))))
      (paint-frame renderer context)
      (dolist (color (list "#335d91" "#81456d" (if (eq palette :dark) "#424954" "#ffffff")))
        (assert (member color fills :test #'equal)))
      (assert (member '("Preview" "#ffffff") texts :test #'equal)))))

(defun test-password-presentation (font)
  (let* ((painted nil) (copied nil)
         (renderer (make-renderer
                    :font font
                    :polygons (lambda (&rest args) (declare (ignore args)))
                    :text (lambda (font text &rest arguments)
                            (declare (ignore font arguments))
                            (push text painted))))
         (context (make-context
                   :copy (lambda (text) (setf copied text))
                   :measure (lambda (widget width)
                              (measure-widget renderer widget width)))))
    (with-frame (context 300 100)
      (lui:text-field (lui:opt :id :secret :value "secret界" :password-p t)))
    (let* ((nodes (lui.draw::selectable-nodes context))
           (node (aref nodes 0))
           (state (gethash (lui:widget-id :secret context) (context-state
                context))))
      (assert (string= "*******" (lui.draw::selection-text node)))
      (setf (context-focus context) (lui:widget-id :secret context)
            (edit-state-anchor state) 0)
      (lui.draw::copy-selection context nodes
                                (lui.draw::make-text-selection))
      (assert (string= "*******" copied))
      (let ((lui.frame:*context* context))
        (lui.draw::paint-text-field renderer node))
      (assert (equal '("*******") painted)))))

(defun test-typed-vector ()
  (let ((calls 0))
    (flet ((point () (cons (incf calls) 0)))
      (let ((points (lui.draw::typed-vector point (point) (point) (point))))
        (assert (= calls 3))
        (assert (typep points 'contour))
        (assert (equalp points #((1 . 0) (2 . 0) (3 . 0)))))))
  (assert (zerop (length (lui.draw::typed-vector point)))))

(defun run-tests ()
  (test-typed-vector)
  (test-shared-wrapping)
  (paint-text (make-renderer
               :text (lambda (&rest arguments)
                       (declare (ignore arguments))
                       (error "Empty labels must not call native text drawing.")))
              "" 0 0 "#000000")
  (let ((font (open-font)))
    (unwind-protect
         (progn
           (test-password-presentation font)
           (test-winding)
           (test-outlines font)
           (test-font-metrics font)
           (test-measurement font)
           (test-measurement-cache)
           (test-toolkit-geometry font)
           (test-edit-painting font)
           (test-panel-painting font)
           (test-custom-toolkit font)
           (test-button-feedback font)
           (test-button-text-centering font)
           (test-motif-states font)
           (test-macos-surfaces font)
           (test-control-background-overrides font)
           (test-font-faces)
           (test-garnet-states font)
           (test-pointer-selection font)
           (test-selection-regressions font)
           (test-long-selection-index font)
           (test-selection-clipping font)
           (test-flat-cells font)
           (test-debug-highlight font))
      (close-font font)))
  (format t "Native geometry, fonts, wrapping, focus, selection, and caret passed.~%")
  t)
