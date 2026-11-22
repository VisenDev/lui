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
  (lui.retained:node
   :row :id number :gap '(:units 1) :width (lui:grow)
   :children
   (list (lui.retained:node :checkbox :text (format nil "Item ~D" number)
                           :id :checked)
         (lui.retained:node :text-field :id :note :width (lui:grow)
                           :padding '(:units 0.5)
                           :default-value (format nil "Note for item ~D"
                                                  number)))))

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

;; UI data: allocated at load time, independently of rendering.
;; Unit descriptors are resolved by the retained layer for the active backend.
(defparameter *toolkit-button*
  (lui.retained:node :button :text "Toolkit: Qt" :id :toolkit
                     :on-activate 'cycle-toolkit))
(defparameter *palette-button*
  (lui.retained:node :button :text "Palette: Default" :id :palette
                     :on-activate 'cycle-palette))
(defparameter *metrics* (lui.retained:node :label :text "" :id :metrics))
(defparameter *greeting* (lui.retained:node :label :text "Hello, retained world!"))
(defparameter *counter* (lui.retained:node :label :text "Clicks: 0"))
(defparameter *preview* (lui.retained:node :label :text ""))
(defparameter *status* (lui.retained:node :label :text "Ready."))
(defparameter *cards*
  (lui.retained:node :column :id :items :gap '(:units 1) :width (lui:grow)
                     :children (list (make-card 1) (make-card 2))))

(defparameter *tree*
  (list
   (lui.retained:node
    :panel :id :root :width (lui:grow) :height (lui:grow)
    :scroll-p t :padding '(:units 2) :gap '(:units 1)
    :radius 0 :frost 0 :opacity 1
    :children
    (list
     (lui.retained:node :label :text "Retained data playground"
                        :font-weight :bold)
     (lui.retained:node :row :gap '(:units 1) :cross-align :center
                        :children (list *toolkit-button* *palette-button*))
     *metrics*
     (lui.retained:node :label
                        :text "Edit a stored tree and watch LUI redraw it.")
     (lui.retained:node
      :row :gap '(:units 2) :width (lui:grow)
      :children
      (list
       (lui.retained:node
        :panel :id :editor :width (lui:grow)
        :padding '(:units 2) :gap '(:units 1)
        :children
        (list
         (lui.retained:node :label :text "Callbacks update data")
         *greeting*
         (lui.retained:node :text-field :id :name
                            :default-value "retained world"
                            :padding '(:units 0.5) :width (lui:grow)
                            :on-change 'rename-greeting)
         (lui.retained:node
          :row :gap '(:units 1)
          :children
          (list (lui.retained:node :button :text "Count" :id :count
                                  :on-activate 'increment)
                *counter*))))
       (lui.retained:node
        :panel :id :data :width (lui:grow) :padding '(:units 2)
        :children (list (lui.retained:node :label :text "Current tree data")
                        *preview*))))
     (lui.retained:node
      :panel :id :collection :width (lui:grow)
      :padding '(:units 2) :gap '(:units 1)
      :children
      (list
       (lui.retained:node :label :text "Nested rows with stable IDs")
       (lui.retained:node :label :text "Edit notes, then reverse the rows.")
       (lui.retained:node
        :row :gap '(:units 1)
        :children
        (list (lui.retained:node :button :text "Add row" :id :add
                                :on-activate 'add-item)
              (lui.retained:node :button :text "Reverse" :id :reverse
                                :on-activate 'reverse-items)
              (lui.retained:node :button :text "Remove last" :id :remove
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
        (second *greeting*) "Hello, retained world!"
        (second *counter*) "Clicks: 0"
        (cddr *cards*) (list (make-card 1) (make-card 2)))
  (report-edit "Ready. Edit the name or press a button.")
  (values))

(defun draw ()
  "Render the global tree each frame; callbacks edit it after traversal."
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
