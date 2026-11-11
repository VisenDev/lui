(defpackage #:lui.web.ffi
  (:use #:cl #:lui.fn)
  (:nicknames #:jscl/ffi)
  (:export #:global #:oget #:invoke #:new #:jsstring #:clstring #:clbool
           #:*owner* #:release-owner #:release-root #:dispatch))
(in-package #:lui.web.ffi)

;; JS objects have stable identities. Weak wrappers and deferred finalizers
;; release temporary DOM/measurement results without running JS inside GC.
(defstruct reference (id 0 :type integer))
(defvar *references* (make-hash-table :weakness :value))
(defvar *released* nil)
(defvar *roots* (make-hash-table))
(defvar *next-root* 0)
(defvar *owner* nil)

#-lui-ecl-host
(ffi:clines "extern cl_object lui_js_operation(int, cl_object);")

(fn (operation t) ((code integer) (arguments list))
  #+lui-ecl-host (error "Browser operation ~D in host: ~S" code arguments)
  #-lui-ecl-host
  (ffi:c-inline (code arguments) (:int :object) :object
                "lui_js_operation(#0, #1)" :one-liner t))

(fn (root-id integer) (value)
  (or (loop :for id :being :the :hash-keys :of *roots*
            :using (:hash-value entry)
            :when (and (eq value (car entry)) (eq *owner* (cdr entry)))
            :return id)
      (let ((id (incf *next-root*)))
        (setf (gethash id *roots*) (cons value *owner*)) id)))

(fn (transport-id integer) (value)
  (if (reference-p value) (reference-id value) (- (root-id value))))

(fn (reference-for reference) ((id integer))
  (let ((old (gethash id *references*)))
    (cond (old (push id *released*) old)
          (t (let ((object (make-reference :id id)))
               (setf (gethash id *references*) object)
               (ext:set-finalizer object
                                  (lambda (ignored)
                                    (declare (ignore ignored))
                                    (push id *released*)))
               object)))))

(fn (root-value t) ((id integer))
  (car (gethash id *roots*)))

(fn (transfer t) ((code integer) (arguments list))
  (when *released* (operation 5 (shiftf *released* nil)))
  (operation code arguments))

(fn (global t) ((path string))
  (transfer 0 (list path)))

(fn (oget t) (object &rest keys)
  (transfer 1 (cons object keys)))

(fn ((setf oget) t) (value object &rest keys)
  (transfer 2 (list* object value keys))
  value)

(fn (invoke t) (function &rest arguments)
  (transfer 3 (cons function arguments)))

(fn (new t) (constructor &rest arguments)
  (transfer 4 (cons constructor arguments)))

(fn (jsstring string) ((value string)) value)
(fn (clstring string) ((value string)) value)
(fn (clbool boolean) (value)
  (not (or (member value '(:false :null :undefined))
           (and (numberp value) (zerop value))
           (and (stringp value) (zerop (length value))))))

(fn (release-owner null) (owner)
  (loop :for id :being :the :hash-keys :of *roots*
        :using (:hash-value entry)
        :when (eq owner (cdr entry))
          :do (operation 6 (list id))
              (remhash id *roots*))
  nil)

(fn (release-root boolean) ((id integer))
  (remhash id *roots*))

(fn (dispatch boolean) ((id integer) (arguments list))
  (let* ((entry (gethash id *roots*)) (*owner* (cdr entry)))
    (handler-case
        (progn (when entry
                 (apply (car entry) arguments)) t)
      (serious-condition (condition)
        (format *error-output* "~&LUI browser callback: ~A~%" condition)
        nil))))
