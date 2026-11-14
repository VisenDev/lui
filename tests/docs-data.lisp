(defpackage #:%lui.tests.docs-data
  (:use #:cl)
  (:export #:run-tests))
(in-package #:%lui.tests.docs-data)

(defun entry (entries package name)
  (find-if (lambda (item)
             (and (string= package (getf item :package))
                  (string= name (getf item :name))))
           entries))

(defun run-tests ()
  (let ((fixture "build/docs-fixture.lisp")
        (output "build/docs-fixture-data.lisp"))
    (unwind-protect
         (progn
           (with-open-file (stream fixture :direction :output
                                          :if-exists :supersede)
             (write-string
              "(defpackage #:docs-fixture
  (:use #:cl) (:export #:typed #:browser #:native #:sample #:make-sample
                      #:sample-value #:binding #:access #:*setting*))
(in-package #:docs-fixture)
(error \"Sources must never be evaluated.\")
(fn (typed integer) ((value integer) &key ((limit integer) 10))
  \"Typed documentation.\" (unknown.platform:call value limit))
#+jscl (defun browser (node) #j:Object #j\"raw:JS\")
#+darwin (defun native (window) window)
(defstruct sample \"Sample structure.\" (value 3 :type integer))
(cffi:defcfun (\"binding\" binding) :int (pointer :pointer))
(defun access (object) \"Getter.\" object)
(defun (setf access) (value object) value)
(defvar *setting*)
(setf (documentation '*setting* 'variable) \"Setting documentation.\")
(defun private () nil)
(defpackage #:docs-internal (:use #:cl) (:export #:shared))
(in-package #:docs-internal)
(defun shared (value) \"Public reexport from an internal module.\" value)
(defpackage #:docs-reexport
  (:use #:docs-fixture) (:import-from #:docs-internal #:shared)
  (:export #:typed #:shared))
(defpackage #:docs-interface (:use #:cl) (:export #:implemented))
(defpackage #:docs-implementation
  (:use #:cl) (:import-from #:docs-interface #:implemented))
(in-package #:docs-implementation)
(defun implemented (value) \"Implementation of an imported public symbol.\" value)
(defun (setf implemented) (new-value object) new-value)
" stream))
           (let* ((paths (list (pathname fixture)))
                  (policy '(("docs-fixture" . :all)
                            ("docs-reexport" . :all)
                            ("docs-interface" . :all)))
                  (entries (%lui.docs.data:collect-entries
                            paths policy))
                  (typed (entry entries "docs-fixture" "TYPED"))
                  (access (entry entries "docs-fixture" "ACCESS")))
             (assert (= 12 (length entries)))
             (assert (string= "Implementation of an imported public symbol."
                              (getf (entry entries "docs-interface"
                                           "IMPLEMENTED") :documentation)))
             (assert (search "((setf implemented) new-value object)"
                             (getf (entry entries "docs-interface"
                                          "IMPLEMENTED") :signature)))
             (assert (notany (lambda (item)
                               (string= "docs-internal"
                                        (getf item :package))) entries))
             (assert (string= "Public reexport from an internal module."
                              (getf (entry entries "docs-reexport" "SHARED")
                                    :documentation)))
             (assert (null (find-package :docs-fixture)))
             (assert (equal entries
                            (%lui.docs.data:collect-entries
                             paths policy)))
             (assert (string= "(typed value &key (limit 10))"
                              (getf typed :signature)))
             (assert (string= "Typed documentation."
                              (getf typed :documentation)))
             (assert (search "(access object)" (getf access :signature)))
             (assert (search "((setf access) value object)"
                             (getf access :signature)))
             (assert (entry entries "docs-fixture" "BROWSER"))
             (assert (entry entries "docs-fixture" "NATIVE"))
             (assert (string= "Setting documentation."
                              (getf (entry entries "docs-fixture" "*SETTING*")
                                    :documentation)))
             (assert (string= "(binding pointer)"
                              (getf (entry entries "docs-fixture" "BINDING")
                                    :signature)))
             (assert (string= "(make-sample &key (value 3))"
                              (getf (entry entries "docs-fixture"
                                           "MAKE-SAMPLE") :signature)))
             (assert (string= "Typed documentation."
                              (getf (entry entries "docs-reexport" "TYPED")
                                    :documentation)))
             (%lui.docs.data:write-data entries output)
             (let ((first (uiop:read-file-string output)))
               (%lui.docs.data:write-data entries output)
               (assert (string= first (uiop:read-file-string output)))))
           ;; Read-time evaluation is rejected, rather than executed.
           (with-open-file (stream fixture :direction :output
                                          :if-exists :supersede)
             (write-string "#.(error \"Do not evaluate.\")" stream))
           (assert (handler-case
                       (progn (%lui.docs.data:collect-entries
                               (list (pathname fixture))) nil)
                     (reader-error () t))))
      (when (probe-file fixture) (delete-file fixture))
      (when (probe-file output) (delete-file output))))
  (let* ((entries (%lui.docs.data:collect-entries))
         (button (entry entries "lui" "BUTTON")))
    (dolist (item entries)
      (assert (plusp (length (getf item :documentation))) ()
              "Missing docstring for ~A:~A."
              (getf item :package) (getf item :name)))
    (dolist (scope %lui.docs.data::*public-api*)
      (when (listp (cdr scope))
        (dolist (name (cdr scope))
          (assert (entry entries (car scope) name) ()
                  "Stale public API entry ~A:~A." (car scope) name))))
    (dolist (name '("SPACER" "HR" "VR"))
      (assert (entry entries "lui" name)))
    (dolist (name '("RENDERER" "FONT" "SET-DEBUGGER-ENABLED"
                    "RENDER-TERMINAL" "RENDER-PDF"))
      (assert (null (entry entries "lui" name))))
    (assert (eq :macro (getf button :kind)))
    (assert (string= "(button text &optional options)"
                     (getf button :signature)))
    (assert (plusp (length (getf button :documentation))))
    (dolist (pair '(("lui" "MOUNT") ("lui.font" "*FONT-PATH*")
                    ("lui.draw" "RENDERER-POLYGONS")
                    ("lui.toolkit" "REGISTER-TOOLKIT-RENDERING")
                    ("lui.palette" "PALETTE-FOREGROUND")
                    ("lui.glass" "*GLASS-DEFAULTS*")))
      (assert (entry entries (first pair) (second pair))))
    (dolist (package '("%lui.fn" "%lui.widgets" "%lui.gl"
                       "%lui.wayland-protocol" "lui.web.style"
                       "%lui.wayland" "%lui.x11" "%lui.win32" "%lui.cocoa"))
      (assert (notany (lambda (item)
                        (string= package (getf item :package))) entries)))
    (dolist (pair '(("%lui.layout" "ELEMENT-CHILDREN")
                    ("%lui.frame" "BEGIN-FRAME")
                    ("%lui.frame" "CONTEXT-STATE")
                    ("lui.draw" "PAINT-FRAME")
                    ("lui.font" "FONT-LOADER")))
      (assert (null (entry entries (first pair) (second pair)))))
    (assert (null (find-package :%lui.cocoa)))
    (assert (null (find-package :%lui.win32)))
    (assert (null (find-package :lui.web))))
  (format t "Documentation source extraction tests passed.~%"))
