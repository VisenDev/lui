(defpackage #:lui.text
  (:use #:cl #:lui.fn)
  (:export #:wrap-lines))
(in-package #:lui.text)

(fn (wrap-lines (vector string)) ((text string) (width (or null real)) (measure function))
  "Wrap at spaces and newlines. MEASURE takes TEXT and a start/end range.
Preserve empty lines and allow words wider than WIDTH to overflow."
  (let ((start 0) (length (length text))
        (lines (make-array 0 :element-type 'string :adjustable t :fill-pointer 0)))
    (loop
      (let ((end (or (position #\Newline text :start start) length)))
        (when width
          (let ((previous nil) (cursor (min end (1+ start))))
            (loop
              (let ((space (position #\Space text :start cursor :end end)))
                (cond
                  ((<= (funcall measure text start (or space end)) width)
                   (unless space (return))
                   (setf previous space cursor (1+ space)))
                  ((or previous space)
                   (let ((split (or previous space)))
                     (vector-push-extend (subseq text start split) lines)
                     (setf start (1+ split) previous nil
                           cursor (min end (1+ start)))))
                  (t (return)))))))
        (vector-push-extend (subseq text start end) lines)
        (when (= end length) (return))
        (setf start (1+ end))))
    lines))
