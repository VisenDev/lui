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
(defparameter *docs-p* (equal (uiop:getenv "ECL_WEB_KIND") "docs"))
(defparameter *output*
  (if *docs-p* #p"build/docs-ecl/" #p"build/web-ecl/"))
(defparameter *entry*
  (if *docs-p* "scripts/start-docs-web.lisp"
      (or (uiop:getenv "ECL_WEB_APP") "scripts/start-demo.lisp")))
(defparameter *sources*
  '("src/01-fn.lisp"
    "scripts/ecl-web.lisp"
    "src/02-helpers.lisp"
    "src/03-layout.lisp"
    "src/04-frame.lisp"
    "src/05-widgets.lisp"
    "src/06-app.lisp"
    "src/07-interaction.lisp"
    "src/08-toolkits.lisp"
    "src/09-debug.lisp"
    "src/backend-common.lisp"
    "src/backend-web.lisp"))
(setf *sources*
      (append *sources*
              (if *docs-p*
                  '("examples/docs.lisp" "build/docs-data.lisp")
                  '("examples/seven-model.lisp" "examples/seven-circles.lisp"
                    "examples/seven-cells.lisp" "examples/seven.lisp"
                    "examples/demo.lisp"))))

(ensure-directories-exist *output*)
(pushnew :lui-ecl-web *features*)
(defparameter *target-info* (c::read-target-info *target*))
(pushnew :lui-ecl-web (cdr (assoc '*features* *target-info*)))

(load "src/01-fn.lisp")
(let ((*features* (cons :lui-ecl-host *features*)))
  (load "scripts/ecl-web.lisp"))
(load "scripts/ecl-web-reader.lisp")

(defun prepare-source (source)
  (if (member source '("src/backend-common.lisp"
                      "src/backend-web.lisp") :test #'equal)
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
