(defpackage #:lui.tests.widgets
  (:use #:cl #:lui.layout #:lui.frame #:lui.terminal)
  (:export #:run-tests))

(in-package #:lui.tests.widgets)

(defun run-tests ()
  (let
    ((context (make-terminal-context)) (slider 0.0) (checked nil)
      (text "abc"))
    (flet
      ((draw ()
          (setf slider
            (lui.glass:slider :slider slider :width (fixed 20)))
          (setf checked (lui.glass:checkbox :check checked "Check"))
          (setf text (lui.motif:text-field :text text))))
      (with-frame (context 30 10) (draw))
      ;; Press/move/release can all arrive before the next UI invocation.
      (with-frame
        (context 30 10 :events
          (list (make-event :kind :press :x 2 :y 0)
            (make-event :kind :move :x 16 :y 0)
            (make-event :kind :release :x 16 :y 0))) (draw))
      (assert (< (abs (- slider 0.8)) 0.001))
      (with-frame
        (context 30 10 :events (list (make-event :kind :move :x 1 :y 0)))
        (draw))
      (assert (< (abs (- slider 0.8)) 0.001))
      (with-frame
        (context 30 10 :events
          (list (make-event :kind :change :id :check :value t)
            (make-event :kind :key :id :text :key :select-all)
            (make-event :kind :text :id :text :value "replacement")))
        (draw))
      (assert checked)
      (assert (string= text "replacement"))))
  (let ((context (make-terminal-context)))
    (flet
      ((draw ()
          (column
            (:id :scroll :width (fixed 10) :height (fixed 2) :scroll-p
              t) (lui.glass:label "first") (lui.glass:label "second")
            (lui.glass:label "third"))))
      (with-frame (context 10 3) (draw))
      (assert (not (search "third" (render-terminal context))))
      (with-frame
        (context 10 3 :events
          (list (make-event :kind :scroll :x 1 :y 1 :value 1))) (draw))
      (assert (search "second" (render-terminal context)))
      (assert (search "third" (render-terminal context)))
      (assert (not (search "first" (render-terminal context))))))
  (format t "Widget interaction and scrolling checks passed.~%")
  t)
