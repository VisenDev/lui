(defpackage #:%lui.test.win32 (:use #:cl))
(in-package #:%lui.test.win32)

(require :asdf)

;; Configure ASDF's source registry for CFFI and ZPB-TTF before running.
;; This script works with both native Windows SBCL and Windows SBCL in Wine.
(let ((root
        (uiop:pathname-parent-directory-pathname
          (uiop:pathname-directory-pathname *load-truename*))))
  (asdf:load-asd (merge-pathnames "lui.asd" root))
  (asdf:load-system "lui/win32")
  (asdf:load-system "lui/demo")
  (load (merge-pathnames "tests/win32.lisp" root)))
