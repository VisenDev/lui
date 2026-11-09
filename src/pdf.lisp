(defpackage #:lui.pdf
  (:use #:cl #:lui.fn #:lui.frame #:lui.layout #:lui.draw)
  (:export #:render-pdf #:*pdf-output*))

(in-package #:lui.pdf)

(lui::expose-api render-pdf *pdf-output*)

(defvar *pdf-output* #p"lui.pdf" "Destination used by the :PDF backend of LUI:RUN.")

(fn (pdf-renderer renderer) ((font lui.font:font))
  (let (clip)
    (make-renderer
     :font font
     :clip (lambda (box) (setf clip box))
     :polygons
     (lambda (contours color alpha)
       (when (plusp (length contours))
         (pdf:with-saved-state
           (when clip
             (pdf:basic-rect (box-x clip) (box-y clip)
                             (box-width clip) (box-height clip))
             (pdf:clip-path)
             (pdf:end-path-no-op))
           (let ((rgba (color-components color alpha)))
             (pdf:set-rgb-fill (aref rgba 0) (aref rgba 1) (aref rgba 2))
             (unless (= (aref rgba 3) 1)
               (pdf:set-fill-transparency (aref rgba 3))))
           (loop :for points :across contours :do
             (when (plusp (length points))
               (pdf:move-to (car (aref points 0)) (cdr (aref points 0)))
               (loop :for i :from 1 :below (length points) :for point := (aref points i) :do
                 (pdf:line-to (car point) (cdr point)))
               (pdf:close-path)))
           (pdf:fill-path)))))))

(fn (render-pdf pathname) ((draw function) pathname &key ((width real) 612)
                         ((height real) 792) ((title string) "LUI")
                                      (background "#1f2430"))
  "Render DRAW once to PATHNAME and return the pathname. Sizes are PDF points."
  (assert (and (plusp width) (plusp height)))
  (let* ((lui:*unit* 8)
         (font (lui.font:open-font)))
    (unwind-protect
         (let* ((renderer (pdf-renderer font))
                (context (make-context :measure
                                       (lambda (widget available)
                                         (measure-widget renderer widget available)))))
           (with-frame (context width height) (funcall draw))
           (pdf:with-document (:title title)
             (pdf:with-page (:bounds (vector 0 0 width height))
               (pdf:translate 0 height)
               (pdf:scale 1 -1)
               (let ((rgba (color-components background)))
                 (pdf:set-rgb-fill (aref rgba 0) (aref rgba 1) (aref rgba 2)))
               (pdf:basic-rect 0 0 width height)
               (pdf:fill-path)
               (paint-frame renderer context))
             (pdf:write-document (pathname pathname)))
           (pathname pathname))
      (lui.font:close-font font))))

(fn (run-pdf pathname) ((draw function) &key title width height interactive)
  (declare (ignore interactive))
  (render-pdf draw *pdf-output* :title title :width (or width 612)
                            :height (or height 792)))

(lui:register-backend :pdf #'run-pdf)
