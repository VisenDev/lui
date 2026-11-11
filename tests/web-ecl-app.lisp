(defpackage #:lui.tests.web-ecl-app
  (:use #:cl))
(in-package #:lui.tests.web-ecl-app)

;; Compiled test entry point: the ordinary gallery remains the default page.
;; The fixture exercises editing, Unicode, GC, and teardown without evaluating
;; test Lisp in the browser or depending on JSCL's object representation.
(defvar *app* nil)
(defvar *value* "initial")
(defvar *count* 0)

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
