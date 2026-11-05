(defpackage #:lui.tests.gl
  (:use #:cl #:lui #:lui.font #:lui.draw #:lui.frame #:lui.gl))
(in-package #:lui.tests.gl)

(defun capture-frame ()
  (let ((pixels (cffi:foreign-alloc :uint8 :count (* 720 520 4))))
    (unwind-protect
         (progn
           (cffi:foreign-funcall "glReadPixels"
                                 :int 0 :int 0 :int 720 :int 520
                                 :uint #x1908 :uint #x1401
                                 :pointer pixels :void)
           (let ((bright 0))
             (dotimes (i (* 720 520))
               (when (> (cffi:mem-aref pixels :uint8 (* i 4)) 200)
                 (incf bright)))
             (assert (> bright 100)))
           (with-open-file (out "build/gl.ppm" :direction :output
                               :if-exists :supersede
                               :element-type '(unsigned-byte 8))
             (map nil (lambda (char) (write-byte (char-code char) out))
                  (format nil "P6~%720 520~%255~%"))
             (loop :for y :downfrom 519 :to 0
                   :do (dotimes (x 720)
                         (dotimes (channel 3)
                           (write-byte
                            (cffi:mem-aref pixels :uint8
                                           (+ (* 4 (+ (* y 720) x))
                                              channel))
                            out))))))
      (cffi:foreign-free pixels))))

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
         (capture-frame)
         (present-gpu gpu)
         (format t "EGL/OpenGL shared demo and glass shader passed.~%"))
    (close-gpu gpu)
    (close-font font)))
