(defpackage #:%lui.run.demo
  (:use #:cl))

(in-package #:%lui.run.demo)

(require :asdf)

(asdf:load-asd (truename "lui.asd"))

;; Load the host backends; an explicit LUI:*BACKEND* still selects one.
(asdf:load-system "lui")

(asdf:load-system "lui/demo")

(%lui.example.demo:main)
