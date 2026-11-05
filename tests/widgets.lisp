(defpackage #:lui.tests.widgets
  (:use #:cl #:lui.layout #:lui.frame #:lui.terminal)
  (:export #:run-tests))

(in-package #:lui.tests.widgets)

(defun test-readline ()
  (let ((context (make-terminal-context))
        (text "alpha beta gamma"))
    (labels ((draw () (setf text (lui.glass:text-field :edit text)))
             (key (&rest keys)
               (with-frame
                   (context 60 5 :events
                            (mapcar (lambda (key)
                                      (make-event :kind :key :id :edit
                                                  :key key))
                                    keys))
                 (draw)))
             (insert (value)
               (with-frame
                   (context 60 5 :events
                            (list (make-event :kind :text :id :edit
                                              :value value)))
                 (draw))))
      (with-frame (context 60 5) (draw))
      (setf (context-focus context) :edit)
      (assert (lui.widgets:text-field-focused-p context))
      (key :home :right :delete :end :left :backspace)
      (assert (string= text "apha beta gama"))
      (key :home :kill-end :yank)
      (assert (string= text "apha beta gama"))
      (key :kill-word :kill-word)
      (assert (string= text "apha "))
      (key :yank)
      (assert (string= text "apha beta gama"))
      (key :home :word-right :word-right :kill-start)
      (assert (string= text " gama"))
      (key :yank :end :transpose)
      (assert (string= text "apha beta gaam"))
      (key :home :kill-word-forward)
      (assert (string= text " beta gaam"))
      (key :yank :home :word-right :shift-word-right)
      (insert "|")
      (assert (string= text "apha| gaam"))
      (key :select-all)
      (insert (format nil "one~%two three"))
      (key :home :kill-end)
      (assert (string= text (format nil "one~%")))
      (key :yank :up :home :kill-end :kill-end)
      (assert (string= text "two three"))
      (key :yank)
      (assert (string= text (format nil "one~%two three")))))
  (assert (eq :home (lui.widgets:readline-key "a" :control t)))
  (assert (eq :select-all
              (lui.widgets:readline-key "A" :control t :shift t)))
  (assert (eq :word-left
              (lui.widgets:readline-key "ArrowLeft" :control t)))
  (assert (eq :word-right (lui.widgets:readline-key "f" :alt t)))
  ;; Selection replacement, empty-input boundaries, and shrink clamping.
  (let ((state (lui.widgets:make-edit-state :cursor 50 :anchor 50)))
    (assert (string= "" (lui.widgets:edit-text
                         "" state
                         (mapcar (lambda (key)
                                   (make-event :kind :key :key key))
                                 '(:left :backspace :delete
                                   :transpose :yank)))))
    (assert (zerop (lui.widgets:edit-state-cursor state)))))

(defun test-tabs-and-hover ()
  (let ((context (make-terminal-context))
        (selected :one))
    (labels ((draw ()
               (row ()
                 (when (lui.glass:tab :one "One"
                                      :selected-p (eq selected :one))
                   (setf selected :one))
                 (lui.glass:tab :disabled "Disabled" :disabled-p t)
                 (when (lui.glass:tab :two "Two"
                                      :selected-p (eq selected :two))
                   (setf selected :two))))
             (key (id key)
               (with-frame
                   (context 40 4 :events (list (make-event :kind :key
                                                          :id id :key key)))
                 (draw))))
      (with-frame (context 40 4) (draw))
      (setf (context-focus context) :one)
      (key :one :right)
      (assert (eq selected :two))
      (assert (eq (context-focus context) :two))
      (assert (context-focus-visible-p context))
      (key :two :right)
      (assert (eq selected :one))
      (key :one :end)
      (assert (eq selected :two))
      (key :two :home)
      (assert (eq selected :one))
      (with-frame
          (context 40 4 :events (list (make-event :kind :move :x 1 :y 0)))
        (draw)
        (assert (hovered-p :one)))
      (assert (eq :one (context-hover context)))
      (with-frame (context 40 4))
      (assert (null (context-hover context)))
      (with-frame (context 40 4) (draw))
      (setf (context-focus context) :two
            (context-focus-visible-p context) t)
      (with-frame
          (context 40 4 :events (list (make-event :kind :press :x 1 :y 0)))
        (draw))
      (assert (eq :one (context-hover context)))
      (assert (eq :two (context-focus context)))
      (assert (not (context-focus-visible-p context)))
      (with-frame (context 41 4) (draw))
      (assert (null (context-hover context))))))

(defun run-tests ()
  (test-readline)
  (test-tabs-and-hover)
  (let ((context (make-terminal-context))
        (slider 0.0)
        (checked nil)
        (text "abc"))
    (flet ((draw ()
             (setf slider
                   (lui.glass:slider :slider slider :width (fixed 20)))
             (setf checked (lui.glass:checkbox :check checked "Check"))
             (setf text (lui.motif:text-field :text text))))
      (with-frame (context 30 10) (draw))
      ;; Press/move/release can all arrive before the next UI invocation.
      (with-frame
          (context 30 10 :events
                   (list (make-event :kind :press :x 2 :y 0)
                         (make-event :kind :move :x 16 :y 0)
                         (make-event :kind :release :x 16 :y 0)))
        (draw))
      (assert (< (abs (- slider 0.8)) 0.001))
      (with-frame
          (context 30 10 :events (list (make-event :kind :move :x 1 :y 0)))
        (draw))
      (assert (< (abs (- slider 0.8)) 0.001))
      (with-frame
          (context 30 10 :events
                   (list (make-event :kind :change :id :check :value t)
                         (make-event :kind :key :id :text :key :select-all)
                         (make-event :kind :text :id :text
                                     :value "replacement")))
        (draw))
      (assert checked)
      (assert (string= text "replacement"))))
  (let ((context (make-terminal-context)))
    (flet ((draw ()
             (column (:id :scroll :width (fixed 10) :height (fixed 2)
                      :scroll-p t)
               (lui.glass:label "first")
               (lui.glass:label "second")
               (lui.glass:label "third"))))
      (with-frame (context 10 3) (draw))
      (assert (not (search "third" (render-terminal context))))
      (with-frame
          (context 10 3 :events
                   (list (make-event :kind :scroll :x 1 :y 1 :value 1)))
        (draw))
      (assert (search "second" (render-terminal context)))
      (assert (search "third" (render-terminal context)))
      (assert (not (search "first" (render-terminal context))))))
  (format t "Widget interaction and scrolling checks passed.~%")
  t)
