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

#-lui-ecl-host (ffi:clines "#include <emscripten.h>")

(fn (evaluate-js string) ((source base-string))
  #+lui-ecl-host (error "Browser operation in host compiler: ~A" source)
  #-lui-ecl-host
  (ffi:c-inline (source) (:cstring) :cstring
                "emscripten_run_script_string(#0)" :one-liner t))

(fn (quote-js base-string) ((value string))
  (coerce
   (with-output-to-string (out)
     (write-char #\" out)
     (loop :for char :across value :for code := (char-code char) :do
       (cond ((find char '(#\" #\\))
              (write-char #\\ out) (write-char char out))
             ((<= 32 code 126) (write-char char out))
             ((<= code #xffff) (format out "\\u~4,'0X" code))
             (t (let ((n (- code #x10000)))
                  (format out "\\u~4,'0X\\u~4,'0X"
                          (+ #xd800 (ash n -10))
                          (+ #xdc00 (logand n #x3ff)))))))
     (write-char #\" out))
   'base-string))

(fn (root-id integer) (value)
  (or (loop :for id :being :the :hash-keys :of *roots*
            :using (:hash-value entry)
            :when (and (eq value (car entry)) (eq *owner* (cdr entry)))
            :return id)
      (let ((id (incf *next-root*)))
        (setf (gethash id *roots*) (cons value *owner*)) id)))

(fn (encode string) (value)
  (if (member value '(:true :false :null :undefined))
      (string-downcase (symbol-name value))
      (typecase value
        (reference (format nil "LuiECL.get(~D)" (reference-id value)))
        (string (quote-js value))
        (real (let ((*read-default-float-format* 'double-float))
                (substitute #\e #\d
                            (format nil "~,17E"
                                    (coerce value 'double-float)))))
        (null "null")
        (otherwise
         (format nil "LuiECL.root(~D,~A)" (root-id value)
                 (if (functionp value) "true" "false"))))))

(fn (decode t) (value)
  (case (car value)
    (:string (map 'string #'code-char (cdr value)))
    (:number (second value))
    (:root (car (gethash (second value) *roots*)))
    (:reference
     (let* ((id (second value)) (old (gethash id *references*)))
       (cond (old (push id *released*) old)
             (t (let ((object (make-reference :id id)))
                  (setf (gethash id *references*) object)
                  (ext:set-finalizer object
                                     (lambda (ignored)
                                       (declare (ignore ignored))
                                       (push id *released*)))
                  object)))))
    (otherwise (car value))))

(fn (evaluate t) ((source string))
  (let ((*read-eval* nil))
    (when *released*
      (evaluate-js
       (coerce (format nil "LuiECL.release([~{~D~^,~}]); ''"
                       (shiftf *released* nil)) 'base-string)))
    (let ((result (read-from-string
                   (evaluate-js
                    (coerce (format nil "LuiECL.perform(()=>~A)" source)
                            'base-string)))))
      (when (eq (car result) :error)
        (error "Browser operation failed: ~A" (decode (cdr result))))
      (decode result))))

(fn (global t) ((path string))
  (evaluate (format nil "LuiECL.global(~A)" (quote-js path))))

(fn (oget t) (object &rest keys)
  (dolist (key keys object)
    (setf object
          (evaluate (format nil "LuiECL.property(~A,~A)"
                            (encode object) (quote-js key))))))

(fn ((setf oget) t) (value object &rest keys)
  (let ((parent (if (cdr keys) (apply #'oget object (butlast keys)) object)))
    (evaluate (format nil "(~A[~A]=~A)" (encode parent)
                      (quote-js (car (last keys))) (encode value))))
  value)

(fn (invoke t) (function &rest arguments)
  (evaluate (format nil "~A(~{~A~^,~})" (encode function)
                    (mapcar #'encode arguments))))

(fn (new t) (constructor &rest arguments)
  (evaluate (format nil "Reflect.construct(~A,[~{~A~^,~}])"
                    (encode constructor) (mapcar #'encode arguments))))

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
          :do (evaluate (format nil "LuiECL.dropRoot(~D)" id))
              (remhash id *roots*))
  nil)

(fn (release-root boolean) ((id integer))
  (remhash id *roots*))

(fn (dispatch boolean) ((id integer) (arguments list))
  (let* ((entry (gethash id *roots*)) (*owner* (cdr entry)))
    (handler-case
        (progn (when entry
                 (apply (car entry) (mapcar #'decode arguments))) t)
      (serious-condition (condition)
        (format *error-output* "~&LUI browser callback: ~A~%" condition)
        nil))))
