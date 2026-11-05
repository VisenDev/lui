(defpackage #:lui.setup
  (:use #:cl))
(in-package #:lui.setup)

(let ((asdf (merge-pathnames "quicklisp/asdf.lisp"
                             (user-homedir-pathname))))
  (when (probe-file asdf) (load asdf)))
(require :asdf)
(let ((setup (merge-pathnames "quicklisp/setup.lisp"
                              (user-homedir-pathname))))
  (when (probe-file setup) (load setup)))
(asdf:load-asd (truename "lui.asd"))
