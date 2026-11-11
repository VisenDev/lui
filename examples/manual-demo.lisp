(defpackage #:lui.example.manual-demo
  (:use #:cl)
  (:export #:make-demo #:main))
(in-package #:lui.example.manual-demo)

(defun make-demo ()
  "Return a manually positioned UI; widgets measure their own text and height."
  (let ((x 4) (y 17) (clicks 0) (enabled t))
    (lambda ()
      (lui:with-toolkit (:qt)
        (lui:label "Manual placement only"
          (lui:opt :position (lui:make-point :x (lui:units 2)
                                            :y (lui:units 1))))
        (lui:label "Explicit positions; heights fit the text."
          (lui:opt :position (lui:make-point :x (lui:units 2)
                                            :y (lui:units 4))))
        (lui:label "X"
          (lui:opt :position (lui:make-point :x (lui:units 2)
                                            :y (lui:units 7))))
        (setf x
              (lui:slider
               (lui:opt :position (lui:make-point :x (lui:units 6)
                                                 :y (lui:units 7))
                        :width (lui:fixed (lui:units 28))
                        :value x :minimum 2 :maximum 48 :step 1)))
        (lui:label "Y"
          (lui:opt :position (lui:make-point :x (lui:units 38)
                                            :y (lui:units 7))))
        (setf y
              (lui:slider
               (lui:opt :position (lui:make-point :x (lui:units 42)
                                                 :y (lui:units 7))
                        :width (lui:fixed (lui:units 28))
                        :value y :minimum 16 :maximum 24 :step 1)))
        (setf enabled
              (lui:checkbox "Enable button"
                (lui:opt :position (lui:make-point :x (lui:units 2)
                                                  :y (lui:units 12))
                         :value enabled)))
        (lui:label (format nil "Clicks: ~D" clicks)
          (lui:opt :position (lui:make-point :x (lui:units 35)
                                            :y (lui:units 12))))
        (when (lui:button "Click me"
                (lui:opt :position (lui:make-point :x (lui:units x)
                                                  :y (lui:units y))
                        :width (lui:fixed (lui:units 24))
                         :disabled-p (not enabled)))
          (incf clicks))
        (lui:text-field
         (lui:opt :position (lui:make-point :x (lui:units x)
                                           :y (lui:units (+ y 5)))
                  :width (lui:fixed (lui:units 30))
                  :default-value "Move me; text stays"))))))

(defun main ()
  "Open the manual-only demo on the selected backend."
  (lui:run (make-demo) :title "LUI manual placement"))
