(defpackage #:lui.tests.gl
  (:use #:cl #:lui #:lui.font #:lui.draw #:lui.frame #:lui.gl))
(in-package #:lui.tests.gl)

(let* ((font (open-font))
       (gpu (open-gpu nil nil font 720 520))
       (renderer (gpu-renderer gpu))
       (context (make-context
                 :measure (lambda (widget width)
                            (measure-widget renderer widget width))))
       (*unit* 8))
  (unwind-protect
       (progn
         (with-frame (context 720 520) (lui.example:draw))
         (begin-gpu-frame gpu)
         (paint-frame renderer context)
         (assert (zerop (cffi:foreign-funcall "glGetError" :uint)))
         (present-gpu gpu)
         (format t "EGL/OpenGL shared demo and glass shader passed.~%"))
    (close-gpu gpu)
    (close-font font)))
