(defpackage #:lui.example.seven.cells
  (:use #:cl #:lui #:lui.layout #:lui.frame #:lui.interaction
        #:lui.seven.model)
  (:export #:draw-content #:*state* #:make-state #:state-sheet
           #:state-selected #:state-editing))
(in-package #:lui.example.seven.cells)

(defstruct state
  (sheet (make-sheet) :type sheet)
  (selected 0 :type integer) editing (draft "" :type string)
  (frame-width 0 :type real) (frame-height 0 :type real)
  (view-width nil :type (or null real))
  (view-height nil :type (or null real)) view-toolkit)
(defvar *state* nil)

(defun cell-id (index)
  (list :seven-cell index))

(defun id-index (id)
  (when (and (consp id) (eq (first id) :seven-cell))
    (cell-index (second id))))

(defun finish-edit (&optional cancel)
  (when (state-editing *state*)
    (unless cancel
      (sheet-set (state-sheet *state*) (state-editing *state*)
                 (state-draft *state*)))
    (setf (state-editing *state*) nil)
    (request-frame)))

(defun start-edit (index &optional text)
  (setf (state-selected *state*) index
        (state-editing *state*) index
        (state-draft *state*)
        (or text (cell-text (sheet-cell (state-sheet *state*) index)))
        (context-focus *context*) (cell-id index))
  (reset-editor (cell-id index) (state-draft *state*))
  (request-frame))

(defun ensure-visible (index)
  (reveal-rect :seven-grid
               (+ (units 4) (* (mod index 26) (units 10)))
               (* (1+ (floor index 26)) (units 3))
               (units 10) (units 3)
               :leading-x (units 4) :leading-y (units 3)))

(defun move-selection (key)
  (let* ((index (state-selected *state*))
         (column (mod index 26)) (row (floor index 26))
         (next (case key
                 (:left (+ (* row 26) (max 0 (1- column))))
                 (:right (+ (* row 26) (min 25 (1+ column))))
                 (:up (+ (* (max 0 (1- row)) 26) column))
                 (:down (+ (* (min 99 (1+ row)) 26) column))
                 (:home 0) (:end 2599))))
    (when next
      (setf (state-selected *state*) next
            (context-focus *context*) (cell-id next))
      (ensure-visible next)
      (request-frame))))

(defun edit-event (id event)
  (setf (state-draft *state*)
        (edit-value id (state-draft *state*) (list event))))

(defun handle-cell-events (index)
  (let* ((id (cell-id index)) (events (take-events id)))
    (when (and events (state-editing *state*)
               (not (eql index (state-editing *state*))))
      (finish-edit))
    (dolist (raw events)
      (let ((event (text-input-event
                    raw (eql index (state-editing *state*)))))
        (when event
          (cond
            ((and (eq (event-kind event) :press)
                  (eq (event-button event) :primary))
             (unless (eql index (state-editing *state*)) (finish-edit))
             (setf (state-selected *state*) index
                   (context-focus *context*) id)
             (when (and (>= (event-clicks event) 2)
                        (not (state-editing *state*)))
               (start-edit index)))
            ((state-editing *state*)
             (cond ((and (eq (event-kind event) :key)
                         (eq (event-key event) :escape))
                    (finish-edit t))
                   ((or (eq (event-kind event) :activate)
                        (and (eq (event-kind event) :key)
                             (eq (event-key event) :enter)))
                    (finish-edit))
                   (t (edit-event id event))))
            ((or (eq (event-kind event) :activate)
                 (and (eq (event-kind event) :key)
                      (eq (event-key event) :enter)))
             (start-edit index))
            ((eq (event-kind event) :key)
             (setf (state-selected *state*) index)
             (move-selection (event-key event)))
            ((and (eq (event-kind event) :text)
                  (stringp (event-value event)))
             (start-edit index "")
             (edit-event id event))))))
    ;; Shared text-field declaration receives the already edited draft.
    nil))

(defun handle-input ()
  (let ((editing (state-editing *state*)))
    ;; Apply pending text before a blur or Enter commits in the same frame.
    (when editing (handle-cell-events editing))
    (when (and (state-editing *state*)
               (not (equal (context-focus *context*)
                           (cell-id (state-editing *state*)))))
      (finish-edit))
    (let ((focused (id-index (context-focus *context*))))
      (when (and focused (not (state-editing *state*)))
        (setf (state-selected *state*) focused)))
    (dolist (id (event-targets))
      (let ((index (id-index id)))
        (when (and index (not (eql index editing)))
          (handle-cell-events index))))))


(defun header (text x y width height)
  (lui:cell nil text
            (lui:opt :width (fixed width) :height (fixed height)
                     :floating-p t :offset-x x :offset-y y
                     :disabled-p t :padding (units 0.5)
                     :background "#e5e9ee" :foreground "#202430")))

(defun draw-cell (index x y width height)
  (if (eql index (state-editing *state*))
      (setf (state-draft *state*)
            (lui:text-field (cell-id index) (state-draft *state*)
                            (lui:opt :width (fixed width)
                                     :height (fixed height)
                                     :floating-p t :offset-x x :offset-y y
                                     :radius 0 :frost 0 :opacity 1
                                     :background "#ffffff"
                                     :foreground "#000000")))
      (lui:cell (cell-id index)
                (cell-display (sheet-cell (state-sheet *state*) index))
                (lui:opt :width (fixed width) :height (fixed height)
                         :floating-p t :offset-x x :offset-y y
                         :selected-p (= index (state-selected *state*))))))

(defun draw-content ()
  (when (or (/= (state-frame-width *state*) (context-width *context*))
            (/= (state-frame-height *state*) (context-height *context*)))
    (setf (state-frame-width *state*) (context-width *context*)
          (state-frame-height *state*) (context-height *context*)
          (state-view-width *state*) nil
          (state-view-height *state*) nil)
    (request-frame))
  (handle-input)
  (lui:label "Double-click or Enter to edit; Enter commits, Esc cancels. Arrows move; Home/End reach A0/Z99.")
  (lui:label (format nil "Selected: ~A"
                     (cell-address (state-selected *state*))))
  (let* ((previous (context-previous-root *context*))
         (viewport (when (and previous
                              (= (box-width (element-box previous))
                                 (context-width *context*))
                              (= (box-height (element-box previous))
                                 (context-height *context*)))
                     (previous-box :seven-grid)))
         (width (units 10)) (height (units 3)) (header (units 4))
         (cached (eq (state-view-toolkit *state*) (lui:current-toolkit)))
         (view-width (if viewport (box-width viewport)
                         (or (and cached (state-view-width *state*)) 0)))
         (view-height (if viewport (box-height viewport)
                          (or (and cached (state-view-height *state*)) 0)))
         (full-width (+ header (* 26 width)))
         (full-height (* 101 height)))
    (when viewport
      (setf (state-view-width *state*) view-width
            (state-view-height *state*) view-height
            (state-view-toolkit *state*) (lui:current-toolkit)))
    ;; The cold geometry pass avoids constructing rows for a whole-window guess.
    (unless viewport (request-frame))
    (multiple-value-bind (x y) (scroll-position :seven-grid)
      (let* ((maximum (max 0 (- full-width view-width)))
             (next (lui:slider :seven-grid-horizontal x
                               (lui:opt :minimum 0 :maximum (max 1 maximum)
                                        :step 1 :width (grow)
                                        :disabled-p (zerop maximum)))))
        (unless (= x next)
          (setf x next)
          (scroll-to :seven-grid x y)
          (request-frame)))
      (multiple-value-bind (first-column last-column)
          (visible-span x view-width width header 26)
        (multiple-value-bind (first-row last-row)
            (visible-span y view-height height height 100)
          (lui:panel (lui:opt :id :seven-grid :width (grow) :height (grow)
                              :scroll-p t :radius 0 :frost 0 :opacity 1)
            (column (:width (fixed full-width) :height (fixed full-height))
              ;; This clip also prevents clicks passing through headers.
              (column (:width (fixed (max 0 (- view-width header)))
                              :height (fixed (max 0 (- view-height height)))
                              :floating-p t :offset-x (+ x header)
                              :offset-y (+ y height) :clip-p t)
                (loop :for row :from first-row :below last-row
                      :do (loop :for column :from first-column
                                :below last-column
                                :do (draw-cell
                                     (+ (* row 26) column)
                                     (- (* column width) x)
                                     (- (* row height) y) width height))))
              ;; Sticky headers are painted last over the scrolled cells.
              (loop :for row :from first-row :below last-row
                    :do (header (format nil "~D" row) x
                                (* (1+ row) height) header height))
              (loop :for column :from first-column :below last-column
                    :do (header (string (code-char (+ 65 column)))
                                (+ header (* column width)) y width height))
              (header "" x y header height))))))))
