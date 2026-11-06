(defpackage #:lui.tests.docs
  (:use #:cl #:lui.layout #:lui.frame #:lui.widgets #:lui.terminal)
  (:export #:run-tests))
(in-package #:lui.tests.docs)

(defun nodes (context predicate)
  (let ((result nil))
    (walk-elements
     (context-root context)
     (lambda (node) (when (funcall predicate node) (push node result))))
    (nreverse result)))

(defun has-label (context text)
  (nodes context
         (lambda (node)
           (let ((widget (element-content node)))
             (and (widget-p widget) (eq (widget-kind widget) :label)
                  (string= text (widget-text widget)))))))

(defun frame (context draw &rest events)
  (with-frame (context 100 40 :events events) (funcall draw)))

(defun run-tests ()
  (let* ((lui:*unit* 1)
         (entries
           (loop :for index :below 400
                 :collect
                 (list :package (if (evenp index) "alpha" "beta")
                       :name (format nil "ENTRY~D" index) :kind :function
                       :signature (format nil "(entry~D value)" index)
                       :documentation
                       (if (zerop index)
                           (format nil "~{~A ~}"
                                   (make-list 1000 :initial-element "Long"))
                           (format nil "Documentation ~D" index)))))
         (draw (lui.docs:make-docs :entries entries))
         (other (lui.docs:make-docs :entries entries))
         (context (make-terminal-context))
         (second (make-terminal-context)))
    (frame context draw)
    (frame second other)
    (assert (has-label context "Getting started"))
    (frame context draw
           (make-event :kind :activate :id '(:docs-package "alpha")))
    (assert (has-label context "200 API entries"))
    (assert (has-label context "alpha:ENTRY0"))
    (assert (plusp (element-scroll-limit-y
                   (first (nodes context
                                 (lambda (node)
                                   (eq :docs-detail (element-id node))))))))
    (let ((rows (nodes context
                       (lambda (node)
                         (let ((id (element-id node)))
                           (and (consp id) (eq (first id) :docs-entry)))))))
      ;; A large reference declares only a viewport of actual control rows.
      (assert (< 0 (length rows) 20))
      (assert (every (lambda (node) (evenp (second (element-id node))))
                     rows)))
    (frame context draw (make-event :kind :change :id :docs-search
                                    :value "Documentation 198"))
    (assert (has-label context "1 API entries"))
    (assert (has-label context "alpha:ENTRY198"))
    (frame context draw
           (make-event :kind :change :id :docs-search :value "absent"))
    (assert (has-label context "No matching entries."))
    (frame second other)
    (assert (has-label second "Getting started"))
    (assert (not (has-label second "No matching entries."))))
  (let ((lui:*unit* 1) (context (make-terminal-context))
        (draw (lui.docs:make-docs :entries nil)))
    (frame context draw (make-event :kind :activate
                                    :id '(:docs-package nil)))
    (assert (has-label context "0 API entries"))
    (assert (has-label context "No matching entries."))
    (assert (has-label context "Choose an API entry from the list.")))
  (format t "Documentation browser tests passed.~%"))
