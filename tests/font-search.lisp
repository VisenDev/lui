;;; Run in a fresh process: sbcl --script tests/font-search.lisp
(load "scripts/setup.lisp")
(asdf:load-system "lui/native")
(assert (not (find-package :org.shirakumo.font-discovery)))

(in-package #:lui.font)
(let* ((path (truename (resolve-face :sans-serif :normal)))
       (*font-path* path)
       (*font-paths* (list (cons '(:monospace :bold) path)))
       (*font-directories* (list (uiop:pathname-directory-pathname path)))
       (*font-names* (list (list '(:sans-serif :normal)
                                "missing-lui-test-font.ttf"
                                (file-namestring path))))
       (font (open-font)))
  (unwind-protect
       (progn
         (assert (equal path (resolve-face :sans-serif :normal)))
         (assert (equal path (resolve-face :monospace :bold)))
         (assert (plusp (text-width font "Base font")))
         (assert (plusp (text-width (font-face font :monospace :bold) "Bold")))
         (assert (handler-case (progn (resolve-face :sans-serif :bold) nil)
                   (%lui.conditions:font-error () t))))
    (close-font font)))
(format t "Native font search and explicit overrides passed.~%")

;; Isolate discovery from the host's font filenames with a real copied face.
(let* ((source (truename (resolve-face :sans-serif :normal)))
       (root (merge-pathnames
              (format nil "lui-font-search-~A/" (gensym))
              (uiop:temporary-directory)))
       (nested (merge-pathnames "Fonts/TTF/LuiTest-Regular.ttf" root))
       (direct (merge-pathnames "LuiTest-Regular.ttf" root))
       (missing (merge-pathnames "missing/" root))
       (*font-path* nil)
       (*font-paths* nil)
       (*font-directories* (list missing root))
       (*font-names*
         '(((:sans-serif :normal) "LuiTest-Regular.ttf")
           ((:sans-serif :bold) "LuiTest-Regular.ttf")
           ((:monospace :normal) "LuiTest-Regular.ttf")
           ((:monospace :bold) "LuiTest-Regular.ttf"))))
  (unwind-protect
       (progn
         (ensure-directories-exist nested)
         (uiop:copy-file source nested)
         ;; A directory alias must not cause an infinite traversal.
         #+linux
         (uiop:run-program
          (list "ln" "-s" (namestring root)
                (namestring (merge-pathnames "Fonts/TTF/loop" root))))
         (dolist (family '(:sans-serif :monospace))
           (dolist (weight '(:normal :bold))
             (assert (equal (truename nested) (resolve-face family weight)))))
         (let ((font (open-font (resolve-face :sans-serif :normal))))
           (unwind-protect
                (assert (plusp (text-width font "Discovered font")))
             (close-font font)))
         ;; A fresh process discovers user fonts without configured roots.
         #+linux
         (let ((user-font (merge-pathnames
                           "fonts/TTF/LuiTest-Regular.ttf" root)))
           (ensure-directories-exist user-font)
           (uiop:copy-file source user-font)
           (unwind-protect
                (uiop:run-program
                 (list "env" (format nil "XDG_DATA_HOME=~A" root)
                       "sbcl" "--noinform" "--non-interactive"
                       "--load" "scripts/setup.lisp"
                       "--eval" "(asdf:load-system \"lui/native\")"
                       "--eval"
                       (format nil
                               "(let ((lui.font:*font-directories* nil)
                                      (lui.font:*font-names*
                                        '(((:sans-serif :normal)
                                           ~S))))
                                  (let ((font (lui.font:open-font ~S)))
                                    (lui.font:close-font font))
                                  (assert (equal ~S
                                    (funcall (find-symbol \"RESOLVE-FACE\"
                                                          :lui.font)
                                             :sans-serif :normal))))"
                               "LuiTest-Regular.ttf" user-font
                               (truename user-font)))
                 :output t :error-output t)
             (delete-file user-font)))
         ;; Direct matches and explicit overrides retain precedence.
         (uiop:copy-file source direct)
         (assert (equal (truename direct) (resolve-face :sans-serif :normal)))
         (let ((*font-paths* (list (cons '(:sans-serif :normal) source))))
           (assert (equal source (resolve-face :sans-serif :normal))))
         ;; No stale process-wide cache: removed fonts stop resolving.
         (delete-file direct)
         (delete-file nested)
         (assert (handler-case (progn (resolve-face :sans-serif :normal) nil)
                   (%lui.conditions:font-error () t))))
    #+linux
    (ignore-errors (delete-file (merge-pathnames "Fonts/TTF/loop" root)))
    (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore)))
(format t "Recursive font discovery and precedence passed.~%")
