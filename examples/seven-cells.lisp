(defpackage #:lui.example.seven.cells
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.example
        #:lui.seven.model)
  (:export #:draw-content #:*state* #:make-state #:state-sheet
           #:state-selected #:state-editing))
(in-package #:lui.example.seven.cells)

(defstruct* state
  (sheet (make-sheet) :type sheet)
  (selected 0 :type integer) editing (draft "" :type string)
  (frame-width 0 :type real) (frame-height 0 :type real))
(defvar *state* (make-state))

(fn cell-id ((index integer))
  (list :seven-cell index))

(fn id-index (id)
  (when (and (consp id) (eq (first id) :seven-cell))
    (cell-index (second id))))

(fn finish-edit (&optional cancel)
  (when (state-editing *state*)
    (unless cancel
      (sheet-set (state-sheet *state*) (state-editing *state*)
                 (state-draft *state*)))
    (setf (state-editing *state*) nil)
    (request-frame)))

(fn start-edit ((index integer) &optional text)
  (setf (state-selected *state*) index
        (state-editing *state*) index
        (state-draft *state*)
        (or text (cell-text (sheet-cell (state-sheet *state*) index)))
        (context-focus *context*) (cell-id index))
  (let ((length (length (state-draft *state*))))
    (setf (gethash (cell-id index) (context-state *context*))
          (lui.widgets:make-edit-state :cursor length :anchor length)))
  (request-frame))

(fn ensure-visible ((index integer))
  (let ((viewport (previous-box :seven-grid))
        (width (units 10)) (height (units 3)) (header (units 4)))
    (when viewport
      (multiple-value-bind (x y) (scroll-position :seven-grid)
        (let* ((left (+ header (* (mod index 26) width)))
               (top (* (1+ (floor index 26)) height))
               (next-x (max 0 (min (- left header)
                                   (max x (- (+ left width)
                                             (box-width viewport))))))
               (next-y (max 0 (min (- top height)
                                   (max y (- (+ top height)
                                             (box-height viewport)))))))
          (unless (and (= x next-x) (= y next-y))
            (scroll-to :seven-grid next-x next-y)
            (request-frame)))))))

(fn move-selection ((key symbol))
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

(fn edit-event (id (event event))
  (setf (state-draft *state*)
        (lui.widgets:edit-text
         (state-draft *state*) (gethash id (context-state *context*))
         (list event))))

(fn handle-cell-events ((index integer))
  (let ((id (cell-id index)))
    (when (and (events-for id) (state-editing *state*)
               (not (eql index (state-editing *state*))))
      (finish-edit))
    (dolist (event (events-for id))
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
         (edit-event id event))))
    ;; Shared text-field declaration receives the already edited draft.
    (setf (gethash id (context-events *context*)) nil)))

(fn handle-input ()
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
    (maphash (lambda (id events)
               (declare (ignore events))
               (let ((index (id-index id)))
                 (when (and index (not (eql index editing)))
                   (handle-cell-events index))))
             (context-events *context*))))

(fn header ((text string) (x real) (y real) (width real) (height real))
  (panel (:width (fixed width) :height (fixed height) :floating-p t
          :offset-x x :offset-y y :align :center :cross-align :center
          :background "#404550" :foreground "#ffffff"
          :radius 0 :frost 0 :opacity 1)
    (widget :label text)))

(fn draw-cell ((index integer) (x real) (y real) (width real) (height real))
  (column (:width (fixed width) :height (fixed height) :floating-p t
           :offset-x x :offset-y y :padding (units 0.1))
    (if (eql index (state-editing *state*))
        (setf (state-draft *state*)
              (widget :text-field (cell-id index) (state-draft *state*)
                      :width (grow) :height (grow) :radius 0 :frost 0
                      :opacity 1))
        (apply #'widget :button (cell-id index)
               (cell-display (sheet-cell (state-sheet *state*) index))
               :width (grow) :height (grow) :radius 0 :frost 0 :opacity 1
               (when (= index (state-selected *state*))
                 '(:background "#235b9b" :foreground "#ffffff"))))))

(fn visible-span ((offset real) (viewport real) (size real) (header real)
                  (count integer))
  (values (max 0 (min (1- count) (floor (- offset header) size)))
          (min count (1+ (ceiling (- (+ offset viewport) header) size)))))

(fn draw-content ()
  (when (or (/= (state-frame-width *state*) (context-width *context*))
            (/= (state-frame-height *state*) (context-height *context*)))
    (setf (state-frame-width *state*) (context-width *context*)
          (state-frame-height *state*) (context-height *context*))
    (request-frame))
  (handle-input)
  (widget :label "Double-click or Enter to edit; Enter commits, Esc cancels. Arrows move; Home/End reach A0/Z99.")
  (widget :label (format nil "Selected: ~A"
                        (cell-address (state-selected *state*))))
  (let* ((viewport (previous-box :seven-grid))
         (width (units 10)) (height (units 3)) (header (units 4))
         (view-width (if viewport (box-width viewport)
                         (context-width *context*)))
         (view-height (if viewport (box-height viewport)
                          (context-height *context*)))
         (full-width (+ header (* 26 width)))
         (full-height (* 101 height)))
    (unless viewport (request-frame))
    (multiple-value-bind (x y) (scroll-position :seven-grid)
      (let* ((maximum (max 0 (- full-width view-width)))
             (next (widget :slider :seven-grid-horizontal x
                           :minimum 0 :maximum (max 1 maximum)
                           :step 1 :width (grow)
                           :disabled-p (zerop maximum))))
        (unless (= x next)
          (setf x next)
          (scroll-to :seven-grid x y)
          (request-frame)))
      (multiple-value-bind (first-column last-column)
          (visible-span x view-width width header 26)
        (multiple-value-bind (first-row last-row)
            (visible-span y view-height height height 100)
          (panel (:id :seven-grid :width (grow) :height (grow)
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
