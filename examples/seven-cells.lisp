(defpackage #:lui.example.seven.cells
  (:use #:cl)
  (:export #:draw-content #:make-state #:state-sheet
           #:state-selected #:state-editing))
(in-package #:lui.example.seven.cells)

(defstruct state
  (sheet (lui.seven.model:make-sheet) :type lui.seven.model:sheet)
  (selected 0 :type integer) editing (draft "" :type string)
  (frame-width 0 :type real) (frame-height 0 :type real)
  (view-width nil :type (or null real))
  (view-height nil :type (or null real)) view-toolkit)

(defun cell-id (index)
  (list :seven-cell index))

(defun id-index (id)
  (when (and (consp id) (eq (first id) :seven-cell))
    (lui.seven.model:cell-index (second id))))

(defun finish-edit (state &optional cancel)
  (when (state-editing state)
    (unless cancel
      (lui.seven.model:sheet-set (state-sheet state) (state-editing state)
                 (state-draft state)))
    (setf (lui.frame:context-focus lui.frame:*context*)
      (cell-id (state-editing state))
      (state-editing state) nil)
    (lui:request-frame)))

(defun start-edit (state index &optional text)
  (setf (state-selected state) index
        (state-editing state) index
        (state-draft state)
        (or text (lui.seven.model:cell-text (lui.seven.model:sheet-cell
            (state-sheet state) index)))
        (lui.frame:context-focus lui.frame:*context*) (cell-id index))
  (lui:reset-editor (cell-id index) (state-draft state))
  (lui:request-frame))

(defun ensure-visible (index)
  (lui:reveal-rect :seven-grid
               (+ (lui:units 4) (* (mod index 26) (lui:units 10)))
               (* (1+ (floor index 26)) (lui:units 3))
               (lui:units 10) (lui:units 3)
               :leading-x (lui:units 4) :leading-y (lui:units 3)))

(defun move-selection (state key)
  (let* ((index (state-selected state))
         (column (mod index 26)) (row (floor index 26))
         (next (case key
                 (:left (+ (* row 26) (max 0 (1- column))))
                 (:right (+ (* row 26) (min 25 (1+ column))))
                 (:up (+ (* (max 0 (1- row)) 26) column))
                 (:down (+ (* (min 99 (1+ row)) 26) column))
                 (:home 0) (:end 2599))))
    (when next
      (setf (state-selected state) next
            (lui.frame:context-focus lui.frame:*context*) (cell-id next))
      (ensure-visible next)
      (lui:request-frame))))

(defun edit-event (state id event)
  (setf (state-draft state)
        (lui:edit-value id (state-draft state) (list event))))

(defun handle-cell-events (state index)
  (let* ((id (cell-id index)) (events (lui:take-events id)))
    (when (and (plusp (length events)) (state-editing state)
               (not (eql index (state-editing state))))
      (finish-edit state))
    (loop for raw across events do
      (let ((event (lui:text-input-event
                    raw (eql index (state-editing state)))))
        (when event
          (cond
            ((and (eq (lui:event-kind event) :press)
                  (eq (lui:event-button event) :primary))
             (unless (eql index (state-editing state)) (finish-edit state))
             (setf (state-selected state) index
                   (lui.frame:context-focus lui.frame:*context*) id)
             (when (and (>= (lui:event-clicks event) 2)
                        (not (state-editing state)))
               (start-edit state index)))
            ((state-editing state)
             (cond ((and (eq (lui:event-kind event) :key)
                         (eq (lui:event-key event) :escape))
                    (finish-edit state t))
                   ((or (eq (lui:event-kind event) :activate)
                        (and (eq (lui:event-kind event) :key)
                             (eq (lui:event-key event) :enter)))
                    (finish-edit state))
                   (t (edit-event state id event))))
            ((or (eq (lui:event-kind event) :activate)
                 (and (eq (lui:event-kind event) :key)
                      (eq (lui:event-key event) :enter)))
             (start-edit state index))
            ((eq (lui:event-kind event) :key)
             (setf (state-selected state) index)
             (move-selection state (lui:event-key event)))
            ((and (eq (lui:event-kind event) :text)
                  (stringp (lui:event-value event)))
             (start-edit state index "")
             (edit-event state id event))))))
    ;; Shared text-field declaration receives the already edited draft.
    nil))

(defun handle-input (state)
  (let ((editing (state-editing state)))
    ;; Apply pending text before a blur or Enter commits in the same frame.
    (when editing (handle-cell-events state editing))
    (when (and (state-editing state)
            (not (equal (lui:widget-key (lui.frame:context-focus
                  lui.frame:*context*))
                           (cell-id (state-editing state)))))
      (finish-edit state))
    (let ((focused (id-index (lui:widget-key (lui.frame:context-focus
                  lui.frame:*context*)))))
      (when (and focused (not (state-editing state)))
        (setf (state-selected state) focused)))
    (loop for id across (lui:event-targets) do
          (let ((index (id-index (lui:widget-key id))))
        (when (and index (not (eql index editing)))
          (handle-cell-events state index))))))


(defun header (text x y width height)
  (lui:cell
    text
    (lui:opt
      :id text
      :width (lui:fixed width)
      :height (lui:fixed height)
      :position :absolute
      :offset-x x
      :offset-y y
      :disabled-p t
      :padding (lui:units 0.5)
      :background "#e5e9ee"
      :foreground "#202430")))

(defun draw-cell (state index x y width height)
  (if (eql index (state-editing state))
      (setf (state-draft state)
      (lui:text-field
        (lui:opt
          :id (cell-id index)
          :value (state-draft state)
          :width (lui:fixed width)
                                     :height (lui:fixed height)
          :position :absolute
          :offset-x x
          :offset-y y
          :radius 0
          :frost 0
          :opacity 1
                                     :background "#ffffff"
                                     :foreground "#000000")))
    (lui:cell
      (lui.seven.model:cell-display (lui.seven.model:sheet-cell (state-sheet
              state) index))
      (lui:opt
        :id (cell-id index)
        :width (lui:fixed width)
        :height (lui:fixed height)
        :position :absolute
        :offset-x x
        :offset-y y
                         :selected-p (= index (state-selected state))))))

(defun draw-content (state)
  (when (or (/= (state-frame-width state) (lui.frame:context-width
            lui.frame:*context*))
            (/= (state-frame-height state) (lui.frame:context-height
            lui.frame:*context*)))
    (setf (state-frame-width state) (lui.frame:context-width
          lui.frame:*context*)
          (state-frame-height state) (lui.frame:context-height
          lui.frame:*context*)
          (state-view-width state) nil
          (state-view-height state) nil)
    (lui:request-frame))
  (handle-input state)
  (lui:label "Double-click or Enter to edit; Enter commits, Esc cancels. Arrows move; Home/End reach A0/Z99.")
  (lui:label (format nil "Selected: ~A"
                     (lui.seven.model:cell-address (state-selected state))))
  (let* ((page-p (lui.frame::context-page-height-p lui.frame:*context*))
         (previous (lui.frame:context-previous-root lui.frame:*context*))
         (viewport (when (and previous
                              (= (lui:box-width (lui:element-box previous))
                                 (lui.frame:context-width
                  lui.frame:*context*))
                              (or page-p
                                  (= (lui:box-height (lui:element-box
                      previous))
                                     (lui.frame:context-height
                    lui.frame:*context*))))
                     (lui:previous-box :seven-grid)))
         (width (lui:units 10)) (height (lui:units 3)) (header (lui:units 4))
         (cached (eq (state-view-toolkit state) (lui:current-toolkit)))
         (view-width (if viewport (lui:box-width viewport)
                         (or (and cached (state-view-width state)) 0)))
         (view-height (if (and page-p viewport)
                          (lui.frame::context-viewport-height
              lui.frame:*context*)
                          (if viewport (lui:box-height viewport)
                              (or (and cached (state-view-height state)) 0))))
         (full-width (+ header (* 26 width)))
         (full-height (* 101 height)))
    (when viewport
      (setf (state-view-width state) view-width
            (state-view-height state) view-height
            (state-view-toolkit state) (lui:current-toolkit)))
    ;; The cold geometry pass avoids constructing rows for a whole-window guess.
    (unless viewport (lui:request-frame))
    (multiple-value-bind (x y) (lui:scroll-position :seven-grid)
      ;; The page owns vertical scrolling; retain the grid's horizontal
      ;; viewport and paint only rows near the visible part of its full extent.
      (when page-p
        (setf y (if viewport
                    (max 0 (min (- full-height view-height)
                                (- (lui.frame::context-page-top
                      lui.frame:*context*)
                                   (lui:box-y viewport))))
                    0)))
      (let* ((maximum (max 0 (- full-width view-width)))
             (next
            (lui:slider
              (lui:opt
                :id :seven-grid-horizontal
                :value x
                :minimum 0
                :maximum (max 1 maximum)
                :step 1
                :width (lui:grow)
                                        :disabled-p (zerop maximum)))))
        (unless (= x next)
          (setf x next)
          (lui:scroll-to :seven-grid x (if page-p 0 y))
          (lui:request-frame)))
      (multiple-value-bind (first-column last-column)
          (lui:visible-span x view-width width header 26)
        (multiple-value-bind (first-row last-row)
            (lui:visible-span y view-height height height 100)
          (lui:panel (lui:opt :id :seven-grid :width (lui:grow)
                              :height (if page-p (lui:fixed full-height)
                  (lui:grow))
                              :scroll-p t :radius 0 :frost 0 :opacity 1)
            (lui:column (lui:opt :width (lui:fixed full-width) :height
              (lui:fixed
                    full-height))
              ;; This clip also prevents clicks passing through headers.
              (lui:column (lui:opt :width (lui:fixed (max 0 (- view-width
                header)))
                              :height (lui:fixed (max 0 (- view-height
                          height)))
                              :position :absolute :offset-x (+ x header)
                              :offset-y (+ y height) :clip-p t)
                (do ((row first-row (1+ row))) ((>= row last-row))
                  (do ((column first-column (1+ column)))
                      ((>= column last-column))
                    (draw-cell state (+ (* row 26) column)
                               (- (* column width) x)
                               (- (* row height) y) width height))))
              ;; Sticky headers are painted last over the scrolled cells.
              (do ((row first-row (1+ row))) ((>= row last-row))
                (header (format nil "~D" row) x
                        (* (1+ row) height) header height))
              (do ((column first-column (1+ column)))
                  ((>= column last-column))
                (header (string (code-char (+ 65 column)))
                        (+ header (* column width)) y width height))
              (header "" x y header height))))))))
