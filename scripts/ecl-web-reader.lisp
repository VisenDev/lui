(defpackage #:lui.ecl.web.reader
  (:use #:cl)
  (:export #:read-web-form))
(in-package #:lui.ecl.web.reader)

;; Read the existing browser interop syntax without loading JSCL. Only the
;; browser adapter files use this reader; ordinary application Lisp is intact.
(defun javascript-token (stream character argument)
  (declare (ignore character argument))
  (if (char= (peek-char nil stream) #\")
      (read stream t nil t)
      (progn
        (assert (char= (read-char stream) #\:))
        (let ((path (with-output-to-string (out)
                      (loop :for c := (peek-char nil stream nil nil)
                            :while (and c (not (find c " ()"))
                                        (not (find c '(#\Newline #\Tab))))
                            :do (write-char (read-char stream) out)))))
          `(lui.ecl-emscripten:global ,path)))))

(defun normalize (form)
  (cond ((atom form) form)
        ((eq (car form) 'quote) form)
        ((and (consp (car form))
              (member (caar form)
                      '(lui.ecl-emscripten:oget lui.ecl-emscripten:global)))
         `(lui.ecl-emscripten:invoke ,(normalize (car form))
                             ,@(mapcar #'normalize (cdr form))))
        (t (mapcar #'normalize form))))

(defun read-web-form (stream eof)
  (let ((*readtable* (copy-readtable)))
    (set-dispatch-macro-character #\# #\j #'javascript-token)
    (normalize (read stream nil eof))))
