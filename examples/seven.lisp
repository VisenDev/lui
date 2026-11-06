(defpackage #:lui.example.seven
  (:use #:cl #:lui #:lui.layout #:lui.frame #:lui.interaction
        #:lui.seven.model)
  (:shadow #:draw #:main)
  (:export #:draw #:draw-content #:main #:*state* #:make-state #:state-task
           #:with-state #:modal-p #:state-circles #:state-cells))
(in-package #:lui.example.seven)

(defun initial-records ()
  (let ((model (make-crud)))
    (crud-create model "Hans" "Emil")
    (crud-create model "Max" "Mustermann")
    (crud-create model "Roman" "Tisch")
    model))

(defstruct state
  (task :counter :type symbol) (toolkit :glass :type symbol)
  (count 0 :type integer)
  (celsius "0" :type string) (fahrenheit "32" :type string)
  (return-p nil :type boolean)
  (departure "27.03.2014" :type string) (return "27.03.2014" :type string)
  booking
  (timer (make-timer) :type timer)
  (crud (initial-records) :type crud)
  (circles (lui.example.seven.circles:make-state)
           :type lui.example.seven.circles::state)
  (cells (lui.example.seven.cells:make-state)
         :type lui.example.seven.cells::state)
  (filter "" :type string) (name "" :type string) (surname "" :type string)
  reveal)

(defvar *state* nil)
(defparameter *tasks*
  '((:counter "Counter") (:temperature "Temperature") (:flight "Flight")
    (:timer "Timer") (:crud "CRUD") (:circles "Circles") (:cells "Cells")))

(defmacro with-state ((instance) &body body)
  (let ((value (gensym "STATE")))
    `(let* ((,value ,instance)
            (*state* ,value)
            (lui.example.seven.circles:*state* (state-circles ,value))
            (lui.example.seven.cells:*state* (state-cells ,value)))
       ,@body)))

(defun modal-p (&optional (instance *state*))
  (with-state (instance) (lui.example.seven.circles:modal-p)))

(defun number-text (number)
  (string-right-trim "." (string-right-trim "0" (format nil "~,2F" number))))

(defun edit-field (id text &key invalid-p disabled-p)
  (let ((next (lui:text-field
               id text
               (if invalid-p
                   (lui:opt :width (grow) :disabled-p disabled-p
                            :background "#a83232")
                   (lui:opt :width (grow) :disabled-p disabled-p)))))
    (unless (equal text next) (request-frame))
    next))

(defun counter-page ()
  (row (:gap (units 1) :width (grow) :cross-align :center)
    (lui:label (format nil "~D" (state-count *state*))
               (lui:opt :width (grow)))
    (when (lui:button :seven-count "Count")
      (incf (state-count *state*))
      (request-frame))))

(defun temperature-page ()
  (row (:gap (units 1) :width (grow))
    (column (:width (grow) :gap (units 1))
      (lui:label "Celsius")
      (let ((text (edit-field
                   :seven-celsius (state-celsius *state*)
                   :invalid-p
                   (not (temperature (state-celsius *state*) :celsius)))))
        (unless (equal text (state-celsius *state*))
          (setf (state-celsius *state*) text)
          (let ((converted (temperature text :celsius)))
            (when converted
              (setf (state-fahrenheit *state*) (number-text converted)))))))
    (column (:width (grow) :gap (units 1))
      (lui:label "Fahrenheit")
      (let ((text (edit-field
                   :seven-fahrenheit (state-fahrenheit *state*)
                   :invalid-p
                   (not (temperature (state-fahrenheit *state*)
                                     :fahrenheit)))))
        (unless (equal text (state-fahrenheit *state*))
          (setf (state-fahrenheit *state*) text)
          (let ((converted (temperature text :fahrenheit)))
            (when converted
              (setf (state-celsius *state*) (number-text converted))))))))
  (unless (and (temperature (state-celsius *state*) :celsius)
               (temperature (state-fahrenheit *state*) :fahrenheit))
    (lui:label "Enter a valid number to convert the other field.")))

(defun flight-page ()
  (row (:gap (units 1) :width (grow))
    (when (lui:tab :seven-one-way "One-way flight"
                   (lui:opt :selected-p (not (state-return-p *state*))))
      (setf (state-return-p *state*) nil)
      (request-frame))
    (when (lui:tab :seven-return-flight "Return flight"
                   (lui:opt :selected-p (state-return-p *state*)))
      (setf (state-return-p *state*) t)
      (request-frame)))
  (lui:label "Departure (DD.MM.YYYY)")
  (setf (state-departure *state*)
        (edit-field :seven-departure (state-departure *state*)
                    :invalid-p (not (parse-date (state-departure *state*)))))
  (unless (parse-date (state-departure *state*))
    (lui:label "Enter a valid departure date."))
  (lui:label "Return (DD.MM.YYYY)")
  (setf (state-return *state*)
        (edit-field :seven-return (state-return *state*)
                    :disabled-p (not (state-return-p *state*))
                    :invalid-p (and (state-return-p *state*)
                                    (not (parse-date
                                          (state-return *state*))))))
  (when (and (state-return-p *state*)
             (not (parse-date (state-return *state*))))
    (lui:label "Enter a valid return date."))
  (when (and (state-return-p *state*)
             (parse-date (state-departure *state*))
             (parse-date (state-return *state*))
             (not (flight-valid-p (state-departure *state*)
                                  (state-return *state*) t)))
    (lui:label "The return date must be on or after departure."))
  (when (lui:button :seven-book "Book"
                    (lui:opt :disabled-p
                             (not (flight-valid-p (state-departure *state*)
                                                  (state-return *state*)
                                                  (state-return-p *state*)))))
    (setf (state-booking *state*)
          (if (state-return-p *state*)
              (format nil "Booked return flight: ~A to ~A."
                      (state-departure *state*) (state-return *state*))
              (format nil "Booked one-way flight on ~A."
                      (state-departure *state*)))))
  (when (state-booking *state*) (lui:label (state-booking *state*))))

(defun timer-page ()
  (let* ((timer (state-timer *state*))
         (duration
          (progn
            (lui:label "Duration (seconds)")
            (lui:slider :seven-duration (timer-duration timer)
                        (lui:opt :minimum 0 :maximum 30
                                 :step 0.1 :width (grow))))))
    (advance-timer timer (frame-time) :duration duration
                   :reset (activated-p :seven-reset))
    (row (:gap (units 1) :width (grow) :cross-align :center)
      (lui:label "Elapsed time:")
      (lui:gauge :seven-elapsed (timer-fraction timer)
                 (lui:opt :width (grow))))
    (lui:label (format nil "~,1F s / ~,1F s"
                       (timer-elapsed timer) (timer-duration timer)))
    (lui:button :seven-reset "Reset")
    (when (< (timer-elapsed timer) (timer-duration timer))
      (request-frame (/ 1 60)))))

(defun person-id-p (id)
  (and (consp id) (eq (first id) :seven-person)))

(defun select-person (id &optional focus)
  (let ((model (state-crud *state*)))
    (unless (eql id (crud-selected model))
      (let ((person (crud-select model id)))
        (when person
          (setf (state-name *state*) (person-name person)
                (state-surname *state*) (person-surname person)))
        (setf (state-reveal *state*) id)
        (request-frame)))
    (when focus
      (setf (context-focus *context*) (list :seven-person id)))))

(defun select-record (people)
  (let* ((model (state-crud *state*))
         (focus (context-focus *context*)))
    (dolist (person people)
      (let ((id (list :seven-person (person-id person))))
        (when (or (activated-p id)
                  (some (lambda (event)
                          (and (eq (event-kind event) :press)
                               (eq (event-button event) :primary)))
                        (events-for id)))
          (select-person (person-id person) t))))
    (when (and people (person-id-p focus))
      (dolist (event (events-for focus))
        (when (eq (event-kind event) :key)
          (let* ((index (or (position (crud-selected model) people
                                      :key #'person-id) 0))
                 (next (list-index (event-key event) index (length people))))
            (when next
              (select-person (person-id (nth next people)) t)
              (setf (context-focus-visible-p *context*) t))))))))

(defun visible-people ()
  (let* ((model (state-crud *state*))
         (people (crud-filter model (state-filter *state*))))
    (unless (find (crud-selected model) people :key #'person-id)
      (crud-select model nil)
      (setf (state-reveal *state*) nil))
    people))

(defun reveal-person ()
  (when (state-reveal *state*)
    (let ((row (previous-box (list :seven-person (state-reveal *state*))))
          (view (previous-box :seven-people)))
      (if (and row view)
          (multiple-value-bind (x y) (scroll-position :seven-people)
            (reveal-rect :seven-people x
                         (+ y (- (box-y row) (box-y view)))
                         0 (box-height row))
            (setf (state-reveal *state*) nil))
          (request-frame)))))

(defun crud-actions ()
  (let ((model (state-crud *state*)))
    (when (activated-p :seven-create)
      (let ((person (crud-create model (state-name *state*)
                                 (state-surname *state*))))
        (when (member person (crud-filter model (state-filter *state*)))
          (select-person (person-id person))))
      (request-frame))
    (when (and (crud-selected model) (activated-p :seven-update))
      (crud-update model (crud-selected model)
                   (state-name *state*) (state-surname *state*))
      (request-frame))
    (when (and (crud-selected model) (activated-p :seven-delete))
      (let* ((people (visible-people))
             (index (position (crud-selected model) people :key #'person-id))
             (focused (person-id-p (context-focus *context*))))
        (crud-delete model (crud-selected model))
        (setf people (visible-people))
        (if people
            (select-person (person-id
                            (nth (min index (1- (length people))) people))
                           focused)
            (setf (state-name *state*) "" (state-surname *state*) "")))
      (request-frame))))

(defun crud-page ()
  (let ((model (state-crud *state*)))
    (lui:label "Filter prefix:")
    (setf (state-filter *state*)
          (edit-field :seven-filter (state-filter *state*)))
    (select-record (visible-people))
    ;; Apply field input and actions before declaring the resulting list.
    (setf (state-name *state*) (edit-value :seven-name (state-name *state*))
          (state-surname *state*)
          (edit-value :seven-surname (state-surname *state*)))
    (crud-actions)
    (lui:panel (lui:opt :id :seven-people :width (grow)
                        :height (fixed (units 8)) :scroll-p t :gap 0
                        :radius 0 :frost 0 :opacity 1)
      (dolist (person (visible-people))
        (lui:list-item
         (list :seven-person (person-id person))
         (format nil "~A, ~A" (person-surname person) (person-name person))
         (lui:opt :selected-p (eql (person-id person) (crud-selected model))
                  :width (grow) :radius 0 :frost 0 :opacity 1))))
    (lui:label "Name:")
    (setf (state-name *state*) (edit-field :seven-name (state-name *state*)))
    (lui:label "Surname:")
    (setf (state-surname *state*)
          (edit-field :seven-surname (state-surname *state*)))
    (row (:gap (units 1) :width (grow))
      (lui:button :seven-create "Create")
      (lui:button :seven-update "Update"
                  (lui:opt :disabled-p (null (crud-selected model))))
      (lui:button :seven-delete "Delete"
                  (lui:opt :disabled-p (null (crud-selected model)))))
    (reveal-person)))

(defun circles-page ()
  (lui.example.seven.circles:draw))

(defun cells-page ()
  (lui.example.seven.cells:draw-content))

(defun draw-content (&optional (instance *state*))
  (with-state (instance)
    (dolist (tasks (list (subseq *tasks* 0 4) (subseq *tasks* 4)))
      (row (:width (grow) :gap (units 0.5))
        (dolist (task tasks)
          (when (lui:tab (list :seven-task (first task)) (second task)
                         (lui:opt :selected-p
                                  (eq (state-task *state*) (first task))
                                  :disabled-p (modal-p)))
            (setf (state-task *state*) (first task))
            (request-frame)))))
    (lui:panel (lui:opt :id (list :seven-body (state-task *state*))
                        :width (grow) :height (grow)
                        :scroll-p
                        (not (member (state-task *state*) '(:cells :circles)))
                        :gap (units 1) :padding (units 1))
      (ecase (state-task *state*)
        (:counter (counter-page)) (:temperature (temperature-page))
        (:flight (flight-page)) (:timer (timer-page)) (:crud (crud-page))
        (:circles (circles-page)) (:cells (cells-page))))))

(defun draw (&optional (instance *state*))
  (with-state (instance)
    (lui:with-toolkit ((state-toolkit *state*))
      (lui:panel (lui:opt :id :seven-window :width (grow) :height (grow)
                          :background (ecase (state-toolkit *state*)
                                        (:glass "#202430") (:motif "#b8b8b8")
                                        (:garnet "#ffffff"))
                          :opacity 1 :radius 0 :frost 0
                          :padding (units 1) :gap (units 1))
        (row (:width (grow) :gap (units 1) :cross-align :center)
          (lui:label "7GUIs" (lui:opt :width (grow)))
          (when (lui:button :seven-toolkit
                            (ecase (state-toolkit *state*)
                              (:glass "Glass") (:motif "Motif")
                              (:garnet "Garnet"))
                            (lui:opt :disabled-p (modal-p)))
            (setf (state-toolkit *state*)
                  (case (state-toolkit *state*)
                    (:glass :motif) (:motif :garnet) (otherwise :glass)))
            (request-frame)))
        (draw-content)))))

(defun main ()
  (let ((instance (make-state)))
    (run (lambda () (draw instance)) :title "7GUIs")))
