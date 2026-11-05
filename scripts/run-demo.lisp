(defpackage #:lui.start.native
  (:use #:cl))

(in-package #:lui.start.native)

(require :asdf)

(asdf:load-asd (truename "lui.asd"))

;; Load the desired LUI backend system before this launcher, e.g. lui/x11.

(asdf:load-system "lui/demo")

(lui.example:main)
