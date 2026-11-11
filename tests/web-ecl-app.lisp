(defpackage #:lui.tests.web-ecl-app
  (:use #:cl))
(in-package #:lui.tests.web-ecl-app)

;; Compiled test entry point: the ordinary gallery remains the default page.
;; The fixture exercises editing, Unicode, GC, and teardown without evaluating
;; test Lisp in the browser or depending on JSCL's object representation.
(defvar *app* nil)
(defvar *value* "initial")
(defvar *count* 0)

(defun check-bridge ()
  (let* ((lui.web.ffi:*owner* (list :bridge-check))
         (object (lui.web.ffi:new (lui.web.ffi:global "Object")))
         (nested (lui.web.ffi:new (lui.web.ffi:global "Object")))
         (opaque (list :lisp-object)))
    (unwind-protect
         (progn
           (assert (eq (lui.web.ffi:global "window")
                       (lui.web.ffi:global "window")))
           (assert (eq :undefined (lui.web.ffi:oget object "missing")))
           (setf (lui.web.ffi:oget object "nested") nested
                 (lui.web.ffi:oget object "opaque") opaque)
           (assert (eq opaque (lui.web.ffi:oget object "opaque")))
           (dolist (value (list 0 -42 1.25d0 :null :true :false :undefined
                               "café 漢字 😀" (string (code-char 0))))
             (setf (lui.web.ffi:oget object "nested" "value") value)
             (assert (equalp value
                             (lui.web.ffi:oget object "nested" "value"))))
           ;; A synchronous browser call reenters Lisp, which calls JS again.
           (setf (lui.web.ffi:oget object "callback")
                 (lambda (value)
                   (setf (lui.web.ffi:oget object "nested" "value") value)))
           (lui.web.ffi:invoke (lui.web.ffi:oget object "callback") "nested")
           (assert (equal "nested"
                          (lui.web.ffi:oget object "nested" "value")))
           (assert (handler-case
                       (progn (lui.web.ffi:invoke 123) nil)
                     (error () t))))
      (lui.web.ffi:release-owner lui.web.ffi:*owner*))))

(check-bridge)

(defun draw-fixture ()
  (lui:with-toolkit (:qt)
    (lui:column (:width (lui:grow) :gap 8)
      (setf *value*
            (lui:text-field :text *value*
                            (lui:opt :width (lui:grow)
                                     :accessible-name "Fixture text")))
      (lui:label (format nil "Value: ~A" *value*))
      (when (lui:button :count "Increment") (incf *count*))
      (lui:label (format nil "Count: ~D" *count*))
      (when (lui:button :gc "Collect garbage")
        (ext:gc t)
        (setf (lui.web.ffi:oget (lui.web.ffi:global "window") "eclLiveRoots")
              (hash-table-count lui.web.ffi::*roots*))))))

(if (equal (lui.web.ffi:oget (lui.web.ffi:global "location") "search")
           "?fixture")
    (progn
      (setf *app* (lui:run #'draw-fixture :width 500 :height 300))
      (setf (lui.web.ffi:oget (lui.web.ffi:global "window") "eclUnmount")
            (lambda ()
              (lui:unmount *app*)
              (setf *app* nil)
              (ext:gc t)
              (setf (lui.web.ffi:oget (lui.web.ffi:global "window")
                                     "eclRemainingRoots")
                    (hash-table-count lui.web.ffi::*roots*)))))
    (lui.example:main))
