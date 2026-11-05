(defpackage #:lui.start.demo
  (:use #:cl))

(in-package #:lui.start.demo)

(let* ((parameters
         (jscl/ffi:new #j:URLSearchParams #j:window:location:search))
       (example ((jscl/ffi:oget parameters "get") #j"example")))
  (if (and (not (eq example #j:null))
           (string= (jscl/ffi:clstring example) "showcase"))
      (lui.example.showcase:main)
      (lui.example:main)))
