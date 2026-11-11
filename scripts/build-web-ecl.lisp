(require :cmp)
(require :asdf)

(defpackage #:lui.build.ecl
  (:use #:cl))
(in-package #:lui.build.ecl)

(unless (fboundp 'c::read-target-info)
  (error "ECL needs cross-compilation support; build a matching host ECL."))
#+threads
(error "Build the host ECL with --disable-threads to match WebAssembly.")

(defparameter *target*
  (or (uiop:getenv "ECL_TARGET_INFO")
      (error "Set ECL_TARGET_INFO to the wasm ECL target-info.lsp file.")))
(defparameter *output* #p"build/web-ecl/")
(defparameter *entry*
  (or (uiop:getenv "ECL_WEB_APP") "scripts/start-demo.lisp"))
(defparameter *sources*
  '("src/fn.lisp" "src/ecl-web.lisp"
    "src/layout.lisp" "src/frame.lisp" "src/widgets.lisp"
    "src/app.lisp" "src/interaction.lisp"
    "src/glass.lisp" "src/motif.lisp" "src/desktop.lisp" "src/garnet.lisp"
    "src/text-wrap.lisp" "src/web-font.lisp" "src/draw.lisp"
    "src/text-selection.lisp" "src/paint-common.lisp"
    "src/paint-glass.lisp" "src/paint-motif.lisp"
    "src/paint-desktop.lisp" "src/paint-garnet.lisp"
    "src/web-input.lisp" "src/debug.lisp" "src/web.lisp"
    "examples/seven-model.lisp" "examples/seven-circles.lisp"
    "examples/seven-cells.lisp" "examples/seven.lisp" "examples/demo.lisp"))

(ensure-directories-exist *output*)
(pushnew :lui-ecl-web *features*)
(defparameter *target-info* (c::read-target-info *target*))
(pushnew :lui-ecl-web (cdr (assoc '*features* *target-info*)))

(load "src/fn.lisp")
(let ((*features* (cons :lui-ecl-host *features*)))
  (load "src/ecl-web.lisp"))
(load "scripts/ecl-web-reader.lisp")

(defun prepare-source (source)
  (if (member source '("src/web-font.lisp" "src/web-input.lisp"
                      "src/web.lisp") :test #'equal)
      (let ((output (merge-pathnames (file-namestring source) *output*)))
        (with-open-file (in source)
          (with-open-file (out output :direction :output
                               :if-exists :supersede)
            (let ((*package* (find-package :cl-user)) (*print-case* :upcase)
                  (*print-pretty* nil) (*print-readably* t))
              (loop :for form := (lui.build.ecl-reader:read-web-form in in)
                    :until (eq form in)
                    :do (write form :stream out) (terpri out)
                        (when (and (consp form)
                                   (member (car form)
                                           '(defpackage in-package)))
                          (eval form))))))
        output)
      source))

;; Load definitions for compile-time macros on the host. Browser calls remain
;; dormant until the linked module starts; no JSCL compiler/runtime is involved.
(let ((objects nil))
  (dolist (source (append *sources* (list *entry*)))
    (let* ((prepared (prepare-source source))
           (object (merge-pathnames
                    (make-pathname :name (pathname-name source) :type "o")
                    *output*)))
      (multiple-value-bind (output warnings failure)
          (compile-file prepared :output-file object :system-p t
                                 :target *target-info*)
        (declare (ignore warnings))
        (when (or failure (null output))
          (error "ECL compilation failed: ~A" source))
        (push output objects))
      (unless (equal source *entry*)
        (let ((*features* (cons :lui-ecl-host *features*)))
          (load prepared)))))
  (with-compilation-unit (:target *target-info*)
    (c:build-static-library
     (merge-pathnames "liblui-web.a" *output*)
     :lisp-files (nreverse objects) :init-name "init_lui_web")))
(ext:quit)
