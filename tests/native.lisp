(defpackage #:lui.tests.native
  (:use #:cl #:lui.layout #:lui.frame #:lui.widgets #:lui.font #:lui.draw)
  (:export #:run-tests))

(in-package #:lui.tests.native)

(defun near (a b &optional (epsilon 0.001f0))
  (< (abs (- a b)) epsilon))

(defun rectangle (x y width height)
  (list (cons x y) (cons (+ x width) y)
        (cons (+ x width) (+ y height)) (cons x (+ y height))))

(defun polygon-area (points)
  (/ (abs (loop :for tail :on points
                :for a := (car tail)
                :for b := (or (cadr tail) (car points))
                :sum (- (* (car a) (cdr b)) (* (car b) (cdr a)))))
     2))

(defun filled-area (contours)
  (let ((area 0))
    (trapezoids contours
                (lambda (points) (incf area (polygon-area points))))
    area))

(defun test-winding ()
  (let ((outer (rectangle 0 0 10 10))
        (inner (rectangle 3 3 4 4)))
    (assert (= 100 (filled-area (list outer inner))))
    (assert (= 84 (filled-area (list outer (reverse inner)))))
    (assert (= 84 (filled-area (list (reverse outer) inner))))
    (assert (= 104 (filled-area
                   (list outer (rectangle 20 20 2 2))))))
  (assert (= 12 (filled-area
                 '(((0 . 0) (4 . 0) (4 . 2)
                    (2 . 2) (2 . 4) (0 . 4))))))
  (assert (zerop (filled-area '(nil ((1 . 1)) ((1 . 1) (3 . 1))))))
  (let* ((box (make-box :x 10 :y 20 :width 40 :height 20))
         (rounded (rounded-polygon box 100)))
    (assert (= 36 (length rounded)))
    (assert (every (lambda (point)
                     (and (<= 10 (car point) 50)
                          (<= 20 (cdr point) 40)))
                   rounded))
    (assert (< 600 (polygon-area rounded) 800))))

(defun test-outlines (font)
  (let ((curves 0)
        (contours (glyph-polygons font #\O)))
    (assert (>= (length contours) 2))
    (zpb-ttf:do-contours
        (contour (zpb-ttf:find-glyph #\O (font-loader font)))
      (let ((samples (pop contours)))
        (zpb-ttf:do-contour-segments (p0 p1 p2) contour
          (if p1
              (progn
                (incf curves)
                ;; A quadratic's midpoint is 1/4 P0 + 1/2 P1 + 1/4 P2.
                (let ((middle (nth 5 samples)))
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
                (assert (near (car (nth 11 samples)) (zpb-ttf:x p2)))
                (assert (near (cdr (nth 11 samples)) (zpb-ttf:y p2)))
                (setf samples (nthcdr 12 samples)))
              (progn
                (assert (= (caar samples) (zpb-ttf:x p2)))
                (assert (= (cdar samples) (zpb-ttf:y p2)))
                (pop samples))))
        (assert (null samples))))
    (assert (plusp curves))
    (assert (eq (glyph-polygons font #\O) (glyph-polygons font #\O)))
    (assert (null (glyph-polygons font #\Space)))))

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
      (assert (equal '("alpha beta" "gamma")
                     (wrap-text font "alpha beta gamma" width)))
      (assert (equal '("unbreakable")
                     (wrap-text font "unbreakable" 1))))
    (assert (equal '("a" "" "b" "")
                   (wrap-text font (format nil "a~%~%b~%") nil)))))

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

(defun bounds (contours)
  (let ((points (apply #'append contours)))
    (list (reduce #'min points :key #'car)
          (reduce #'min points :key #'cdr)
          (- (reduce #'max points :key #'car)
             (reduce #'min points :key #'car))
          (- (reduce #'max points :key #'cdr)
             (reduce #'min points :key #'cdr)))))

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
      (lui.glass:text-field :name "AV" :width (fixed 180)
                            :height (fixed 40) :accent "#ff5500"))
    (let* ((node (aref (element-children (context-root context)) 0))
           (state (gethash :name (context-state context))))
      (setf (context-focus context) :name
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
                          :clip (lambda (box) (declare (ignore box)))))
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
      (lui.glass:button :action "Action" :accent "#ff5500"))
    (flet ((paint ()
             (setf calls nil)
             (paint-frame renderer context)))
      (setf (context-focus context) :action
            (context-hover context) :action)
      (paint)
      (assert (member '("#ffffff" 0.14f0 1) calls :test #'equal))
      (assert (not (member '("#ff5500" 1 2) calls :test #'equal)))
      (setf (context-active context) :action)
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
      (lui.motif:button :disabled "Disabled" :disabled-p t))
    (paint-frame renderer context)
    (assert (find "#777777" calls :key #'second :test #'equal))
    (assert (find "#989898" calls :key #'second :test #'equal))
    (with-frame (context 240 120)
      (lui.motif:checkbox :toggle nil "Enabled"))
    (setf (context-hover context) :toggle calls nil)
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
           (assert (not (equal (glyph-polygons normal #\W)
                               (glyph-polygons bold #\W))))
           (let ((saw-font nil))
             (with-frame (context 240 80)
               (lui.garnet:button
                :custom "Selected face" :font-size 20
                :painter (lambda (renderer node)
                           (declare (ignore node))
                           (setf saw-font
                                 (and (eq bold (renderer-font renderer))
                                      (= 20 (font-size bold)))))))
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
            :glass (lambda (&rest arguments)
                     (declare (ignore arguments)) (incf glass-calls))
            :text (lambda (face text x y color)
                    (push (list text x y color face) texts))
            :polygons (lambda (contours color alpha)
                        (push (list contours color alpha) calls))))
         (context (make-context
                   :measure (lambda (widget width)
                              (measure-widget renderer widget width)))))
    (with-frame (context 400 400)
      (lui.garnet:panel (:id :window :width (grow) :height (grow)
                        :padding 8 :gap 8)
        (lui.garnet:label "Garnet")
        (lui.garnet:button :push "Push")
        (lui.garnet:button :disabled "Disabled" :disabled-p t)
        (lui.garnet:checkbox :check t "Checked")
        (lui.garnet:slider :range 0.5)
        (lui.garnet:text-field :text "Edit")
        (lui.garnet:tab :tab "Selected" :selected-p t)))
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
        (dolist (square pattern)
          (assert (equal '(1 1) (cddr (bounds (list square))))))
        (paint)
        (assert (find pattern calls :key #'first :test #'eq))
        (setf (context-hover context) :disabled)
        (paint)
        (assert (= count (length calls)))
        (setf (context-hover context) :push
              (context-active context) :push)
        (paint)
        (let ((pressed (find "Push" texts :key #'first :test #'equal)))
          (assert (near (+ 4 (second push-text)) (second pressed)))
          (assert (near (+ 4 (third push-text)) (third pressed)))))
      ;; Checkmarks are two crossed polygon strokes, not a font-dependent glyph.
      (assert (find-if
               (lambda (call)
                 (and (= 2 (length (first call)))
                      (equal '(10 10) (cddr (bounds (first call))))))
               calls)))))

(defun run-tests ()
  (let ((font (open-font)))
    (unwind-protect
         (progn
           (test-winding)
           (test-outlines font)
           (test-font-metrics font)
           (test-measurement font)
           (test-edit-painting font)
           (test-panel-painting font)
           (test-button-feedback font)
           (test-motif-states font)
           (test-font-faces)
           (test-garnet-states font))
      (close-font font)))
  (format t "Native geometry, fonts, wrapping, focus, selection, and caret passed.~%")
  t)
