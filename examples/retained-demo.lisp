(defpackage #:%lui.example.retained-demo
  (:use #:cl)
  (:export #:*tree* #:draw #:reset-demo #:main))
(in-package #:%lui.example.retained-demo)

;; This example intentionally owns one global UI, editable from the REPL.
(defvar *tree* nil "The retained UI tree; built once with backend spacing units.")
(defvar *toolkit* nil)
(defvar *palette* nil)
(defvar *toolkit-button* nil)
(defvar *palette-button* nil)
(defvar *metrics* nil)
(defvar *greeting* nil)
(defvar *counter* nil)
(defvar *cards* nil)
(defvar *preview* nil)
(defvar *status* nil)
(defvar *clicks* nil)
(defvar *serial* nil)

(defun make-card (number)
  "Create a keyed nested row whose editable note survives sibling reordering."
  (list :row (list :id number :gap (lui:units 1) :width (lui:grow))
        (list :checkbox (format nil "Item ~D" number) :id :checked)
        (list :text-field :id :note :width (lui:grow)
              :padding (lui:units 0.5)
              :default-value (format nil "Note for item ~D" number))))

(defun reset-demo ()
  "Reset the single demo's data before opening a new window."
  (setf *tree* nil
        *toolkit* :qt
        *palette* :default
        *toolkit-button* (list :button "" :id :toolkit)
        *palette-button* (list :button "" :id :palette)
        *metrics* (list :label "" :id :metrics)
        *greeting* (list :label "Hello, retained world!")
        *counter* (list :label "Clicks: 0")
        *cards* nil
        *preview* (list :label "")
        *status* (list :label "Ready. Edit the name or press a button.")
        *clicks* 0
        *serial* 2)
  (values))

(defun report-edit (message)
  "Refresh the status and data preview after an edit."
  (setf (second *status*) message
        (second *preview*)
        (format nil "~S~%~S~%Row keys: ~S"
                *greeting* *counter*
                (mapcar (lambda (node) (getf (second node) :id))
                        (cddr *cards*))))
  (values))

(defun rename-greeting (name)
  "Update the greeting node from the name field."
  (setf (second *greeting*) (format nil "Hello, ~A!" name))
  (report-edit "Changed the greeting node's text.")
  (values))

(defun increment ()
  "Increment the counter by editing its retained label."
  (setf (second *counter*) (format nil "Clicks: ~D" (incf *clicks*)))
  (report-edit "Changed the counter node's text.")
  (values))

(defun add-item ()
  "Append a row with a fresh stable identity."
  (setf (cddr *cards*)
        (append (cddr *cards*) (list (make-card (incf *serial*)))))
  (report-edit "Appended a new keyed row.")
  (values))

(defun reverse-items ()
  "Reorder existing row nodes without changing their identities."
  (setf (cddr *cards*) (reverse (cddr *cards*)))
  (report-edit "Reversed rows; keys preserve note state.")
  (values))

(defun remove-item ()
  "Remove the last row if one is present."
  (setf (cddr *cards*) (butlast (cddr *cards*)))
  (report-edit "Removed the last row, if present.")
  (values))

(defun cycle-toolkit ()
  "Select the next toolkit for the next frame."
  (let ((names '(:glass :motif :garnet :macos :qt)))
    (setf *toolkit* (or (second (member *toolkit* names))
                      (first names))))
  (values))

(defun cycle-palette ()
  "Select the next palette independently of the toolkit."
  (let ((names (lui:available-palettes)))
    (setf *palette*
          (aref names (mod (1+ (position *palette* names))
                           (length names)))))
  (values))

(defun initialize-tree ()
  "Build the global tree once using the active backend spacing units."
  (setf (getf (cddr *toolkit-button*) :on-activate) #'cycle-toolkit
        (getf (cddr *palette-button*) :on-activate) #'cycle-palette)
  (setf *cards*
        (list :column (list :id :items :gap (lui:units 1)
                            :width (lui:grow))
              (make-card 1) (make-card 2))
        *tree*
        (list
         (list :panel
               (list :id :root :width (lui:grow) :height (lui:grow)
                     :scroll-p t :padding (lui:units 2)
                     :radius 0 :frost 0 :opacity 1
                     :gap (lui:units 1))
               '(:label "Retained data playground" :font-weight :bold)
               (list :row (list :gap (lui:units 1)
                                :cross-align :center)
                     *toolkit-button* *palette-button*)
               *metrics*
               '(:label "Edit a stored tree and watch LUI redraw it.")
               (list :row (list :gap (lui:units 2) :width (lui:grow))
                     (list :panel
                           (list :id :editor :width (lui:grow)
                                 :padding (lui:units 2)
                                 :gap (lui:units 1))
                           '(:label "Callbacks update data")
                           *greeting*
                           (list :text-field :id :name
                                 :default-value "retained world"
                                 :padding (lui:units 0.5)
                                 :width (lui:grow)
                                 :on-change #'rename-greeting)
                           (list :row (list :gap (lui:units 1))
                                 (list :button "Count" :id :count
                                       :on-activate #'increment)
                                 *counter*))
                     (list :panel
                           (list :id :data :width (lui:grow)
                                 :padding (lui:units 2))
                           '(:label "Current tree data")
                           *preview*))
               (list :panel
                     (list :id :collection :width (lui:grow)
                           :padding (lui:units 2)
                           :gap (lui:units 1))
                     '(:label "Nested rows with stable IDs")
                     '(:label "Edit notes, then reverse the rows.")
                     (list :row (list :gap (lui:units 1))
                           (list :button "Add row" :id :add
                                 :on-activate #'add-item)
                           (list :button "Reverse" :id :reverse
                                 :on-activate #'reverse-items)
                           (list :button "Remove last" :id :remove
                                 :on-activate #'remove-item))
                     *cards*)
               *status*)))
  (report-edit "Ready. Edit the name or press a button.")
  (values))

(defun draw ()
  "Render the global tree each frame; callbacks edit it after traversal."
  ;; The backend establishes LUI:*UNIT* when it enters the first frame.
  (unless *tree* (initialize-tree))
  (setf (second *toolkit-button*)
        (format nil "Toolkit: ~A" (if (eq *toolkit* :macos) "macOS"
                                     (string-capitalize *toolkit*)))
        (second *palette-button*)
        (format nil "Palette: ~A" (string-capitalize *palette*))
        (second *metrics*) (lui:frame-rate-label))
  (lui:with-toolkit (*toolkit*)
    (lui:with-palette (*palette*)
      (let ((colors (lui.toolkit:toolkit-palette)))
        (setf (getf (second (first *tree*)) :background)
              (getf colors :window-background
                    (getf colors :background))))
      (lui.retained:draw *tree*)))
  (values))

(defun main (&key (interactive t))
  "Open one retained demo. Initialization runs once; the lambda runs per frame."
  (reset-demo)
  (lui:run (lambda () (draw))
           :title "LUI retained data playground" :interactive interactive))
