(defpackage #:lui.build.docs.web
  (:use #:cl))
(in-package #:lui.build.docs.web)

;; Run with JSCL's Node host after generating build/docs-data.lisp.
(with-open-file (out "build/start-docs.lisp" :direction :output
                     :if-exists :supersede)
  (write-line "(lui.docs:main :backend :web)" out))

(jscl:compile-application
 '("src/fn.lisp" "src/web-js.lisp" "src/layout.lisp" "src/frame.lisp" "src/widgets.lisp"
   "src/app.lisp" "src/interaction.lisp"
   "src/glass.lisp" "src/motif.lisp" "src/desktop.lisp" "src/garnet.lisp"
   "src/text-wrap.lisp" "src/web-font.lisp" "src/draw.lisp" "src/text-selection.lisp" "src/paint-common.lisp"
   "src/paint-glass.lisp" "src/paint-motif.lisp" "src/paint-desktop.lisp" "src/paint-garnet.lisp" "src/web-input.lisp"
   "src/debug.lisp" "src/web.lisp" "examples/docs.lisp"
   "build/docs-data.lisp" "build/start-docs.lisp")
 "build/lui-docs.js")

(let ((fs jscl::*fs*)
      (header
       #j"<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>LUI documentation</title><style>body{margin:0}</style></head><body><script>"))
  (flet ((inline-script (path)
           (let ((source ((jscl/ffi:oget fs "readFileSync")
                          (jscl/ffi:jsstring path) #j"utf8")))
             ;; Documentation strings may contain HTML closing tags.
             ((jscl/ffi:oget source "replace")
              (#j:RegExp #j"</script" #j"gi") #j"<\\/script"))))
    ((jscl/ffi:oget fs "writeFileSync") #j"build/docs.html"
     ((jscl/ffi:oget header "concat")
      (inline-script "build/jscl.js") #j"</script><script>"
      (inline-script "build/lui-docs.js") #j"</script></body></html>")
     #j"utf8")))
(format t "Wrote standalone build/docs.html~%")
