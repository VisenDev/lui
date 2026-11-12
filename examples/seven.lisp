(defpackage #:lui.example.seven
  (:use #:cl)
  (:export #:draw #:draw-content #:main #:make-state #:state-task
           #:modal-p #:state-circles #:state-cells))
(in-package #:lui.example.seven)

(defun initial-records ()
  (let ((model (lui.seven.model:make-crud)))
    (lui.seven.model:crud-create model "Hans" "Emil")
    (lui.seven.model:crud-create model "Max" "Mustermann")
    (lui.seven.model:crud-create model "Roman" "Tisch")
    model))

(defstruct state
  (task :counter :type symbol) (toolkit :qt :type symbol)
  (count 0 :type integer)
  (celsius "0" :type string) (fahrenheit "32" :type string)
  (return-p nil :type boolean)
  (departure "27.03.2014" :type string) (return "27.03.2014" :type string)
  booking
  (timer (lui.seven.model:make-timer) :type lui.seven.model:timer)
  (crud (initial-records) :type lui.seven.model:crud)
  (circles (lui.example.seven.circles:make-state)
           :type lui.example.seven.circles::state)
  (cells (lui.example.seven.cells:make-state)
         :type lui.example.seven.cells::state)
  (filter "" :type string) (name "" :type string) (surname "" :type string)
  reveal)

(defparameter *tasks*
  '((:counter "Counter") (:temperature "Temperature") (:flight "Flight")
    (:timer "Timer") (:crud "CRUD") (:circles "Circles") (:cells "Cells")))

(defun modal-p (state)
  (lui.example.seven.circles:modal-p (state-circles state)))

(defun number-text (number)
  (string-right-trim "." (string-right-trim "0" (format nil "~,2F" number))))

(defun edit-field (id text &key invalid-p disabled-p)
  (let ((next
        (lui:text-field
          (list*
            :id
            id
            :value
            text
               (if invalid-p
                   (lui:opt :width (lui:grow) :disabled-p disabled-p
                            :background "#a83232")
                (lui:opt :width (lui:grow) :disabled-p disabled-p))))))
    (unless (equal text next) (lui:request-frame))
    next))

(defun counter-page (state)
  (lui:row (lui:opt :gap (lui:units 1) :width (lui:grow) :cross-align :center)
    (lui:label (format nil "~D" (state-count state))
               (lui:opt :width (lui:grow)))
    (when (lui:button "Count" (lui:opt :id :seven-count))
      (incf (state-count state))
      (lui:request-frame))))

(defun temperature-page (state)
  (lui:row (lui:opt :gap (lui:units 1) :width (lui:grow))
    (lui:column (lui:opt :width (lui:grow) :gap (lui:units 1))
      (lui:label "Celsius")
      (let ((text (edit-field
                   :seven-celsius (state-celsius state)
                   :invalid-p
                   (not (lui.seven.model:temperature (state-celsius state)
                    :celsius)))))
        (unless (equal text (state-celsius state))
          (setf (state-celsius state) text)
          (let ((converted (lui.seven.model:temperature text :celsius)))
            (when converted
              (setf (state-fahrenheit state) (number-text converted)))))))
    (lui:column (lui:opt :width (lui:grow) :gap (lui:units 1))
      (lui:label "Fahrenheit")
      (let ((text (edit-field
                   :seven-fahrenheit (state-fahrenheit state)
                   :invalid-p
                   (not (lui.seven.model:temperature (state-fahrenheit state)
                                     :fahrenheit)))))
        (unless (equal text (state-fahrenheit state))
          (setf (state-fahrenheit state) text)
          (let ((converted (lui.seven.model:temperature text :fahrenheit)))
            (when converted
              (setf (state-celsius state) (number-text converted))))))))
  (unless (and (lui.seven.model:temperature (state-celsius state) :celsius)
               (lui.seven.model:temperature (state-fahrenheit state)
          :fahrenheit))
    (lui:label "Enter a valid number to convert the other field.")))

(defun flight-page (state)
  (lui:row (lui:opt :gap (lui:units 1) :width (lui:grow))
    (when
      (lui:tab
        "One-way flight"
        (lui:opt :id :seven-one-way :selected-p (not (state-return-p state))))
      (setf (state-return-p state) nil)
      (lui:request-frame))
    (when
      (lui:tab
        "Return flight"
        (lui:opt :id :seven-return-flight :selected-p (state-return-p state)))
      (setf (state-return-p state) t)
      (lui:request-frame)))
  (lui:label "Departure (DD.MM.YYYY)")
  (setf (state-departure state)
        (edit-field :seven-departure (state-departure state)
                    :invalid-p (not (lui.seven.model:parse-date
            (state-departure state)))))
  (unless (lui.seven.model:parse-date (state-departure state))
    (lui:label "Enter a valid departure date."))
  (lui:label "Return (DD.MM.YYYY)")
  (setf (state-return state)
        (edit-field :seven-return (state-return state)
                    :disabled-p (not (state-return-p state))
                    :invalid-p (and (state-return-p state)
                                    (not (lui.seven.model:parse-date
                                          (state-return state))))))
  (when (and (state-return-p state)
             (not (lui.seven.model:parse-date (state-return state))))
    (lui:label "Enter a valid return date."))
  (when (and (state-return-p state)
             (lui.seven.model:parse-date (state-departure state))
             (lui.seven.model:parse-date (state-return state))
             (not (lui.seven.model:flight-valid-p (state-departure state)
                                  (state-return state) t)))
    (lui:label "The return date must be on or after departure."))
  (when
    (lui:button
      "Book"
      (lui:opt
        :id :seven-book
        :disabled-p
          (not (lui.seven.model:flight-valid-p (state-departure state)
                                                  (state-return state)
                                                  (state-return-p state)))))
    (setf (state-booking state)
          (if (state-return-p state)
              (format nil "Booked return flight: ~A to ~A."
                      (state-departure state) (state-return state))
              (format nil "Booked one-way flight on ~A."
                      (state-departure state)))))
  (when (state-booking state) (lui:label (state-booking state))))

(defun timer-page (state)
  (let* ((timer (state-timer state))
         (duration
          (progn
            (lui:label "Duration (seconds)")
          (lui:slider
            (lui:opt
              :id :seven-duration
              :value (lui.seven.model:timer-duration timer)
              :minimum 0
              :maximum 30
              :step 0.1
              :width (lui:grow))))))
    (lui.seven.model:advance-timer timer (lui:frame-time) :duration duration
                   :reset (lui:activated-p :seven-reset))
    (lui:row (lui:opt :gap (lui:units 1) :width (lui:grow) :cross-align
      :center)
      (lui:label "Elapsed time:")
      (lui:gauge
        (lui.seven.model:timer-fraction timer)
        (lui:opt :id :seven-elapsed :width (lui:grow))))
    (lui:label (format nil "~,1F s / ~,1F s"
                       (lui.seven.model:timer-elapsed timer)
          (lui.seven.model:timer-duration timer)))
    (lui:button "Reset" (lui:opt :id :seven-reset))
    (when (< (lui.seven.model:timer-elapsed timer)
          (lui.seven.model:timer-duration timer))
      (lui:request-frame (/ 1 60)))))

(defun person-id-p (id)
  (and (consp id) (eq (first id) :seven-person)))

(defun select-person (state id &optional focus)
  (let ((model (state-crud state)))
    (unless (eql id (lui.seven.model:crud-selected model))
      (let ((person (lui.seven.model:crud-select model id)))
        (when person
          (setf (state-name state) (lui.seven.model:person-name person)
                (state-surname state) (lui.seven.model:person-surname
                person)))
        (setf (state-reveal state) id)
        (lui:request-frame)))
    (when focus
      (setf (lui.frame:context-focus lui.frame:*context*) (list :seven-person
            id)))))

(defun select-record (state people)
  (let* ((model (state-crud state))
         (focus (lui:widget-key (lui.frame:context-focus
              lui.frame:*context*))))
    (dolist (person people)
      (let ((id (list :seven-person (lui.seven.model:person-id person))))
        (when (or (lui:activated-p id)
                  (some (lambda (event)
                          (and (eq (lui:event-kind event) :press)
                               (eq (lui:event-button event) :primary)))
                        (lui.frame:events-for id)))
          (select-person state (lui.seven.model:person-id person) t))))
    (when (and people (person-id-p focus))
      (loop for event across (lui.frame:events-for focus) do
        (when (eq (lui:event-kind event) :key)
          (let* ((index (or (position (lui.seven.model:crud-selected model)
                      people
                                      :key #'lui.seven.model:person-id) 0))
                 (next (lui:list-index (lui:event-key event) index (length
                      people))))
            (when next
              (select-person state (lui.seven.model:person-id (nth next
                      people)) t)
              (setf (lui.frame:context-focus-visible-p lui.frame:*context*)
                t))))))))

(defun visible-people (state)
  (let* ((model (state-crud state))
         (people (lui.seven.model:crud-filter model (state-filter state))))
    (unless (find (lui.seven.model:crud-selected model) people :key
          #'lui.seven.model:person-id)
      (lui.seven.model:crud-select model nil)
      (setf (state-reveal state) nil))
    people))

(defun reveal-person (state)
  (when (state-reveal state)
    (let ((row (lui:previous-box (list :seven-person (state-reveal state))))
          (view (lui:previous-box :seven-people)))
      (if (and row view)
          (multiple-value-bind (x y) (lui:scroll-position :seven-people)
            (lui:reveal-rect :seven-people x
                         (+ y (- (lui:box-y row) (lui:box-y view)))
                         0 (lui:box-height row))
            (setf (state-reveal state) nil))
          (lui:request-frame)))))

(defun crud-actions (state)
  (let ((model (state-crud state)))
    (when (lui:activated-p :seven-create)
      (let ((person (lui.seven.model:crud-create model (state-name state)
                                 (state-surname state))))
        (when (member person (lui.seven.model:crud-filter model (state-filter
                  state)))
          (select-person state (lui.seven.model:person-id person))))
      (lui:request-frame))
    (when (and (lui.seven.model:crud-selected model) (lui:activated-p
            :seven-update))
      (lui.seven.model:crud-update model (lui.seven.model:crud-selected model)
                   (state-name state) (state-surname state))
      (lui:request-frame))
    (when (and (lui.seven.model:crud-selected model) (lui:activated-p
            :seven-delete))
      (let* ((people (visible-people state))
             (index (position (lui.seven.model:crud-selected model) people
                :key #'lui.seven.model:person-id))
             (focused (person-id-p (lui:widget-key (lui.frame:context-focus
                    lui.frame:*context*)))))
        (lui.seven.model:crud-delete model (lui.seven.model:crud-selected
              model))
        (setf people (visible-people state))
        (if people
            (select-person state (lui.seven.model:person-id
                                  (nth (min index (1- (length people)))
                                       people))
                           focused)
            (setf (state-name state) "" (state-surname state) "")))
      (lui:request-frame))))

(defun crud-page (state)
  (let ((model (state-crud state)))
    (lui:label "Filter prefix:")
    (setf (state-filter state)
          (edit-field :seven-filter (state-filter state)))
    (select-record state (visible-people state))
    ;; Apply field input and actions before declaring the resulting list.
    (setf (state-name state) (lui:edit-value :seven-name (state-name state))
          (state-surname state)
          (lui:edit-value :seven-surname (state-surname state)))
    (crud-actions state)
    (lui:panel (lui:opt :id :seven-people :width (lui:grow)
                        :height (lui:fixed (lui:units 8)) :scroll-p t :gap 0
                        :radius 0 :frost 0 :opacity 1)
      (dolist (person (visible-people state))
        (lui:list-item
          (format nil "~A, ~A" (lui.seven.model:person-surname person)
            (lui.seven.model:person-name person))
          (lui:opt
            :id (list :seven-person (lui.seven.model:person-id person))
            :selected-p
              (eql (lui.seven.model:person-id person)
                (lui.seven.model:crud-selected model))
            :width (lui:grow)
            :radius 0
            :frost 0
            :opacity 1))))
    (lui:label "Name:")
    (setf (state-name state) (edit-field :seven-name (state-name state)))
    (lui:label "Surname:")
    (setf (state-surname state)
          (edit-field :seven-surname (state-surname state)))
    (lui:row (lui:opt :gap (lui:units 1) :width (lui:grow))
      (lui:button "Create" (lui:opt :id :seven-create))
      (lui:button
        "Update"
        (lui:opt
          :id :seven-update
          :disabled-p (null (lui.seven.model:crud-selected model))))
      (lui:button
        "Delete"
        (lui:opt
          :id :seven-delete
          :disabled-p (null (lui.seven.model:crud-selected model)))))
    (reveal-person state)))

(defun circles-page (state)
  (lui.example.seven.circles:draw (state-circles state)))

(defun cells-page (state)
  (lui.example.seven.cells:draw-content (state-cells state)))

(defun draw-content (state)
  (dolist (tasks (list (subseq *tasks* 0 4) (subseq *tasks* 4)))
    (lui:row (lui:opt :width (lui:grow) :gap (lui:units 0.5))
      (dolist (task tasks)
        (when
          (lui:tab
            (second task)
            (lui:opt
              :id (list :seven-task (first task))
              :selected-p (eq (state-task state) (first task))
                                :disabled-p (modal-p state)))
          (setf (state-task state) (first task))
          (lui:request-frame)))))
  (lui:panel (lui:opt :id (list :seven-body (state-task state))
                      :width (lui:grow) :height (lui:grow)
                      :scroll-p
                      (not (member (state-task state) '(:cells :circles)))
                      :gap (lui:units 1) :padding (lui:units 1))
    (ecase (state-task state)
      (:counter (counter-page state)) (:temperature (temperature-page state))
      (:flight (flight-page state)) (:timer (timer-page state))
      (:crud (crud-page state))
      (:circles (circles-page state)) (:cells (cells-page state)))))

(defun draw (state)
  (lui:with-toolkit ((state-toolkit state))
    (lui:panel (lui:opt :id :seven-window :width (lui:grow) :height (lui:grow)
                        :background
                        (let ((colors (lui:toolkit-palette)))
                          (getf colors :window-background
                                (getf colors :background)))
                        :opacity 1 :radius 0 :frost 0
                        :padding (lui:units 1) :gap (lui:units 1))
      (lui:row (lui:opt :width (lui:grow) :gap (lui:units 1) :cross-align
        :center)
        (lui:label "7GUIs" (lui:opt :width (lui:grow)))
        (when
          (lui:button
                          (ecase (state-toolkit state)
                            (:glass "Glass") (:motif "Motif")
                            (:garnet "Garnet") (:macos "macOS") (:qt "Qt"))
            (lui:opt :id :seven-toolkit :disabled-p (modal-p state)))
          (setf (state-toolkit state)
                (case (state-toolkit state)
                  (:glass :motif) (:motif :garnet) (:garnet :macos)
                  (:macos :qt) (otherwise :glass)))
          (lui:request-frame)))
      (draw-content state))))

(defun main ()
  (let ((instance (make-state)))
    (lui:run (lambda () (draw instance)) :title "7GUIs")))
