;;; Run in a fresh process: sbcl --script tests/font-discovery.lisp FONT.ttf
;;; Hide the optional system while retaining the installed native dependencies.
(load "scripts/setup.lisp")
(asdf:load-system "cffi")
(asdf:load-system "zpb-ttf")
(assert (not (find-package :org.shirakumo.font-discovery)))
(asdf:clear-system "font-discovery")
(asdf:clear-system "lui/native")
(let* ((searchers asdf:*system-definition-search-functions*)
       (asdf:*system-definition-search-functions*
         (list (lambda (name)
                 (unless (equal name "font-discovery")
                   (loop :for searcher :in searchers
                         :thereis (funcall searcher name)))))))
  (asdf:load-asd (truename "lui.asd"))
  (asdf:load-system "lui/native"))
(assert (not (find-package :org.shirakumo.font-discovery)))

(in-package #:lui.font)
(let* ((path (truename (first (uiop:command-line-arguments))))
       (*font-path* path)
       (*font-paths* (list (cons '(:monospace :bold) path)))
       (font (open-font)))
  (unwind-protect
       (progn
         (assert (plusp (text-width font "Explicit font")))
         (assert (equal path (resolve-face :monospace :bold)))
         (assert (plusp (text-width (font-face font :monospace :bold) "Bold")))
         (assert (handler-case (progn (resolve-face :sans-serif :bold) nil)
                   (%lui.conditions:font-error () t))))
    (close-font font)))
(format t "Native loading and explicit fonts without font-discovery passed.~%")
