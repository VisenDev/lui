;;; Run in a fresh process: sbcl --script tests/font-search.lisp
(load "scripts/setup.lisp")
(asdf:load-system "lui/native")
(assert (not (find-package :org.shirakumo.font-discovery)))

(in-package #:lui.font)
(let* ((path (truename (resolve-face :sans-serif :normal)))
       (*font-path* path)
       (*font-paths* (list (cons '(:monospace :bold) path)))
       (*font-directories* (list (uiop:pathname-directory-pathname path)))
       (*font-names* (list (list '(:sans-serif :normal)
                                "missing-lui-test-font.ttf"
                                (file-namestring path))))
       (font (open-font)))
  (unwind-protect
       (progn
         (assert (equal path (resolve-face :sans-serif :normal)))
         (assert (equal path (resolve-face :monospace :bold)))
         (assert (plusp (text-width font "Base font")))
         (assert (plusp (text-width (font-face font :monospace :bold) "Bold")))
         (assert (handler-case (progn (resolve-face :sans-serif :bold) nil)
                   (%lui.conditions:font-error () t))))
    (close-font font)))
(format t "Native font search and explicit overrides passed.~%")
