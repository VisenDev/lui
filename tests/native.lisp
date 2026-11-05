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

(defun run-tests ()
  (let ((font (open-font)))
    (unwind-protect
         (progn
           (test-winding)
           (test-outlines font)
           (test-font-metrics font)
           (test-measurement font)
           (test-edit-painting font)
           (test-panel-painting font))
      (close-font font)))
  (format t "Native geometry, fonts, wrapping, focus, selection, and caret passed.~%")
  t)
