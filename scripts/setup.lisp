(defpackage #:lui.setup
  (:use #:cl))
(in-package #:lui.setup)

(require :asdf)
#-quicklisp
(let ((setup (merge-pathnames "quicklisp/setup.lisp"
                              (user-homedir-pathname))))
  (when (probe-file setup) (load setup)))
(asdf:load-asd (truename "lui.asd"))
