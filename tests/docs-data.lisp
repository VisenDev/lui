(defpackage #:lui.tests.docs-data
  (:use #:cl)
  (:export #:run-tests))
(in-package #:lui.tests.docs-data)

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
(defpackage #:docs-reexport (:use #:docs-fixture) (:export #:typed))
" stream))
           (let* ((paths (list (pathname fixture)))
                  (entries (lui.docs.generator:collect-entries paths))
                  (typed (entry entries "docs-fixture" "TYPED"))
                  (access (entry entries "docs-fixture" "ACCESS")))
             (assert (= 10 (length entries)))
             (assert (null (find-package :docs-fixture)))
             (assert (equal entries
                            (lui.docs.generator:collect-entries paths)))
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
             (lui.docs.generator:write-data entries output)
             (let ((first (uiop:read-file-string output)))
               (lui.docs.generator:write-data entries output)
               (assert (string= first (uiop:read-file-string output)))))
           ;; Read-time evaluation is rejected, rather than executed.
           (with-open-file (stream fixture :direction :output
                                          :if-exists :supersede)
             (write-string "#.(error \"Do not evaluate.\")" stream))
           (assert (handler-case
                       (progn (lui.docs.generator:collect-entries
                               (list (pathname fixture))) nil)
                     (reader-error () t))))
      (when (probe-file fixture) (delete-file fixture))
      (when (probe-file output) (delete-file output))))
  (let* ((entries (lui.docs.generator:collect-entries))
         (button (entry entries "lui" "BUTTON")))
    (assert (> (length entries) 250))
    (assert (string= "(button id text &optional options)"
                     (getf button :signature)))
    (assert (plusp (length (getf button :documentation))))
    (dolist (pair '(("lui.web" "MOUNT") ("lui.cocoa" "RUN-COCOA")
                    ("lui.win32" "RUN-WIN32")
                    ("lui.wayland-protocol" "DESTROY-PROXY")))
      (assert (entry entries (first pair) (second pair))))
    (assert (null (find-package :lui.cocoa)))
    (assert (null (find-package :lui.win32)))
    (assert (null (find-package :lui.web))))
  (format t "Documentation source extraction tests passed.~%"))
