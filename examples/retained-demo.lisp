(defpackage #:%lui.example.retained-demo
  (:use #:cl)
  (:export #:make-demo #:main))
(in-package #:%lui.example.retained-demo)

(%lui.fn:fn (make-card list) ((number integer))
  "Create a keyed nested row whose editable note survives sibling reordering."
  (list :row (list :id number :gap (lui:units 1) :width (lui:grow))
        (list :checkbox (format nil "Item ~D" number) :id :checked)
        (list :text-field :id :note :width (lui:grow)
              :default-value (format nil "Note for item ~D" number))))

(%lui.fn:fn (make-demo function) ()
  "Return a retained tree playground with independent state for each instance.
Callbacks enqueue edits. After DRAW finishes, edits mutate the stored list tree
and request another frame. The next frame renders the changed data. Add/remove
and reverse keyed rows to inspect how their checkbox and editor values behave."
  (let ((tree nil)
        (pending nil)
        (greeting (list :label "Hello, retained world!"))
        (counter (list :label "Clicks: 0"))
        (cards nil)
        (preview (list :label ""))
        (status (list :label "Ready. Edit the name or press a button."))
        (clicks 0)
        (serial 2))
    (labels
        ((enqueue (edit)
           (push edit pending))
         (report-edit (message)
           (setf (second status) message
                 (second preview)
                 (format nil "~S~%~S~%Row keys: ~S"
                         greeting counter
                         (mapcar (lambda (node) (getf (second node) :id))
                                 (cddr cards)))))
         (rename-greeting (name)
           (enqueue (lambda ()
                      (setf (second greeting) (format nil "Hello, ~A!" name))
                      (report-edit "Changed the greeting node's text."))))
         (increment ()
           (enqueue (lambda ()
                      (setf (second counter)
                            (format nil "Clicks: ~D" (incf clicks)))
                      (report-edit "Changed the counter node's text."))))
         (add-item ()
           (enqueue (lambda ()
                      (setf (cddr cards)
                            (append (cddr cards)
                                    (list (make-card (incf serial)))))
                      (report-edit "Appended a new keyed row."))))
         (reverse-items ()
           (enqueue (lambda ()
                      (setf (cddr cards) (reverse (cddr cards)))
                      (report-edit "Reversed rows; keys preserve note state."))))
         (remove-item ()
           (enqueue (lambda ()
                      (setf (cddr cards) (butlast (cddr cards)))
                      (report-edit "Removed the last row, if present."))))
         (initialize-tree ()
           (setf cards
                 (list :column (list :id :items :gap (lui:units 1)
                                     :width (lui:grow))
                       (make-card 1) (make-card 2))
                 tree
                 (list
                  (list :column
                        (list :id :root :width (lui:grow) :height (lui:grow)
                              :scroll-p t :padding (lui:units 1)
                              :gap (lui:units 1))
                        '(:label "Retained data playground")
                        '(:label "Edit a stored tree and watch LUI redraw it.")
                        (list :row (list :gap (lui:units 2) :width (lui:grow))
                              (list :panel
                                    (list :id :editor :width (lui:grow)
                                          :padding (lui:units 1)
                                          :gap 0)
                                    '(:label "Callbacks update data")
                                    greeting
                                    (list :text-field :id :name
                                          :default-value "retained world"
                                          :width (lui:grow)
                                          :on-change #'rename-greeting)
                                    (list :row (list :gap (lui:units 1))
                                          (list :button "Count" :id :count
                                                :on-activate #'increment)
                                          counter))
                              (list :panel
                                    (list :id :data :width (lui:grow)
                                          :padding (lui:units 1))
                                    '(:label "Current tree data")
                                    preview))
                        (list :panel
                              (list :id :collection :width (lui:grow)
                                    :padding (lui:units 1)
                                    :gap 0)
                              '(:label "Nested rows with stable IDs")
                              '(:label "Edit notes, then reverse the rows.")
                              (list :row (list :gap (lui:units 1))
                                    (list :button "Add row" :id :add
                                          :on-activate #'add-item)
                                    (list :button "Reverse" :id :reverse
                                          :on-activate #'reverse-items)
                                    (list :button "Remove last" :id :remove
                                          :on-activate #'remove-item))
                              cards)
                        status)))
           (report-edit "Ready. Edit the name or press a button.")))
      (lambda ()
        (unless tree (initialize-tree))
        (lui:with-toolkit (:qt)
          (lui.retained:draw tree))
        ;; Do not alter a child list while DRAW is traversing it.
        (when pending
          (let ((edits (nreverse pending)))
            (setf pending nil)
            (dolist (edit edits) (funcall edit)))
          (lui:request-frame))
        (values)))))

(%lui.fn:fn (main t) ()
  "Run the retained demo; launch with make retained-demo PLATFORM=terminal
or a native graphical backend. The same stored tree drives every backend."
  (lui:run (make-demo) :title "LUI retained data playground"))
