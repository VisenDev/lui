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
                  ((:button "a" :on-activate 3))
                  ((:label "a" :padding (:units "bad")))))
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

(defun test-styling ()
  (let ((context (%lui.tests.support:make-test-context))
        (count 0))
    (lui:with-frame (context 80 30)
      (lui.retained:draw
       '((:panel (:padding 3 :gap 2)
          (:text-field :id :styled :padding 2 :font-size 18
           :font-weight :bold :foreground "#123456"
           :background "#fedcba" :radius 4 :default-value "Styled")))))
    (%lui.layout:walk-elements
     (%lui.frame:context-root context)
     (lambda (node)
       (let ((widget (%lui.layout:element-content node)))
         (when (and (%lui.widgets:widget-p widget)
                    (eq :text-field (%lui.widgets:widget-kind widget)))
           (incf count)
           (assert (= 2 (%lui.layout:element-padding node)))
           (assert (= 18 (%lui.widgets:widget-font-size widget)))
           (assert (eq :bold (%lui.widgets:widget-font-weight widget)))
           (assert (= 4 (%lui.widgets:widget-radius widget)))
           (assert (equal "#123456"
                          (%lui.widgets:widget-color widget :foreground)))
           (assert (equal "#fedcba"
                          (%lui.widgets:widget-color widget :background)))))))
    (assert (= count 1))))

(defun test-deferred-callbacks ()
  (let* ((context (%lui.tests.support:make-test-context))
         (order nil)
         (tree nil))
    (setf tree
          (list (list :button "First" :id :first :on-activate
                      (lambda ()
                        (push :first order)
                        (setf (cdr tree) nil)))
                (list :button "Second" :id :second :on-activate
                      (lambda () (push :second order)))
                '(:label "Tail")))
    (flet ((frame (&optional events)
             (lui:with-frame (context 80 30 :events events)
               (lui.retained:draw tree))))
      (frame)
      (frame (loop :for key :in '(:first :second)
                   :collect (%lui.frame:make-event
                             :kind :activate :id (retained-id key context))))
      ;; A callback removing later siblings cannot skip their declarations.
      (assert (equal (reverse order) '(:first :second)))
      (assert (%lui.tests.support:has-text-p context "Tail"))
      (assert (%lui.frame:context-next-frame context))
      (frame)
      (assert (not (%lui.tests.support:has-text-p context "Tail")))
      (assert (equal (reverse order) '(:first :second))))))

(defun test-discarded-callbacks ()
  (let* ((context (%lui.tests.support:make-test-context))
         (calls 0)
         (tree (list (list :button "Go" :id :go :on-activate
                           (lambda () (incf calls))))))
    (lui:with-frame (context 80 30) (lui.retained:draw tree))
    (let ((id (retained-id :go context)))
      (setf (cdr tree) (list '(:unknown)))
      (assert
       (handler-case
           (progn
             (lui:with-frame
                 (context 80 30 :events
                          (list (%lui.frame:make-event :kind :activate :id id)))
               (lui.retained:draw tree))
             nil)
         (lui:configuration-error () t))))
    (assert (zerop calls))
    (setf (cdr tree) nil)
    (lui:with-frame (context 80 30) (lui.retained:draw tree))
    (assert (zerop calls))))

(defun test-load-time-spacing ()
  (let ((tree '((:text-field :padding (:units 2) :default-value "Units"))))
    (dolist (unit '(1 12))
      (let ((context (%lui.tests.support:make-test-context))
            (lui:*unit* unit)
            (found nil))
        (lui:with-frame (context 100 100) (lui.retained:draw tree))
        (%lui.layout:walk-elements
         (%lui.frame:context-root context)
         (lambda (node)
           (when (%lui.widgets:widget-p (%lui.layout:element-content node))
             (setf found t)
             (assert (= (* 2 unit) (%lui.layout:element-padding node))))))
        (assert found)))
    (assert (equal (getf (rest (first tree)) :padding) '(:units 2)))))

(defun run-tests ()
  (test-values-and-identity)
  (test-activation-and-containers)
  (test-invalid-trees)
  (test-circular-tree)
  (test-styling)
  (test-load-time-spacing)
  (test-deferred-callbacks)
  (test-discarded-callbacks)
  (format t "Retained descriptions, callbacks, identity and removal passed.~%"))
