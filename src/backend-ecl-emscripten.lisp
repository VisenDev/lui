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
  "Call the JavaScript bridge operation with Lisp arguments; reject host execution."
  #+lui-ecl-host (error 'lui.conditions:backend-error
                        :backend :web-ecl
                        :operation :operation
                        :format-control "Browser operation ~D in host: ~S"
                        :format-arguments (list code arguments))
  #-lui-ecl-host
  (ffi:c-inline (code arguments) (:int :object) :object
                "lui_js_operation(#0, #1)" :one-liner t))

(fn (root-id integer) (value)
  "Find or allocate a callback root owned by the current browser application."
  (or (loop :for id :being :the :hash-keys :of *roots*
            :using (:hash-value entry)
            :when (and (eq value (car entry)) (eq *owner* (cdr entry)))
            :return id)
      (let ((id (incf *next-root*)))
        (setf (gethash id *roots*) (cons value *owner*)) id)))

(fn (transport-id integer) (value)
  "Encode a Lisp value as a JavaScript transport reference."
  (if (reference-p value) (reference-id value) (- (root-id value))))

(fn (reference-for reference) ((id integer))
  "Reuse or create a weak Lisp wrapper for a JavaScript object identifier."
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
  "Root a Lisp callback and return the identifier passed across WebAssembly."
  (car (gethash id *roots*)))

(fn (transfer t) ((code integer) (arguments list))
  "Send a bridge operation and decode its primitive or object result."
  (when *released* (operation 5 (shiftf *released* nil)))
  (operation code arguments))

(fn (global t) ((path string))
  "Resolve a colon-separated JavaScript global property path."
  (transfer 0 (list path)))

(fn (oget t) (object &rest keys)
  "Read nested JavaScript properties from OBJECT using KEYS."
  (transfer 1 (cons object keys)))

(fn ((setf oget) t) (value object &rest keys)
  "Assign a JavaScript property through the bridge and return VALUE."
  (transfer 2 (list* object value keys))
  value)

(fn (invoke t) (function &rest arguments)
  "Invoke a JavaScript function with the supplied Lisp arguments."
  (transfer 3 (cons function arguments)))

(fn (new t) (constructor &rest arguments)
  "Construct a JavaScript object from its constructor and arguments."
  (transfer 4 (cons constructor arguments)))

(fn (jsstring string) ((value string))
  "Return a Lisp string for direct Unicode transfer through the ECL bridge."
  value)
(fn (clstring string) ((value string))
  "Return the directly transferred JavaScript string as a Lisp string." value)
(fn (clbool boolean) (value)
  "Interpret JavaScript false, null, undefined, zero, and empty strings as false."
  (not (or (member value '(:false :null :undefined))
           (and (numberp value) (zerop value))
           (and (stringp value) (zerop (length value))))))

(fn (release-owner (values)) (owner)
  "Release every callback root registered by OWNER without affecting other apps."
  (loop :for id :being :the :hash-keys :of *roots*
        :using (:hash-value entry)
        :when (eq owner (cdr entry))
        :do (operation 6 (list id))
        (remhash id *roots*))
  (values))

(fn (release-root boolean) ((id integer))
  "Remove one callback root and report whether it was present."
  (remhash id *roots*))

(fn (dispatch boolean) ((id integer) (arguments list))
  "Invoke a rooted Lisp callback and report failures across the JavaScript boundary."
  (let* ((entry (gethash id *roots*)) (*owner* (cdr entry)))
    (handler-case
        (progn (when entry
                 (apply (car entry) arguments)) t)
      (serious-condition (condition)
        (format *error-output* "~&LUI browser callback: ~A~%" condition)
        nil))))
