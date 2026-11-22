(defpackage #:%lui.tests.retained
  (:use #:cl)
  (:export #:run-tests))
(in-package #:%lui.tests.retained)

(defun retained-id (key context)
  (lui:with-key :retained
    (lui:with-key (list :key key)
      (lui:widget-id key context))))

(defun test-values-and-identity ()
  (let* ((context (%lui.tests.support:make-test-context))
         (changes nil)
         (field (list :text-field :id :edit :default-value "start"
                      :on-change (lambda (value) (push value changes))))
         (tree (list field '(:label "other"))))
    (flet ((frame (&optional events)
             (lui:with-frame (context 80 20 :events events)
               (lui.retained:draw tree))))
      (frame)
      (let ((id (retained-id :edit context)))
        (frame (list (%lui.frame:make-event :kind :text :id id :value "!")))
        (assert (equal changes '("start!")))
        (setf tree (reverse tree))
        (frame)
        (assert (equal id (retained-id :edit context)))
        (assert (%lui.tests.support:has-text-p context "start!"))
        (assert (equal (getf (rest field) :default-value) "start"))
        (setf tree nil)
        (frame)
        (setf tree (list field))
        (frame)
        (assert (%lui.tests.support:has-text-p context "start"))
        (assert (not (%lui.tests.support:has-text-p context "start!")))))))

(defun test-activation-and-containers ()
  (let ((context (%lui.tests.support:make-test-context))
        (clicks 0))
    (flet ((frame (&optional events)
             (lui:with-frame (context 80 20 :events events)
               (lui.retained:draw
                (list (list :column '(:gap 1)
                            (list :button "hello" :id :hello
                                  :on-activate (lambda () (incf clicks)))
                            '(:label "hi")))))))
      (frame)
      (assert (%lui.tests.support:has-text-p context "hello"))
      (assert (%lui.tests.support:has-text-p context "hi"))
      (frame (list (%lui.frame:make-event :kind :activate
                                    :id (lui:with-key :retained
                                          (lui:with-key (list :position 0)
                                            (lui:with-key (list :key :hello)
                                              (lui:widget-id :hello context)))))))
      (assert (= clicks 1))
      (frame)
      (assert (= clicks 1)))))

(defun test-invalid-trees ()
  (dolist (tree '(((:unknown "x")) ((:button)) ((:label "x" :width))
                  ((:button "a" :id :same) (:label "b" :id :same))
                  ((:button "a" :on-activate 3))))
    (let ((context (%lui.tests.support:make-test-context)))
      (assert
       (handler-case
           (progn (lui:with-frame (context 80 20)
                    (lui.retained:draw tree))
                  nil)
         (lui:configuration-error () t))))))

(defun test-circular-tree ()
  (let ((node (list :column nil))
        (context (%lui.tests.support:make-test-context)))
    (setf (cddr node) (list node))
    (assert
     (handler-case
         (progn (lui:with-frame (context 80 20)
                  (lui.retained:draw (list node)))
                nil)
       (lui:configuration-error () t)))))

(defun run-tests ()
  (test-values-and-identity)
  (test-activation-and-containers)
  (test-invalid-trees)
  (test-circular-tree)
  (format t "Retained descriptions, callbacks, identity and removal passed.~%"))
