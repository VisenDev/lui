(defpackage #:%lui.example.retained-demo
  (:use #:cl)
  (:export #:*tree* #:draw #:reset-demo #:main))
(in-package #:%lui.example.retained-demo)

;; This example intentionally owns one global UI, editable from the REPL.
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
  (lui.retained:make-row :id number :gap '(:units 1) :width (lui:grow)
   :children
   (lui.retained:nodes
    (lui.retained:make-checkbox :text (format nil "Item ~D" number)
                       :id :checked)
    (lui.retained:make-text-field :id :note :width (lui:grow)
                       :padding '(:units 0.5)
                       :default-value (format nil "Note for item ~D"
                                              number)))))

(defun report-edit (message)
  "Refresh the status and data preview after an edit."
  (setf (lui.retained:label-text *status*) message
        (lui.retained:label-text *preview*)
        (format nil "Greeting text: ~S~%Counter text: ~S~%Row keys: ~S"
                (lui.retained:label-text *greeting*)
                (lui.retained:label-text *counter*)
                (map 'list #'lui.retained:node-id
                     (lui.retained:column-children *cards*))))
  (values))

(defun rename-greeting (name)
  "Update the greeting node from the name field."
  (setf (lui.retained:label-text *greeting*) (format nil "Hello, ~A!" name))
  (report-edit "Changed the greeting node's text.")
  (values))

(defun increment ()
  "Increment the counter by editing its retained label."
  (setf (lui.retained:label-text *counter*)
        (format nil "Clicks: ~D" (incf *clicks*)))
  (report-edit "Changed the counter node's text.")
  (values))

(defun add-item ()
  "Append a row with a fresh stable identity."
  (let* ((children (lui.retained:column-children *cards*))
         (extended (make-array (1+ (length children))
                               :element-type 'lui.retained:node
                               :initial-element (make-card (incf *serial*)))))
    (replace extended children)
    (setf (lui.retained:column-children *cards*) extended))
  (report-edit "Appended a new keyed row.")
  (values))

(defun reverse-items ()
  "Reorder existing row nodes without changing their identities."
  (setf (lui.retained:column-children *cards*)
        (reverse (lui.retained:column-children *cards*)))
  (report-edit "Reversed rows; keys preserve note state.")
  (values))

(defun remove-item ()
  "Remove the last row if one is present."
  (let ((children (lui.retained:column-children *cards*)))
    (setf (lui.retained:column-children *cards*)
          (subseq children 0 (max 0 (1- (length children))))))
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

;; UI data: allocated at load time, independently of rendering.
;; Unit descriptors are resolved by the retained layer for the active backend.
(defparameter *toolkit-button*
  (lui.retained:make-button :text "Toolkit: Qt" :id :toolkit
                     :on-activate 'cycle-toolkit))
(defparameter *palette-button*
  (lui.retained:make-button :text "Palette: Default" :id :palette
                     :on-activate 'cycle-palette))
(defparameter *metrics* (lui.retained:make-label :text "" :id :metrics))
(defparameter *greeting*
  (lui.retained:make-label :text "Hello, retained world!"))
(defparameter *counter* (lui.retained:make-label :text "Clicks: 0"))
(defparameter *preview* (lui.retained:make-label :text ""))
(defparameter *status* (lui.retained:make-label :text "Ready."))
(defparameter *cards*
  (lui.retained:make-column :id :items :gap '(:units 1) :width (lui:grow)
                     :children (lui.retained:nodes (make-card 1) (make-card 2))))

(defparameter *tree*
  (lui.retained:nodes
   (lui.retained:make-panel :id :root :width (lui:grow) :height (lui:grow)
    :scroll-p t :padding '(:units 2) :gap '(:units 1)
    :radius 0 :frost 0 :opacity 1
    :children
    (lui.retained:nodes
     (lui.retained:make-label :text "Retained data playground"
                        :font-weight :bold)
     (lui.retained:make-row :gap '(:units 1) :cross-align :center
                        :children
                        (lui.retained:nodes *toolkit-button* *palette-button*))
     *metrics*
     (lui.retained:make-label
                        :text "Edit a stored tree and watch LUI redraw it.")
     (lui.retained:make-row :gap '(:units 2) :width (lui:grow)
      :children
      (lui.retained:nodes
       (lui.retained:make-panel :id :editor :width (lui:grow)
        :padding '(:units 2) :gap '(:units 1)
        :children
        (lui.retained:nodes
         (lui.retained:make-label :text "Callbacks update data")
         *greeting*
         (lui.retained:make-text-field :id :name
                            :default-value "retained world"
                        :padding '(:units 0.5) :width (lui:grow)
                            :on-change 'rename-greeting)
         (lui.retained:make-row :gap '(:units 1)
          :children
          (lui.retained:nodes
           (lui.retained:make-button :text "Count" :id :count
                              :on-activate 'increment)
           *counter*))))
       (lui.retained:make-panel :id :data :width (lui:grow) :padding '(:units 2)
        :children
        (lui.retained:nodes
         (lui.retained:make-label :text "Current tree data") *preview*))))
     (lui.retained:make-panel :id :collection :width (lui:grow)
      :padding '(:units 2) :gap '(:units 1)
      :children
      (lui.retained:nodes
       (lui.retained:make-label :text "Nested rows with stable IDs")
       (lui.retained:make-label :text "Edit notes, then reverse the rows.")
       (lui.retained:make-row :gap '(:units 1)
        :children
        (lui.retained:nodes
         (lui.retained:make-button :text "Add row" :id :add
                            :on-activate 'add-item)
         (lui.retained:make-button :text "Reverse" :id :reverse
                            :on-activate 'reverse-items)
         (lui.retained:make-button :text "Remove last" :id :remove
                            :on-activate 'remove-item)))
       *cards*))
     *status*)))
  "The live UI data. Callbacks edit these nodes; DRAW reuses them each frame.")

(defun reset-demo ()
  "Reset model values and dynamic rows without rebuilding the UI tree."
  (setf *toolkit* :qt
        *palette* :default
        *clicks* 0
        *serial* 2
        (lui.retained:label-text *greeting*) "Hello, retained world!"
        (lui.retained:label-text *counter*) "Clicks: 0"
        (lui.retained:column-children *cards*)
        (lui.retained:nodes (make-card 1) (make-card 2)))
  (report-edit "Ready. Edit the name or press a button.")
  (values))

(defun draw ()
  "Render the global tree each frame; callbacks edit it after traversal."
  (setf (lui.retained:button-text *toolkit-button*)
        (format nil "Toolkit: ~A" (if (eq *toolkit* :macos) "macOS"
                                     (string-capitalize *toolkit*)))
        (lui.retained:button-text *palette-button*)
        (format nil "Palette: ~A" (string-capitalize *palette*))
        (lui.retained:label-text *metrics*) (lui:frame-rate-label))
  (lui:with-toolkit (*toolkit*)
    (lui:with-palette (*palette*)
      (let ((colors (lui.toolkit:toolkit-palette)))
        (setf (lui.retained:panel-background (aref *tree* 0))
              (getf colors :window-background
                    (getf colors :background))))
      (lui.retained:draw *tree*)))
  (values))

(defun main (&key (interactive t))
  "Open one retained demo. Initialization runs once; the lambda runs per frame."
  (reset-demo)
  (lui:run (lambda () (draw))
           :title "LUI retained data playground" :interactive interactive))
