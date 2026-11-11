(defpackage #:lui.example.manual-demo
  (:use #:cl)
  (:export #:make-demo #:main))
(in-package #:lui.example.manual-demo)

(defun at (x y width height)
  "Place a widget explicitly, without flow sizing or sibling reservations."
  (let ((terminal (lui.frame:context-text-mode-p lui.frame:*context*)))
    (lui:opt :position (lui:make-point
                       :x (lui:units x)
                       :y (if terminal (floor y 2) (lui:units y)))
             :reserve-space-p nil
             :width (lui:fixed (lui:units width))
             :height (lui:fixed (if terminal 1 (lui:units height))))))

(defun make-demo ()
  "Return an independent UI whose widgets all have explicit surface positions."
  (let ((x 4) (y 22) (clicks 0) (enabled t))
    (lambda ()
      (lui:with-toolkit (:qt)
        (lui:label "Manual placement only" (at 2 1 60 3))
        (lui:label "Every widget has a position and fixed size."
                   (at 2 5 72 3))
        (lui:label "X" (at 2 9 3 3))
        (setf x (lui:slider
                 (append (at 6 9 60 3)
                         (lui:opt :value x :minimum 2 :maximum 48 :step 1))))
        (lui:label "Y" (at 2 13 3 3))
        (setf y (lui:slider
                 (append (at 6 13 60 3)
                         (lui:opt :value y :minimum 21 :maximum 36 :step 1))))
        (setf enabled
              (lui:checkbox "Enable button"
                (append (at 2 17 30 3) (lui:opt :value enabled))))
        (lui:label (format nil "Clicks: ~D" clicks) (at 35 17 30 3))
        (when (lui:button "Click me"
                (append (at x y 24 3) (lui:opt :disabled-p (not enabled))))
          (incf clicks))
        (lui:text-field
         (append (at x (+ y 4) 30 3)
                 (lui:opt :default-value "Move me; text stays")))))))

(defun main ()
  "Open the manual-only demo on the selected backend."
  (lui:run (make-demo) :title "LUI manual placement"))
