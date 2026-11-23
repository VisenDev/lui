;;; Run through make test-fonts: fresh processes isolate platform and image state.
(load "scripts/setup.lisp")

(when (equal "darwin" (uiop:getenv "LUI_FONT_TEST_MODE"))
  ;; Check reader/ASDF exclusion on Linux without claiming CoreText execution.
  (asdf:load-system "lui/core")
  (asdf:load-system "cffi")
  (asdf:load-system "zpb-ttf")
  (let* ((*features* (cons :darwin (remove :linux *features*)))
         (dependency
           (find-if (lambda (entry)
                      (and (consp entry)
                           (equal "font-discovery" (third entry))))
                    (asdf:system-depends-on (asdf:find-system "lui/native")))))
    (assert dependency)
    (assert (not (uiop:featurep (second dependency))))
    (load "src/backend-common.lisp")
    (assert (not (find-package :org.shirakumo.font-discovery)))
    (assert (not (fboundp (find-symbol "DISCOVER-SYSTEM-FACE" :lui.font)))))
  (format t "Darwin dependency and source exclusion passed (simulated).~%")
  (uiop:quit 0))

(asdf:load-system "lui/native")
(defpackage #:%lui.tests.font-discovery-image
  (:use #:cl))
(in-package #:%lui.tests.font-discovery-image)

(defun check-discovery ()
  "Force system discovery before and after saving, with no filename fallback."
  (let* ((lui.font:*font-discovery-p* t)
         (lui.font:*font-path* nil)
         (lui.font:*font-paths* nil)
         (lui.font:*font-directories* nil)
         (lui.font:*font-names* nil)
         (font (lui.font:open-font)))
    (unwind-protect
         (dolist (family '(:sans-serif :monospace))
           (dolist (weight '(:normal :bold))
             (assert (plusp (lui.font:text-width
                             (lui.font:font-face font family weight)
                             "Saved font discovery")))))
      (lui.font:close-font font))))

(defun main ()
  "Exercise restored Fontconfig handles in a new native process."
  (check-discovery)
  (format t "Saved executable font discovery passed.~%")
  (uiop:quit 0))

(check-discovery)
(sb-ext:save-lisp-and-die (uiop:getenv "LUI_OUTPUT")
                        :toplevel #'main :executable t)
