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

  (defstruct param
    (name nil :type symbol)
    (type t)
    (kind nil :type (member :required :optional :key :rest :aux))
    initform supplied-p)

  (defun parse-typed-lambda-list (params)
    (let ((state :required)
          (results nil))
      (loop :for val :in params
            :do (case val
                  (&optional (setf state :optional))
                  (&key (setf state :key))
                  (&rest (setf state :rest))
                  (&aux (setf state :aux))
                  (otherwise
                   (ecase state
                     (:required
                      (cond ((listp val)
                             (assert (= 2 (length val)))
                             (push (make-param :name (first val)
                                               :kind :required
                                               :type (second val))
                                   results))
                            (t
                             (push (make-param :name val :kind :required)
                                   results))))
                     ((:optional :key :aux)
                      (cond ((and (listp val) (listp (car val)))
                             (assert (= 2 (length (car val))))
                             (push (make-param :name (first (first val))
                                               :kind state
                                               :type (second (first val))
                                               :initform (second val)
                                               :supplied-p (third val))
                                   results))
                            ((listp val)
                             (push (make-param :name (first val)
                                               :kind state
                                               :initform (second val)
                                               :supplied-p (third val))
                                   results))
                            (t
                             (push (make-param :name val :kind state)
                                   results))))
                     (:rest
                      (push (make-param :name val :kind :rest) results))))))
      (nreverse results)))

  (defun generate-function-type (return-type parsed-typed-lambda-list)
    (loop :with results := nil
          :with active-kind := :required
          :for param :in parsed-typed-lambda-list
          :for name := (param-name param)
          :for type := (param-type param)
          :for kind := (param-kind param)
          :do (progn
                (when (not (eq kind active-kind))
                  (case kind
                    (:optional (push '&optional results))
                    (:key (push '&key results))
                    (:rest (push '&rest results))
                    (:aux nil)
                    (otherwise nil))
                  (setf active-kind kind))
                (ecase kind
                  ((:required :optional :rest) (push type results))
                  (:key
                   (push (list (intern (symbol-name name) 'keyword) type)
                         results))
                  (:aux))
                results)
          :finally (return `(function ,(nreverse results) ,return-type))))

  (defun generate-function-lambda-list (parsed-typed-lambda-list)
    (loop :with results := nil
          :with active-kind := :required
          :for param :in parsed-typed-lambda-list
          :for name := (param-name param)
          :for kind := (param-kind param)
          :for initform := (param-initform param)
          :do (progn
                (when (not (eq kind active-kind))
                  (push (ecase kind
                          (:optional '&optional)
                          (:key '&key)
                          (:rest '&rest)
                          (:aux '&aux))
                        results)
                  (setf active-kind kind))
                (push (ecase kind
                        ((:required :rest) name)
                        ((:optional :aux :key)
                         (append (list name initform)
                                 (when (param-supplied-p param)
                                   (list (param-supplied-p param))))))
                      results))
          :finally (return (nreverse results)))))

(defmacro fn (name typed-lambda-list &body body)
  "name -> either a function name or a list of the form (function-name return-type),
   typed-lambda-list -> a typed parameter list like a defmethod parameter list
   body -> a normal function body"
  (let* ((function-name (if (listp name) (first name) name))
         (return-type (if (listp name) (second name) t))
         (params (parse-typed-lambda-list typed-lambda-list))
         (docstring (when (stringp (first body)) (first body)))
         (body (if docstring (rest body) body))
         (declarations
           (loop :while (and (consp (first body)) (eq (caar body) 'declare))
                 :collect (pop body))))
    `(progn
       (declaim (ftype ,(generate-function-type return-type params)
                       ,function-name))
       (defun ,function-name ,(generate-function-lambda-list params)
         ,@(when docstring (list docstring))
         (declare ,@(mapcar (lambda (param)
                             `(type ,(param-type param) ,(param-name param)))
                           params))
         ,@declarations
         (the ,return-type (progn ,@body))))))

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
