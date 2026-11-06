(defpackage #:lui.start.native
  (:use #:cl))

(in-package #:lui.start.native)

(require :asdf)

(asdf:load-asd (truename "lui.asd"))

;; Load the host backends; an explicit LUI:*BACKEND* still selects one.
(asdf:load-system "lui")

(asdf:load-system "lui/demo")

(lui.example:main)
