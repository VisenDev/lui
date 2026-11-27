(defpackage #:%lui.tests.win32-keys
  (:use #:cl))
(in-package #:%lui.tests.win32-keys)

(defun load-key-translator ()
  "Load the production's pure key functions on hosts without Windows DLLs."
  (let ((package (find-package :%lui.win32)))
    (unless (and package (fboundp (find-symbol "KEY-INPUT" package)))
      (let ((*package* *package*))
        (with-open-file (stream "src/backend-win32.lisp")
          (loop :for form := (read stream nil stream)
                :until (eq form stream)
                :do (cond
                      ((member (first form) '(defpackage in-package))
                       (eval form))
                      ((and (eq (first form) '%lui.fn:fn)
                            (consp (second form))
                            (member (symbol-name (first (second form)))
                                    '("KEY-NAME" "KEY-INPUT") :test #'string=))
                       (eval form)))))))))

(load-key-translator)

(defun run-tests ()
  "Reject virtual-key/ASCII collisions while retaining genuine chords."
  (let ((translate (symbol-function (find-symbol "KEY-INPUT" :%lui.win32))))
    (dolist (editing '(nil t))
      (assert (eq lui.key:kb-menu
                  (lui:event-key
                   (funcall translate 93 nil nil nil editing))))
      (assert (lui:event-shortcut-p
               (funcall translate 121 nil nil t editing)
               lui.key:f10 :shift t))
      (dolist (entry '((36 . lui.key:home) (35 . lui.key:end)
                       (38 . lui.key:up) (40 . lui.key:down)
                       (46 . lui.key:delete)))
        (dolist (shift '(nil t))
          (let ((event (funcall translate (car entry) t nil shift editing)))
            (assert (eq (cdr entry) (lui:event-key event)))
            (assert (= (if shift 3 2) (lui:event-modifiers event)))))))
    ;; Unsupported F keys/navigation must never alias Ctrl+letters/digits.
    (dolist (code (append '(33 34 45) (loop :for code :from 112 :to 135
                                           :unless (= code 121)
                                           :collect code)))
      (assert (null (funcall translate code t nil nil nil))))
    (dolist (entry '((48 . lui.key:zero) (57 . lui.key:nine)
                     (65 . lui.key:a) (83 . lui.key:s) (90 . lui.key:z)))
      (assert (lui:event-shortcut-p
               (funcall translate (car entry) t nil nil nil)
               (cdr entry) :control t)))
    (assert (eq lui.key:home
                (lui:event-key (funcall translate 65 t nil nil t))))
    (assert (eq lui.key:word-left
                (lui:event-key (funcall translate 37 t nil nil t))))
    (assert (null (funcall translate 66 t t nil t))))
  (format t "Win32 navigation/character shortcut separation passed.~%"))

(run-tests)
