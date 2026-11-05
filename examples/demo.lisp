(defpackage #:lui.example
  (:use #:cl #:lui #:lui.layout #:lui.frame)
  (:export #:main #:draw))

(in-package #:lui.example)

(defvar *name* "Common Lisp")

(defvar *volume* 0.4)

(defvar *enabled* t)

(defvar *count* 0)

(defun draw ()
  (column (:width (grow) :padding (units 2) :gap (units 2))
    (lui.glass:label "LUI — one application, every backend")
    (setf *name* (lui.glass:text-field :name *name* :width (grow)))
    (setf *volume* (lui.glass:slider :volume *volume* :width (grow)))
    (setf *enabled* (lui.motif:checkbox :enabled *enabled* "Enabled"))
    (row (:gap (units 2))
      (when (lui.glass:button :hello "Say hello") (incf *count*))
      (when (lui.motif:button :reset "Reset") (setf *count* 0)))
    (lui.glass:label (format nil "Hello ~A (~D)" *name* *count*))))

(defun main ()
  (run #'draw :title "LUI widget collections"))
