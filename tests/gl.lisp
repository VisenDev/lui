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


(defun pixel-color (x y)
  (cffi:with-foreign-object (pixel :uint8 4)
    (cffi:foreign-funcall "glReadPixels"
                          :int x :int (- 519 y) :int 1 :int 1
                          :uint #x1908 :uint #x1401 :pointer pixel :void)
    (loop :for channel :below 4
          :collect (cffi:mem-aref pixel :uint8 channel))))

(defun test-opaque-compositing (gpu renderer context)
  (cffi:with-foreign-object (bits :int)
    (cffi:foreign-funcall "glGetIntegerv" :uint #x0d55 :pointer bits :void)
    ;; An RGB-only target would hide destination-alpha regressions.
    (assert (>= (cffi:mem-ref bits :int) 8)))
  (flet ((button ()
        (lui.motif:button
          "Hover"
          (lui:opt :id :alpha :width (fixed 160) :height (fixed 50)))))
    (with-frame (context 720 520) (button))
    (begin-gpu-frame gpu)
    (paint-frame renderer context)
    (let ((normal (pixel-color 130 25)))
      (with-frame (context 720 520
                           :events (list (make-event :kind :move
                                                     :x 130 :y 25)))
        (button))
      (assert (eq :alpha (lui:widget-key (context-hover context))))
      (begin-gpu-frame gpu)
      (paint-frame renderer context)
      (let ((hover (pixel-color 130 25)))
        (assert (> (first hover) (first normal)))
        (assert (= 255 (fourth hover))))))
  (with-frame (context 720 520)
    (lui.glass:button
      "Glass"
      (lui:opt
        :id :glass
        :background "#c00000"
        :opacity 0.35
        :width (fixed 160)
        :height (fixed 50))))
  (begin-gpu-frame gpu)
  (funcall (renderer-clip renderer)
           (make-box :width 720 :height 520))
  (funcall (renderer-polygons renderer)
           '#(#((0 . 0) (720 . 0) (720 . 520) (0 . 520))) "#204060" 1)
  (paint-frame renderer context)
  (let ((glass (pixel-color 130 25)))
    ;; Glass still blends with the app's backdrop, while the window stays opaque.
    (assert (< 32 (first glass) 190))
    (assert (> (third glass) 30))
    (assert (= 255 (fourth glass))))
  (assert (= 255 (fourth (pixel-color 600 450))))
  (format t "Opaque window alpha survives Motif hover and Glass tint.~%"))

(defun test-backdrop-frost (gpu renderer context)
  (labels ((contrast (frost opacity)
             (with-frame (context 720 520)
               (column (:width (grow) :height (grow))
                 (lui.glass:panel (lui:opt :floating-p t :offset-x 40
                  :offset-y 40
                :width (fixed 200) :height (fixed 120)
                :background "#606060" :opacity opacity
                                           :frost frost :radius 0))))
             (begin-gpu-frame gpu)
             (funcall (renderer-clip renderer)
                      (make-box :width 720 :height 520))
             (dotimes (stripe 90)
               (let ((x (* stripe 8)))
                 (funcall (renderer-polygons renderer)
                          (vector (vector (cons x 0) (cons (+ x 8) 0)
                                      (cons (+ x 8) 520) (cons x 520)))
                          (if (evenp stripe) "#000000" "#ffffff") 1)))
             (paint-frame renderer context)
             (let ((samples (loop :for x :from 80 :below 144
                                  :collect (first (pixel-color x 100)))))
               (assert (= 255 (fourth (pixel-color 100 100))))
               (- (reduce #'max samples) (reduce #'min samples)))))
    (let ((sharp (contrast 0 0.2))
          (frosted (contrast 24 0.2))
          (opaque (contrast 0 0.85)))
      (assert (> sharp 150))
      (assert (< frosted (* sharp 0.7)))
      (assert (< opaque (* sharp 0.3)))
      (format t "Glass frost smooths backdrop pixels; opacity controls tint.~%"))))

(defun test-translated-geometry-cache (gpu renderer)
  (lui.gl::clear-geometry gpu)
  (let ((builds (lui.gl::gpu-geometry-builds gpu)))
    (flet ((cells (color)
             (begin-gpu-frame gpu)
             (funcall (renderer-clip renderer)
                      (make-box :width 720 :height 520))
             (dotimes (index 600)
               (let* ((x (* 20 (mod index 30)))
                      (y (* 20 (floor index 30)))
                      (outer (rounded-polygon
                              (make-box :x x :y y :width 10 :height 10) 0))
                      (inner (rounded-polygon
                              (make-box :x (1+ x) :y (1+ y)
                                        :width 8 :height 8) 0)))
                 (funcall (renderer-polygons renderer) (vector outer) color 1)
                 (funcall (renderer-polygons renderer)
                          (vector outer (reverse inner)) "#20c040" 1)))))
      (cells "#c04020")
      ;; More than 512 positions must reuse two shapes, not flush the cache.
      (assert (= (+ builds 2) (lui.gl::gpu-geometry-builds gpu)))
      (assert (= 2 (hash-table-count (lui.gl::gpu-geometry gpu))))
      (dolist (point '((5 5) (25 5) (585 385)))
        (let ((pixel (apply #'pixel-color point)))
          (assert (> (first pixel) 180))
          (assert (< (third pixel) 40))))
      (assert (> (second (pixel-color 0 5)) 180))
      (assert (< (first (pixel-color 15 5)) 50))
      (cells "#2040c0")
      (assert (= (+ builds 2) (lui.gl::gpu-geometry-builds gpu)))
      (assert (> (third (pixel-color 585 385)) 180))
      (assert (< (first (pixel-color 585 385)) 40))))
  (format t "Translated cell geometry stays cached across 600 positions.~%"))

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
           '#(#((0 . 0) (40 . 0) (40 . 40) (0 . 40))) "#ffffff" 1)
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
       (gallery (lui.example:make-gallery))
       (*unit* 8))
  (unwind-protect
       (progn
         (test-opaque-compositing gpu renderer context)
         (test-fractional-resolution gpu renderer)
         (test-backdrop-frost gpu renderer context)
         (test-translated-geometry-cache gpu renderer)
         (with-frame (context 720 520) (lui.example:draw gallery))
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
