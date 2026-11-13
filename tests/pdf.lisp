(defpackage #:%lui.tests.pdf
  (:use #:cl)
  (:export #:run-tests))
(in-package #:%lui.tests.pdf)

(defun run-tests ()
  (uiop:with-temporary-file (:pathname path :type "pdf")
    (let ((lui.pdf:*pdf-output* path) (frames 0) (pdf:*compress-streams* nil))
      (assert (equal path
                (lui:run (lambda () (incf frames) (lui:button "Save"
                                                    (lui:opt :id :save)))
                              :backend :pdf :width 180 :height 60)))
      (assert (= frames 1))
      (let ((file (uiop:read-file-string path :external-format :latin-1)))
        (dolist (token '("%PDF-" "/Count 1" "/MediaBox [ 0 0 180 60 ]"
                         " W" " rg" " l" "%%EOF"))
          (assert (search token file)))))))
