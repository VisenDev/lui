(defpackage #:lui.pdf
  (:use #:cl #:lui.frame #:lui.layout #:lui.draw)
  (:export #:render-pdf #:*output*))

(in-package #:lui.pdf)

(defvar *output* #p"lui.pdf" "Destination used by the :PDF backend of LUI:RUN.")

(defun pdf-renderer (font)
  (let (clip)
    (make-renderer
     :font font
     :clip (lambda (box) (setf clip box))
     :polygons
     (lambda (contours color alpha)
       (when contours
         (pdf:with-saved-state
           (when clip
             (pdf:basic-rect (box-x clip) (box-y clip)
                             (box-width clip) (box-height clip))
             (pdf:clip-path)
             (pdf:end-path-no-op))
           (destructuring-bind (r g b opacity) (color-components color alpha)
             (pdf:set-rgb-fill r g b)
             (unless (= opacity 1)
               (pdf:set-fill-transparency (float opacity 1f0))))
           (dolist (points contours)
             (when points
               (pdf:move-to (caar points) (cdar points))
               (dolist (point (rest points))
                 (pdf:line-to (car point) (cdr point)))
               (pdf:close-path)))
           (pdf:fill-path)))))))

(defun render-pdf (draw pathname &key (width 612) (height 792) (title "LUI")
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
               (apply #'pdf:set-rgb-fill (subseq (color-components background) 0 3))
               (pdf:basic-rect 0 0 width height)
               (pdf:fill-path)
               (paint-frame renderer context))
             (pdf:write-document (pathname pathname)))
           (pathname pathname))
      (lui.font:close-font font))))

(defun run-pdf (draw &key title width height interactive)
  (declare (ignore interactive))
  (render-pdf draw *output* :title title :width (or width 612)
                            :height (or height 792)))

(lui:register-backend :pdf #'run-pdf)
