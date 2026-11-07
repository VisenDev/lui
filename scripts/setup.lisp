(defpackage #:lui.setup
  (:use #:cl))
(in-package #:lui.setup)

(require :asdf)
#-quicklisp
(let ((setup (merge-pathnames "quicklisp/setup.lisp"
                              (user-homedir-pathname))))
  (when (probe-file setup) (load setup)))
;; Optional local dependency checkouts, including uncursed.
(let ((dependencies (merge-pathnames "build/deps/" (uiop:getcwd))))
  (when (probe-file dependencies)
    (dolist (directory (uiop:subdirectories dependencies))
      (pushnew directory asdf:*central-registry* :test #'equal))))
(asdf:load-asd (truename "lui.asd"))
