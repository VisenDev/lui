(defpackage #:%lui.miricl.web.reader
  (:use #:cl)
  (:export #:prepare-source))
(in-package #:%lui.miricl.web.reader)

(defun javascript-token (stream character argument)
  "Read the shared browser adapter's JavaScript literals and global paths."
  (declare (ignore character argument))
  (if (char= (peek-char nil stream) #\")
      (read stream t nil t)
      ;; else
      (progn
        (assert (char= (read-char stream) #\:))
        (let ((path (with-output-to-string (out)
                      (loop :for c := (peek-char nil stream nil nil)
                            :while (and c (not (find c " ()"))
                                        (not (find c '(#\Newline #\Tab))))
                            :do (write-char (read-char stream) out)))))
          `(%lui.miricl:global ,path)))))

(defun normalize (form)
  "Translate shared browser calls and object comparisons to the adapter."
  (cond ((atom form) form)
        ((eq (car form) 'quote) form)
        ((eq (car form) 'eq)
         `(%lui.miricl:same-p ,@(mapcar #'normalize (cdr form))))
        ((and (consp (car form))
              (member (caar form) '(%lui.miricl:oget %lui.miricl:global)))
         `(%lui.miricl:invoke ,@(mapcar #'normalize form)))
        (t (mapcar #'normalize form))))

(defun prepare-source (source output &optional (browser-p t))
  "Write ordinary Lisp from browser syntax, resolving packages in source order."
  (with-open-file (in source)
    (with-open-file (out output :direction :output :if-exists :supersede)
      (let ((*package* (find-package :cl-user))
            (*print-pretty* nil)
            (*print-readably* t)
            (*readtable* (copy-readtable)))
        (set-dispatch-macro-character #\# #\j #'javascript-token)
        (loop :for form := (read in nil in)
              :until (eq form in)
              :do (write (if browser-p (normalize form) form) :stream out)
                  (terpri out)
                  (when (and (consp form)
                             (member (car form) '(defpackage in-package)))
                    (eval form))))))
  (values))
