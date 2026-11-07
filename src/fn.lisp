(defpackage #:lui.fn
  (:use #:cl)
  (:export #:fn #:symbolicate))

(in-package #:lui.fn)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun symbolicate (&rest things)
    "Concatenate the printed arguments, uppercase the result, and intern it in the current package."
    (intern (string-upcase
             (apply #'concatenate 'string
                    (mapcar (lambda (thing) (format nil "~a" thing))
                            things)))))

  (defun parse-typed-lambda-list (parameters)
    (let ((mode :required) lambda-list argument-types declarations)
      (dolist (parameter parameters)
        (if (member parameter '(&optional &key &rest &aux))
            (progn
              (setf mode parameter)
              (push parameter lambda-list)
              (unless (eq mode '&aux) (push parameter argument-types)))
            (let* ((optional (member mode '(&optional &key &aux)))
                   (binding (if (and optional (consp parameter))
                                parameter (list parameter)))
                   (head (first binding))
                   (typed (consp head))
                   (name (if typed (first head) head))
                   (type (if typed (second head) t)))
              (when typed (assert (= 2 (length head))))
              (push (if optional (cons name (rest binding)) name) lambda-list)
              (push `(type ,type ,name) declarations)
              (unless (eq mode '&aux)
                (push (if (eq mode '&key)
                          (list (intern (symbol-name name) :keyword) type)
                          type)
                      argument-types)))))
      (values (nreverse lambda-list) (nreverse argument-types)
              (nreverse declarations)))))

(defmacro fn (name typed-lambda-list &body body)
  "Define a function with typed parameters and an optional (NAME RETURN-TYPE).
Optional/key parameters use ((NAME TYPE) DEFAULT SUPPLIED-P)."
  (multiple-value-bind (lambda-list argument-types types)
      (parse-typed-lambda-list typed-lambda-list)
    (let* ((function-name (if (listp name) (first name) name))
           (return-type (if (listp name) (second name) t))
           (docstring (when (stringp (first body)) (pop body)))
           (declarations
             (loop :while (and (consp (first body)) (eq (caar body) 'declare))
                   :collect (pop body))))
      `(progn
         (declaim (ftype (function ,argument-types ,return-type) ,function-name))
         (defun ,function-name ,lambda-list
           ,@(when docstring (list docstring))
           (declare ,@types)
           ,@declarations
           (the ,return-type (progn ,@body)))))))

#+jscl
(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; JSCL emits costly slot checks even for type T. Preserve metadata and
  ;; initializer expressions, removing only generated constructor/writer checks.
  (let ((original (macro-function 'defstruct)))
    (setf (macro-function 'defstruct)
          (lambda (form environment)
            (labels ((without-slot-checks (form)
                       (cond ((atom form) form)
                             ((eq (car form) 'quote) form)
                             ((eq (car form) 'defun)
                              (append (subseq form 0 3)
                                      (mapcar #'without-slot-checks
                                              (remove-if
                                               (lambda (body)
                                                 (and (consp body)
                                                      (eq (car body) 'check-type)))
                                               (cdddr form)))))
                             (t (mapcar #'without-slot-checks form)))))
              (without-slot-checks
               (macroexpand (funcall original form environment) environment)))))))
