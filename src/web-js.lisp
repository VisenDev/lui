(defpackage #:lui.js
  (:use #:cl #:lui.fn)
  (:export #:global #:property #:invoke #:new #:same-p #:callback
           #:+null+ #:+undefined+))
(in-package #:lui.js)

(defparameter +null+ #+jscl (jscl::jsnull) #+miricl js:+null+)
(defparameter +undefined+ #+jscl (jscl::jsundefined) #+miricl js:+undefined+)

(fn (from-js t) (value)
  #+miricl (if (js:valuep value) (js:from-js value) value)
  #+jscl
  (cond ((eq (jscl/ffi:typeof value) (jscl/ffi:jsstring "string"))
         (jscl/ffi:clstring value))
        ((eq value (jscl/ffi:jsbool t)) t)
        ((eq value (jscl/ffi:jsbool nil)) nil)
        (t value)))

(fn (to-js t) (value)
  #+jscl
  (cond ((stringp value) (jscl/ffi:jsstring value))
        ((eq value t) (jscl/ffi:jsbool t))
        ((null value) (jscl/ffi:jsbool nil))
        (t value))
  #+miricl value)

(fn (global t) (&optional name)
  #+miricl (js:global name)
  #+jscl (if name (jscl/ffi:oget jscl::*root* name) jscl::*root*))

(fn (property t) (object &rest keys)
  (dolist (key keys (from-js object))
    (setf object #+jscl (jscl/ffi:oget object key)
          #+miricl (js:property object key))))

(fn ((setf property) t) (value object &rest keys)
  (dolist (key (butlast keys))
    (setf object (property object key)))
  #+jscl (setf (jscl/ffi:oget object (car (last keys))) (to-js value))
  #+miricl (setf (js:property object (car (last keys))) (to-js value))
  value)

(defmacro invoke (object method &rest arguments)
  #+jscl
  `(from-js ((jscl/ffi:oget (to-js ,object) ,method)
             ,@(mapcar (lambda (arg) `(to-js ,arg)) arguments)))
  #+miricl
  `(from-js (js:invoke ,object ,method
                       ,@(mapcar (lambda (arg) `(to-js ,arg)) arguments))))

(defmacro new (constructor &rest arguments)
  `(,(quote #+jscl jscl/ffi:new #+miricl js:new) ,constructor
     ,@(mapcar (lambda (arg) `(to-js ,arg)) arguments)))

(fn (same-p boolean) (left right)
  #+jscl (eq left right)
  #+miricl (js:strict-equal left right))

(fn (callback t) ((function function))
  "Create an event callback once; retain it for listener removal."
  #+jscl function
  #+miricl
  (js:callback (lambda (&rest arguments)
                 (apply function arguments)
                 js:+undefined+)))
