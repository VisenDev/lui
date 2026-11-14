(defpackage #:%lui.miricl
  (:use #:cl #:%lui.fn)
  (:nicknames #:jscl/ffi)
  (:export #:global #:oget #:invoke #:new #:jsstring #:clstring #:clbool
           #:same-p))
(in-package #:%lui.miricl)

(defvar *callbacks* (js:make-weak-hash-table :test 'eq :weakness :key))

(fn (from-js t) ((value t))
  "Convert JavaScript primitives while preserving object references."
  (let ((decoded (if (js:valuep value) (js:from-js value) value)))
    ;; Browser integer fields (buttons, click counts, keys) have JS Number type.
    (if (and (floatp decoded) (= decoded (truncate decoded)))
        (truncate decoded)
        ;; else
        decoded)))

(fn (to-js t) ((value t))
  "Convert callbacks once so listener removal preserves function identity."
  (if (functionp value)
      (or (gethash value *callbacks*)
          (setf (gethash value *callbacks*)
                (js:callback
                 (lambda (&rest arguments)
                   (apply value (mapcar #'from-js arguments))
                   js:+undefined+))))
      ;; else
      value))

(fn (global t) ((path string))
  "Resolve a JavaScript global path or literal through the host adapter."
  (from-js (js:invoke (js:global "LuiMiricl") "global" path)))

(fn (oget t) ((object t) &rest (keys list))
  "Read nested properties, retaining the receiver of JavaScript methods."
  (dolist (key keys (from-js object))
    (setf object (js:invoke (js:global "LuiMiricl") "property"
                            object key))))

(fn ((setf oget) t) ((value t) (object t) &rest (keys list))
  "Assign a JavaScript property, converting Lisp callbacks as needed."
  (dolist (key (butlast keys))
    (setf object (js:property object key)))
  (setf (js:property object (car (last keys))) (to-js value))
  value)

(fn (invoke t) ((function t) &rest (arguments list))
  "Call a JavaScript function and decode its primitive result."
  (from-js (apply #'js:call function (mapcar #'to-js arguments))))

(fn (new t) ((constructor t) &rest (arguments list))
  "Construct a JavaScript object with converted arguments."
  (apply #'js:new constructor (mapcar #'to-js arguments)))

(fn (jsstring string) ((value string))
  "Transfer strings directly through MiriCL's Unicode bridge." value)

(fn (clstring string) ((value t))
  "Decode a JavaScript string."
  (from-js value))

(fn (clbool boolean) ((value t))
  "Apply JavaScript truthiness to a bridge value."
  (not (null (from-js (js:call (js:global "Boolean") value)))))

(fn (same-p boolean) ((left t) (right t))
  "Compare JavaScript object identity or ordinary Lisp identity."
  (if (or (js:valuep left) (js:valuep right))
      (js:strict-equal left right)
      ;; else
      (eq left right)))
