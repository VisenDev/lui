(defpackage #:lui.tests.gl
  (:use #:cl #:lui #:lui.font #:lui.draw #:lui.frame #:lui.gl #:lui.layout))
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


(defun test-fractional-resolution (gpu renderer)
  (setf (gpu-logical-width gpu) 480
        (gpu-logical-height gpu) (/ 1040 3))
  (begin-gpu-frame gpu)
  (funcall (renderer-clip renderer)
           (make-box :x 10 :y 10 :width 20 :height 20))
  (cffi:with-foreign-object (clip :int 4)
    (cffi:foreign-funcall "glGetIntegerv" :uint #x0c10 :pointer clip :void)
    (assert (equal '(15 475 30 30)
                   (loop :for i :below 4
                         :collect (cffi:mem-aref clip :int i)))))
  (funcall (renderer-polygons renderer)
           '(((0 . 0) (40 . 0) (40 . 40) (0 . 40))) "#ffffff" 1)
  (cffi:with-foreign-object (pixel :uint8 4)
    (flet ((red-at (x)
             (cffi:foreign-funcall "glReadPixels"
                                   :int x :int 490 :int 1 :int 1
                                   :uint #x1908 :uint #x1401
                                   :pointer pixel :void)
             (cffi:mem-aref pixel :uint8)))
      (assert (> (red-at 16) 250))
      (assert (< (red-at 12) 50))
      (assert (< (red-at 46) 50))))
  (setf (gpu-logical-width gpu) 720 (gpu-logical-height gpu) 520))

(let* ((font (open-font))
       (gpu (open-gpu nil nil font 720 520))
       (renderer (gpu-renderer gpu))
       (context (make-context
                 :measure (lambda (widget width)
                            (measure-widget renderer widget width))))
       (*unit* 8))
  (unwind-protect
       (progn
         (test-fractional-resolution gpu renderer)
         (with-frame (context 720 520) (lui.example:draw))
         (begin-gpu-frame gpu)
         (paint-frame renderer context)
         (assert (zerop (cffi:foreign-funcall "glGetError" :uint)))
         (capture-frame)
         (let ((builds (lui.gl::gpu-geometry-builds gpu)))
           (begin-gpu-frame gpu)
           (paint-frame renderer context)
           (assert (= builds (lui.gl::gpu-geometry-builds gpu))))
         (present-gpu gpu)
         (format t "EGL/OpenGL shared demo and glass shader passed.~%"))
    (close-gpu gpu)
    (close-font font)))
