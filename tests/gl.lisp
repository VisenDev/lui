(defpackage #:%lui.tests.gl
  (:use #:cl #:lui #:lui.font #:lui.draw #:%lui.frame #:%lui.gl #:%lui.layout))
(in-package #:%lui.tests.gl)

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
    (%paint-frame renderer context)
    (let ((normal (pixel-color 130 25)))
      (with-frame (context 720 520
                           :events (list (make-event :kind :move
                                                     :x 130 :y 25)))
        (button))
      (assert (eq :alpha (lui:widget-key (context-hover context))))
      (begin-gpu-frame gpu)
      (%paint-frame renderer context)
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
  (%paint-frame renderer context)
  (let ((glass (pixel-color 130 25)))
    ;; Glass still blends with the app's backdrop, while the window stays opaque.
    (assert (< 32 (first glass) 190))
    (assert (> (third glass) 30))
    (assert (= 255 (fourth glass))))
  (assert (= 255 (fourth (pixel-color 600 450))))
  (format t "Opaque window alpha survives Motif hover and Glass tint.~%"))

(defun test-backdrop-frost (gpu renderer context)
  ;; No built-in toolkit parent: the backdrop is an independent capability.
  (lui.toolkit:register-toolkit :test-backdrop
    :geometry (lambda (widget)
                (declare (ignore widget)) (lui.draw:make-geometry))
    :paint (lambda (target node)
             (let ((widget (element-content node)) (box (element-box node)))
               (funcall (renderer-backdrop-effect target)
                        box 0 (%lui.widgets:widget-frost widget))
               (shape target box 0 (%lui.widgets:widget-background widget)
                      (%lui.widgets:widget-opacity widget)))))
  (labels ((contrast (frost opacity)
             (with-frame (context 720 520)
               (column (lui:opt :width (grow) :height (grow))
                 (lui:with-toolkit (:test-backdrop)
                   (lui:panel
                    (lui:opt :position :absolute :offset-x 40 :offset-y 40
                             :width (fixed 200) :height (fixed 120)
                             :background "#606060" :opacity opacity
                             :frost frost :radius 0)))))
             (begin-gpu-frame gpu)
             (funcall (renderer-clip renderer)
                      (make-box :width 720 :height 520))
             (dotimes (stripe 90)
               (let ((x (* stripe 8)))
                 (funcall (renderer-polygons renderer)
                          (vector (vector (cons x 0) (cons (+ x 8) 0)
                                      (cons (+ x 8) 520) (cons x 520)))
                          (if (evenp stripe) "#000000" "#ffffff") 1)))
             (%paint-frame renderer context)
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
      (format t "Custom toolkit backdrop blurs pixels; opacity controls tint.~%"))))

(defun test-translated-geometry-cache (gpu renderer)
  (%lui.gl::clear-geometry gpu)
  (let ((builds (%lui.gl::gpu-geometry-builds gpu)))
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
      (assert (= (+ builds 2) (%lui.gl::gpu-geometry-builds gpu)))
      (assert (= 2 (hash-table-count (%lui.gl::gpu-geometry gpu))))
      (dolist (point '((5 5) (25 5) (585 385)))
        (let ((pixel (apply #'pixel-color point)))
          (assert (> (first pixel) 180))
          (assert (< (third pixel) 40))))
      (assert (> (second (pixel-color 0 5)) 180))
      (assert (< (first (pixel-color 15 5)) 50))
      (cells "#2040c0")
      (assert (= (+ builds 2) (%lui.gl::gpu-geometry-builds gpu)))
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

(defun frame-pixels ()
  (let* ((count (* 720 520 4))
         (pixels (make-array count :element-type '(unsigned-byte 8))))
    (cffi:with-pointer-to-vector-data (data pixels)
      (cffi:foreign-funcall "glReadPixels"
                            :int 0 :int 0 :int 720 :int 520
                            :uint #x1908 :uint #x1401 :pointer data :void))
    pixels))

(defun test-backdrop-cache (gpu renderer)
  (let ((text (copy-seq "CASE"))
        (color (copy-seq "#20c040"))
        (contours (vector (vector (cons 35 40) (cons 180 40)
                                  (cons 180 85) (cons 35 85))))
        (extra t)
        (clip-width 240))
    (labels ((scene ()
               (begin-gpu-frame gpu)
               (funcall (renderer-clip renderer)
                        (make-box :width clip-width :height 130))
               (when extra
                 (funcall (renderer-polygons renderer) contours color 1))
               (funcall (renderer-text renderer)
                        (renderer-font renderer) text 40 70 "#ffffff")
               (dolist (x '(30 400 185 60))
                 (let ((box (make-box :x x :y 30 :width 160 :height 80)))
                   (funcall (renderer-clip renderer)
                            (intersect-boxes
                             box (make-box :width 620 :height 85)))
                   (funcall (renderer-backdrop-effect renderer) box 12 18)
                   (shape renderer box 12 "#405080" 0.3)))
               (frame-pixels))
             (check ()
               ;; Every warmed frame must match the same scene with no history.
               (let ((cached (scene)))
                 (%lui.gl::clear-backdrops gpu)
                 (assert (equalp cached (scene)))
                 (let ((revision (%lui.gl::gpu-backdrop-revision gpu)))
                   (assert (equalp cached (scene)))
                   (assert (= revision
                              (%lui.gl::gpu-backdrop-revision gpu))))
                 ;; Regional texture coordinates must preserve the original
                 ;; full-frame sampling, apart from one channel's rounding bit.
                 (let ((area (symbol-function '%lui.gl::backdrop-area)))
                   (unwind-protect
                        (progn
                          (setf (symbol-function '%lui.gl::backdrop-area)
                                (lambda (target box frost)
                                  (declare (ignore box frost))
                                  (make-box :width (gpu-width target)
                                            :height (gpu-height target))))
                          (assert (every (lambda (a b) (<= (abs (- a b)) 1))
                                         cached (scene))))
                     (setf (symbol-function '%lui.gl::backdrop-area)
                           area))))))
      (check)
      ;; Mutate the same input objects to catch aliases in retained cache keys.
      (setf (char text 0) #\c)
      (check)
      (setf (char color 1) #\e)
      (check)
      (incf (car (aref (aref contours 0) 0)) 15)
      (check)
      (setf extra nil)
      (check)
      (setf clip-width 110)
      (check)
      (setf (gpu-logical-width gpu) 480
            (gpu-logical-height gpu) (/ 1040 3))
      (check)
      (setf (gpu-width gpu) 360 (gpu-height gpu) 260)
      (check)
      (setf (gpu-width gpu) 720 (gpu-height gpu) 520
            (gpu-logical-width gpu) 720 (gpu-logical-height gpu) 520)
      (check)))
  (format t "Cached backdrops match fresh text, geometry, clip and resize draws.~%"))

(defun test-backdrop-cache-bounds (gpu)
  (%lui.gl::clear-backdrops gpu)
  (let ((area (make-box :width 512 :height 512)))
    ;; Each region is 1 MiB; exceeding the budget must release old textures.
    (dotimes (index 33)
      (%lui.gl::allocate-backdrop gpu area (list index)))
    (assert (<= (%lui.gl::gpu-backdrop-bytes gpu) (* 32 1024 1024))))
  (let ((textures
          (loop :for entry :being :the :hash-values
                  :of (%lui.gl::gpu-backdrops gpu)
                :collect (%lui.gl::gl-backdrop-texture entry))))
    (%lui.gl::clear-backdrops gpu)
    (dolist (texture textures)
      (assert (zerop (cffi:foreign-funcall "glIsTexture"
                                         :uint texture :unsigned-char)))))
  (assert (zerop (%lui.gl::gpu-backdrop-bytes gpu)))
  (assert (zerop (hash-table-count (%lui.gl::gpu-backdrops gpu))))
  (format t "Backdrop texture storage is bounded and released.~%"))

(defun test-gallery-backdrop-cache (gpu renderer context gallery)
  (setf (%lui.example.demo::gallery-toolkit gallery) :glass)
  (dolist (page '(:controls :editing :layout :scroll :styles :menus))
    (setf (%lui.example.demo::gallery-page gallery) page)
    (dolist (point '((20 120) (180 120) (100 210) (500 210)))
      (with-frame (context 720 520
                   :events (vector (make-event :kind :move
                                                :x (first point)
                                                :y (second point))))
        (%lui.example.demo:draw gallery))
      (begin-gpu-frame gpu)
      (%paint-frame renderer context)
      (let ((expected (frame-pixels)))
        (%lui.gl::clear-backdrops gpu)
        (begin-gpu-frame gpu)
        (%paint-frame renderer context)
        (assert (equalp expected (frame-pixels))))))
  (format t "Glass gallery pages match cached and fresh rendering.~%"))

(let* ((font (open-font))
       (gpu (open-gpu nil nil font 720 520))
       (renderer (gpu-renderer gpu))
       (context (make-context
                 :measure (lambda (widget width)
                            (%measure-widget renderer widget width))))
       (gallery (%lui.example.demo:make-gallery))
       (*unit* 8))
  (unwind-protect
       (progn
         (test-opaque-compositing gpu renderer context)
         (test-fractional-resolution gpu renderer)
         (test-backdrop-frost gpu renderer context)
         (test-backdrop-cache gpu renderer)
         (test-backdrop-cache-bounds gpu)
         (test-gallery-backdrop-cache gpu renderer context gallery)
         (test-translated-geometry-cache gpu renderer)
         (with-frame (context 720 520) (%lui.example.demo:draw gallery))
         (begin-gpu-frame gpu)
         (%paint-frame renderer context)
         (assert (zerop (cffi:foreign-funcall "glGetError" :uint)))
         (capture-frame)
         (let ((builds (%lui.gl::gpu-geometry-builds gpu)))
           (begin-gpu-frame gpu)
           (%paint-frame renderer context)
           (assert (= builds (%lui.gl::gpu-geometry-builds gpu))))
         (present-gpu gpu)
         (format t "EGL/OpenGL shared demo and glass shader passed.~%"))
    (close-gpu gpu)
    (close-font font)))
