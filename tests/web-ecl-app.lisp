(defpackage #:lui.tests.web-ecl-app
  (:use #:cl))
(in-package #:lui.tests.web-ecl-app)

;; Compiled test entry point: the ordinary gallery remains the default page.
;; The fixture exercises editing, Unicode, GC, and teardown without evaluating
;; test Lisp in the browser or depending on JSCL's object representation.
(defvar *app* nil)
(defvar *count* 0)

(defun check-bridge ()
  (let* ((lui.ecl-emscripten:*owner* (list :bridge-check))
         (object (lui.ecl-emscripten:new (lui.ecl-emscripten:global
              "Object")))
         (nested (lui.ecl-emscripten:new (lui.ecl-emscripten:global
              "Object")))
         (opaque (list :lisp-object)))
    (unwind-protect
         (progn
           (assert (eq (lui.ecl-emscripten:global "window")
                       (lui.ecl-emscripten:global "window")))
           (assert (eq :undefined (lui.ecl-emscripten:oget object "missing")))
           (setf (lui.ecl-emscripten:oget object "nested") nested
                 (lui.ecl-emscripten:oget object "opaque") opaque)
           (assert (eq opaque (lui.ecl-emscripten:oget object "opaque")))
           (dolist (value (list 0 -42 1.25d0 :null :true :false :undefined
                               "café 漢字 😀" (string (code-char 0))))
             (setf (lui.ecl-emscripten:oget object "nested" "value") value)
             (assert (equalp value
                             (lui.ecl-emscripten:oget object "nested"
                  "value"))))
           ;; A synchronous browser call reenters Lisp, which calls JS again.
           (setf (lui.ecl-emscripten:oget object "callback")
                 (lambda (value)
                   (setf (lui.ecl-emscripten:oget object "nested" "value")
                value)))
           (lui.ecl-emscripten:invoke (lui.ecl-emscripten:oget object "callback") "nested")
           (assert (equal "nested"
                          (lui.ecl-emscripten:oget object "nested" "value")))
           (assert (handler-case
                       (progn (lui.ecl-emscripten:invoke 123) nil)
                     (error () t))))
      (lui.ecl-emscripten:release-owner lui.ecl-emscripten:*owner*))))

(check-bridge)

(defun draw-fixture ()
  (lui:with-toolkit (:qt)
    (lui:column (:width (lui:grow) :gap 8)
      (let ((value
            (lui:text-field
              (lui:opt
                :id 0
                :default-value "initial"
                :width (lui:grow)
                :accessible-name "Fixture text"))))
        (lui:label (format nil "Value: ~A" value)))
      (when (lui:button "Increment" (lui:opt :id :count)) (incf *count*))
      (lui:label (format nil "Count: ~D" *count*))
      (when (lui:button "Collect garbage" (lui:opt :id :gc))
        (ext:gc t)
        (setf (lui.ecl-emscripten:oget (lui.ecl-emscripten:global "window") "eclLiveRoots")
              (hash-table-count lui.ecl-emscripten::*roots*))))))

(if (equal (lui.ecl-emscripten:oget (lui.ecl-emscripten:global "location") "search")
           "?fixture")
    (progn
      (setf *app* (lui:run #'draw-fixture :width 500 :height 300))
      (setf (lui.ecl-emscripten:oget (lui.ecl-emscripten:global "window") "eclUnmount")
            (lambda ()
              (lui:unmount *app*)
              (setf *app* nil)
              (ext:gc t)
              (setf (lui.ecl-emscripten:oget (lui.ecl-emscripten:global "window")
                                     "eclRemainingRoots")
                    (hash-table-count lui.ecl-emscripten::*roots*)))))
    (lui.example.demo:main))
