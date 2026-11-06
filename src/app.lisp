(defpackage #:lui
  (:use #:cl #:lui.fn #:lui.widgets #:lui.frame)
  (:export #:run #:register-backend #:available-backends #:units #:*backend*
           #:*unit* #:with-toolkit #:current-toolkit #:toolkit-defaults
           #:register-toolkit #:toolkit-revision #:toolkit-surface
           #:control
           #:define-toolkit #:define-collection
           #:table #:table-row #:table-cell
           #:opt #:panel #:label
           #:button #:tab #:checkbox #:radio #:slider
           #:text-field #:cell #:list-item #:gauge #:canvas
           #:date-picker #:date-time-picker #:searchable-combobox))

(in-package #:lui)

(defvar *backends* (make-hash-table :test 'eq))

(defvar *default-backend-function* nil)

(defvar *backend* nil
  "Default backend override; NIL selects an available backend.")

(defvar *unit* 1 "Layout spacing unit supplied by the active backend.")

(fn (units real) ((count real))
  "Convert spacing units to backend coordinates: terminal cells or graphical units."
  (* count *unit*))

(fn register-backend ((name symbol) (runner function))
  "Install a RUN implementation under NAME; normally called by a backend."
  (setf (gethash name *backends*) runner))

(fn (available-backends list) ()
  "List every backend registered in this Lisp image."
  (let (results)
    (maphash (lambda (name runner)
               (declare (ignore runner))
               (push name results))
             *backends*)
    results))

(fn run
    ((draw function) &key (backend *backend*) ((title string) "LUI") width
     height (interactive t) ((min-fps real) 1) ((max-fps real) 240))
  "Run the same immediate-mode DRAW function on any registered backend.
Backend-specific window, DOM, input, frame, and lifetime management stay in LUI.
WIDTH/HEIGHT are optional backend coordinates; omit them for sensible defaults.
MIN-FPS sets idle redraws per second. MAX-FPS caps input and animation frames.
INTERACTIVE NIL renders one frame (useful for tests and terminal snapshots)."
  (assert (< 0 min-fps))
  (assert (<= min-fps max-fps))
  (let* ((lui.frame::*min-fps* min-fps) (lui.frame::*max-fps* max-fps)
         (name (or backend
                   (and *default-backend-function*
                        (funcall *default-backend-function*))
                   (first (available-backends))))
         (runner (gethash name *backends*)))
    (unless runner
      (error "Backend ~S is not loaded. Available: ~S" name
             (available-backends)))
    (funcall runner draw :title title :width width :height height
             :interactive interactive)))

(defvar *toolkit* :glass)
(defvar *toolkit-definition* nil)

(defstruct (toolkit (:conc-name %toolkit-))
  parent defaults controls)
(defvar *toolkits* (make-hash-table :test 'eq))

(defvar *toolkit-revision* 0)
(defun toolkit-revision ()
  "Return the generation used to invalidate cached toolkit styles."
  *toolkit-revision*)

(defun find-toolkit (name)
  (or (gethash name *toolkits*) (error "Unknown toolkit ~S." name)))

(defun register-toolkit (name &key parent defaults controls
                                   (surface (if parent
                                                (toolkit-surface parent)
                                                :glass)))
  "Register a toolkit. DEFAULTS is a plist or a zero-argument function.
CONTROLS maps control names to functions taking the public arguments and options."
  (loop :for ancestor := parent
          :then (%toolkit-parent (find-toolkit ancestor))
        :while ancestor :when (eq ancestor name)
          :do (error "Circular toolkit inheritance at ~S." name))
  (incf *toolkit-revision*)
  (register-surface name surface)
  (setf (gethash name *toolkits*)
        (make-toolkit :parent parent :defaults defaults
                      :controls controls))
  name)

(defun current-toolkit ()
  "Return the toolkit name active in this drawing scope."
  *toolkit*)

(defun defaults-of (entry)
  (let* ((parent (%toolkit-parent entry))
         (source (%toolkit-defaults entry))
         (defaults (if (functionp source) (funcall source) source)))
    (if parent (append defaults (defaults-of (find-toolkit parent)))
        defaults)))

(defun toolkit-defaults (&optional (name *toolkit*))
  "Return appearance defaults with child overrides before inherited values."
  (defaults-of (find-toolkit name)))

(defun override (kind entry)
  (or (cdr (assoc kind (%toolkit-controls entry)))
      (let ((parent (%toolkit-parent entry)))
        (when parent (override kind (find-toolkit parent))))))

(defun control (kind &rest arguments)
  "Invoke a user-defined control from the current toolkit or its ancestors."
  (apply (or (override kind (or *toolkit-definition*
                                (find-toolkit *toolkit*)))
             (error "No ~S control in toolkit ~S." kind *toolkit*))
         arguments))

(defmacro with-toolkit ((designator) &body body)
  "Draw BODY with the named toolkit; nested bindings restore on exit."
  `(let* ((*toolkit* ,designator)
          (*toolkit-definition* (find-toolkit *toolkit*)))
     ,@body))

(defmacro opt (&rest forms &key width height padding gap align cross-align
               id direction clip-p scroll-p scrollbar-p scrollbar-width mode
               floating-p offset-x offset-y
               interactive-p keyboard-focus-p pointer-focus-p
               foreground background radius frost minimum maximum step
               font-size font-family font-weight opacity accent disabled-p
               painter terminal-label accessible-name
               placeholder max-results selected-p text)
  "Build widget options, preserving order, explicit NIL, and omitted keys."
  (declare (ignore width height padding gap align cross-align
                   id direction mode
                   clip-p scroll-p scrollbar-p scrollbar-width
                   floating-p offset-x offset-y interactive-p
                   keyboard-focus-p pointer-focus-p foreground background
                   radius frost minimum maximum step font-size font-family
                   font-weight opacity accent disabled-p painter
                   terminal-label accessible-name
                   placeholder max-results selected-p text))
  `(list ,@forms))

(defmacro panel (options &body body)
  "Draw a styled container and attach widgets declared in BODY as children."
  `(let ((lui.frame:*parent*
           (lui.widgets:declare-panel
            *toolkit* (append ,options (toolkit-defaults)))))
     ,@body))

(defmacro define-control (name args doc &body body)
  (let ((kind (intern (symbol-name name) :keyword)))
    `(defun ,name (,@args &optional options)
       ,doc
       (let* ((entry (or *toolkit-definition* (find-toolkit *toolkit*)))
              (custom (override ,kind entry)))
         (if custom (funcall custom ,@args options)
             (let ((style *toolkit*) (defaults (defaults-of entry)))
               ,@body))))))

(define-control label (text)
  "Display selectable text. Width determines wrapping; no ID is needed."
  (apply #'declare-widget :label style nil text (append options defaults)))

(define-control button (id text)
  "Return true in the frame where the control with this ID activates."
  (apply #'declare-widget :button style id text (append options defaults)))

(defun without-option (key options)
  (let ((result nil))
    (do ((tail options (cddr tail))) ((null tail) (nreverse result))
      (unless (eq (car tail) key)
        (push (car tail) result)
        (push (cadr tail) result)))))

(defun selectable (kind style id text options defaults)
  (apply #'declare-widget kind style id text :value (getf options :selected-p)
         (append (without-option :selected-p options) defaults)))

(define-control tab (id text)
  "Declare a tab. Supply :selected-p in OPT and update the page on activation."
  (selectable :tab style id text options defaults))

(define-control list-item (id text)
  "Declare a selectable row and return activation. The caller owns selection."
  (selectable :list-item style id text options defaults))

(defmacro table ((&rest options) &body rows)
  "Lay out TABLE-ROWs with shared content-sized columns. :GAP separates rows
and :COLUMN-GAP separates columns. Other options are layout element keywords."
  `(column (:table-p t ,@options) ,@rows))

(defmacro table-row (() &body cells)
  "Declare a table row. Each direct child occupies one column by default."
  `(row () ,@cells))

(defmacro table-cell ((&rest options) &body contents)
  "Group any number of widgets in a table cell. :COLUMN-SPAN defaults to one."
  `(column (,@options :height (lui.layout:grow) :clip-p t) ,@contents))

(define-control cell (id text)
  "Display a compact grid cell. Use :selected-p to mark the active cell."
  (selectable :cell style id text options
              (list* :background "#ffffff" :foreground "#202430" defaults)))

(define-control checkbox (id value text)
  "Return the new boolean and a second value indicating a change."
  (value-widget :checkbox style id value text (append options defaults)))

(define-control radio (id value choice text)
  "Return the selected choice and a change flag; keep the returned value in your model."
  (value-widget :radio style id value text
                (list* :choice choice (append options defaults))))

(define-control slider (id value)
  "Return the new number and a change flag. OPT accepts :minimum, :maximum and :step."
  (value-widget :slider style id value (getf options :text "")
                (append (without-option :text options) defaults)))

(define-control text-field (id value)
  "Return the edited string and a change flag. Keep the returned string in your model."
  (value-widget :text-field style id value (getf options :placeholder "")
                (append (without-option :placeholder options) defaults)))

(define-control gauge (id fraction)
  "Display a read-only progress fraction, clamped to the range zero to one."
  (apply #'declare-widget :gauge style id "" :value (max 0 (min 1 fraction))
         (append options defaults)))

(define-control canvas (id commands)
  "Display circle commands (kind x y radius stroke fill) in local coordinates."
  (apply #'declare-widget :canvas style id "" :value commands
         (append options defaults)))

(defmacro define-toolkit (name defaults panel-name &rest names)
  "Define toolkit controls in the standard order; RADIO may be appended to NAMES."
  (let ((functions '(label button tab checkbox slider text-field cell
                     list-item gauge canvas radio))
        (args '((text) (id text) (id text) (id value text) (id value)
                (id value) (id text) (id text) (id fraction) (id commands)
                (id value choice text))))
    `(progn
       (register-toolkit ,name :surface ,name :defaults (lambda () ,defaults))
       ,@(loop :for local :in names :for fn :in functions :for a :in args
               :collect
               `(defun ,local (,@a &optional options &rest legacy)
                  (with-toolkit (,name)
                    (,fn ,@a (if legacy (cons options legacy) options)))))
       (defmacro ,panel-name (options &body body)
         (let ((form (if (and (consp options) (keywordp (car options)))
                         (cons 'opt options) options)))
           (list 'with-toolkit (list ,name) (list* 'panel form body)))))))

(defmacro define-collection (name defaults panel-name &rest names)
  "Compatibility alias for DEFINE-TOOLKIT with the same arguments."
  `(define-toolkit ,name ,defaults ,panel-name ,@names))

(defstruct picker-state
  (year 2000 :type integer) (month 1 :type integer)
  (open-p nil :type boolean) months-p
  (draft "" :type string) value)

(defstruct (combobox-state (:include edit-state))
  open-p focused-p filter-p highlight)

(defun combobox-matches (query choices limit)
  ;; Keep the source index for IDs so filtering never retargets a pointer event.
  (let ((index 0) (count 0) matches)
    (block collect
      (map nil (lambda (choice)
                 (when (search query choice :test #'char-equal)
                   (push (cons index choice) matches)
                   (when (= (incf count) limit) (return-from collect)))
                 (incf index))
           choices))
    (nreverse matches)))

(defun anchored-popup (id anchor options)
  (let* ((*parent* (lui.layout:make-element))
         (pane (declare-panel *toolkit*
                 (append options (opt :id id :floating-p t :opacity 1
                                      :scroll-p t :scrollbar-p nil :clip-p t
                                      :interactive-p t :keyboard-focus-p nil :padding (units 1))
                         (toolkit-defaults)))))
    (setf (lui.layout:element-popup-anchor pane) anchor)
    (push pane (lui.frame::context-popups *context*))
    pane))

(defun combobox-popup (id matches index anchor reveal)
  (let* ((pane (anchored-popup (list id :popup) anchor nil))
         (*parent* pane))
    (loop for match in matches for i from 0
          for row-id = (list id :choice (car match))
          do (list-item row-id (cdr match)
                        (opt :width (lui.layout:grow) :selected-p (eql i index)))
             (let ((row (gethash row-id (lui.frame::context-ids *context*))))
               (setf (lui.layout:element-keyboard-focus-p row) nil)
               (when (and reveal (eql index i))
                 (setf (lui.layout:element-popup-reveal pane) row))))))

(defun combobox-completion (id state text choices limit events anchor)
  (let ((navigate (find-if (lambda (event)
                             (and (eq :key (event-kind event))
                                  (member (event-key event) '(:up :down)))) events)))
    (when (or navigate (combobox-state-open-p state))
      (let* ((matches (combobox-matches (if (combobox-state-filter-p state) text "")
                                        choices limit))
             (last (1- (length matches)))
             (old (and (combobox-state-open-p state) (combobox-state-highlight state)))
             (index (and matches old (min old last))))
        (dolist (event events)
          (case (event-kind event)
            (:key (case (event-key event)
                    ((:up :down)
                     (setf (combobox-state-open-p state) t
                           index (when matches
                                   (if (eq :down (event-key event))
                                       (min last (1+ (or index -1)))
                                       (max 0 (1- (or index (1+ last))))))))
                    (:escape (setf (combobox-state-open-p state) nil))))
            (:activate
             (when (combobox-state-open-p state)
               (setf (combobox-state-open-p state) nil)
               (return-from combobox-completion (and index (cdr (nth index matches))))))))
        (setf (combobox-state-highlight state) index)
        (when (and matches (combobox-state-open-p state))
          (let ((clicked (find-if (lambda (match) (activated-p (list id :choice (car match))))
                                  matches)))
            (when clicked
              (setf (combobox-state-open-p state) nil)
              (return-from combobox-completion (cdr clicked))))
          (combobox-popup id matches index anchor navigate)))))
  nil)

(defun searchable-combobox (id value choices &optional options)
  "Edit a string, returning the text and a change flag just like TEXT-FIELD.
Suggestions open on focus or typing. Up/Down highlight a suggestion and
Enter accepts it. Escape dismisses the suggestions and keeps the typed text."
  (let* ((text (or value ""))
         (state (or (gethash id (context-state *context*))
                    (setf (gethash id (context-state *context*))
                          (make-combobox-state :cursor (length text) :anchor (length text)))))
         (limit (getf options :max-results 20))
         (focused (and (not (getf options :disabled-p)) (equal id (context-focus *context*))))
         (events (events-for id))
         (press (lui.frame::context-pointer-press *context*))
         (popup-box (previous-box (list id :popup)))
         (edited (text-field id text (without-option :max-results options)))
         (anchor (gethash id (lui.frame::context-ids *context*)))
         (result (if (string= edited text) value edited)))
    (check-type limit (integer 1 *))
    (cond ((not focused) (setf (combobox-state-open-p state) nil))
          ((or (not (combobox-state-focused-p state)) (find :press events :key #'event-kind))
           (setf (combobox-state-open-p state) t (combobox-state-filter-p state) nil
                 (combobox-state-highlight state) nil))
          ((and press (not (and popup-box (lui.frame::contains-p popup-box
                                               (event-x press) (event-y press)))))
           (setf (combobox-state-open-p state) nil)))
    (setf (combobox-state-focused-p state) focused)
    (when (and focused (not (string= edited text)))
      (setf (combobox-state-open-p state) t (combobox-state-filter-p state) t
            (combobox-state-highlight state) nil))
    (when focused
      (let ((choice (combobox-completion id state edited choices limit events anchor)))
        (when choice
          (setf result choice (edit-state-anchor state) (length choice)
                (edit-state-cursor state) (length choice))
          (let ((widget (lui.layout:element-content anchor)))
            (when (and (widget-p widget) (eq :text-field (widget-kind widget)))
              (setf (widget-value widget) choice)))
          (request-frame))))
    (values result (not (equal result value)))))

(defun month-days (year month)
  (if (= month 2)
      (if (and (zerop (mod year 4))
               (or (not (zerop (mod year 100))) (zerop (mod year 400))))
          29 28)
      (if (member month '(4 6 9 11)) 30 31)))

(defun picker-parts (text mode)
  (let ((date-p (not (eq mode :time)))
        (time-p (not (eq mode :date))))
    (when (and (stringp text)
               (= (length text) (ecase mode (:date 10) (:time 5)
                                                  (:datetime 16))))
      (labels ((number-at (start end)
                 (when (every #'digit-char-p (subseq text start end))
                   (parse-integer text :start start :end end))))
        (let* ((year (if date-p (number-at 0 4) 2000))
               (month (if date-p (number-at 5 7) 1))
               (day (if date-p (number-at 8 10) 1))
               (offset (if date-p 11 0))
               (hour (if time-p (number-at offset (+ offset 2)) 0))
               (minute (if time-p (number-at (+ offset 3) (+ offset 5)) 0)))
          (when (and year month day hour minute
                     (<= 1 year 9999) (<= 1 month 12)
                     (<= 1 day (month-days year month))
                     (<= 0 hour 23) (<= 0 minute 59)
                     (or (not date-p)
                         (and (char= (char text 4) #\-)
                              (char= (char text 7) #\-)))
                     (or (not time-p)
                         (char= (char text (+ offset 2)) #\:))
                     (or (not (eq mode :datetime))
                         (char= (char text 10) #\T)))
            (list year month day hour minute)))))))

(defun picker-string (parts mode)
  (destructuring-bind (year month day hour minute) parts
    (concatenate 'string
                 (if (eq mode :time) ""
                     (format nil "~4,'0D-~2,'0D-~2,'0D" year month day))
                 (if (eq mode :datetime) "T" "")
                 (if (eq mode :date) ""
                     (format nil "~2,'0D:~2,'0D" hour minute)))))

(defun calendar-start (year month)
  ;; Gregorian weekday, Sunday = 0, independent of time zones and OS clocks.
  (let* ((previous (1- year))
         (days (+ (* 365 previous) (floor previous 4)
                  (- (floor previous 100)) (floor previous 400))))
    (loop :for m :from 1 :below month :do (incf days (month-days year m)))
    (mod (1+ days) 7)))

(defparameter *month-names*
  #("January" "February" "March" "April" "May" "June" "July" "August"
    "September" "October" "November" "December"))

(defun local-today ()
  (multiple-value-bind (s m h day month year) (get-decoded-time)
    (declare (ignore s m h))
    (list year month day 0 0)))

(defun shift-month (year month delta)
  (multiple-value-bind (year-offset index) (floor (+ month -1 delta) 12)
    (values (+ year year-offset) (1+ index))))

(defun calendar-item (id text &rest options)
  (list-item id text (append options (opt :font-size 14))))

(defun calendar-arrow-focus (id state)
  (let ((focus (context-focus *context*)))
    (when (and (consp focus) (equal (first focus) id) (eq (second focus) :day))
      (let ((day (third focus)))
        (dolist (event (events-for focus))
          (let ((step (and (eq (event-kind event) :key)
                           (case (event-key event)
                             (:left -1) (:right 1) (:up -7) (:down 7)))))
            (when step
              (let* ((year (picker-state-year state)) (month (picker-state-month state))
                     (count (month-days year month)) (next (+ day step))
                     (offset (cond ((< next 1) -1) ((> next count) 1) (t 0))))
                (multiple-value-bind (y m) (shift-month year month offset)
                  (when (<= 1 y 9999)
                    (setf day (case offset (-1 (+ next (month-days y m))) (1 (- next count)) (t next))
                          (picker-state-year state) y (picker-state-month state) m
                          (context-focus *context*) (list id :day day))))))))))))

(defun picker-calendar (id state selected)
  "Return the selected date parts (or NIL for Clear) and an action flag."
  (calendar-arrow-focus id state)
  (let* ((year (picker-state-year state)) (month (picker-state-month state))
         (months (picker-state-months-p state))
         (width (lui.layout:percent (/ 1 7)))
         (palette (toolkit-defaults))
         (foreground (getf palette :foreground "#ffffff"))
         (muted (lui.widgets::muted-ink foreground (getf palette :background "#303040")))
         (ink (getf palette :accent foreground)))
    (row (:width (lui.layout:grow))
      (when (calendar-item (list id :month-menu)
                           (format nil "~A ~4,'0D ▼" (aref *month-names* (1- month)) year)
                           :width (lui.layout:grow) :font-weight :bold)
        (setf (picker-state-months-p state) (not months)))
      (dolist (step '(-1 1))
        (multiple-value-bind (y m) (shift-month year month (* step (if months 12 1)))
          (when (calendar-item (list id (if (minusp step) :previous-month :next-month))
                               (if (minusp step) "↑" "↓") :font-size 19 :center-text-p t
                               :width (lui.layout:fixed (if (context-text-mode-p *context*) 3 28))
                               :disabled-p (not (<= 1 y 9999))
                               :accessible-name (if months (if (minusp step) "Previous year" "Next year")
                                                    (if (minusp step) "Previous month" "Next month")))
            (setf (picker-state-year state) y (picker-state-month state) m)))))
    (setf year (picker-state-year state) month (picker-state-month state))
    (if (picker-state-months-p state)
        (dotimes (r 4)
          (row (:width (lui.layout:grow))
            (dotimes (c 3)
              (let ((m (+ 1 (* r 3) c)))
                (when (calendar-item (list id :month m) (subseq (aref *month-names* (1- m)) 0 3)
                                     :width (lui.layout:percent 1/3) :selected-p (= m month))
                  (setf (picker-state-month state) m (picker-state-months-p state) nil))))))
        (let* ((start (calendar-start year month)) (count (month-days year month)))
          (row (:width (lui.layout:grow))
            (loop for name across "SMTWTFS" do
              (row (:width width :align :center)
                (label (string name) (opt :font-size 13)))))
          (dotimes (week 6)
            (row (:width (lui.layout:grow))
              (dotimes (column 7)
                (let* ((n (- (+ 1 (* week 7) column) start))
                       (offset (cond ((< n 1) -1) ((> n count) 1) (t 0))))
                  (multiple-value-bind (y m) (shift-month year month offset)
                    (let ((day (case offset (-1 (+ n (month-days y m))) (1 (- n count)) (t n))))
                      (when (calendar-item (if (zerop offset) (list id :day day)
                                               (list id :adjacent y m day))
                                           (princ-to-string day) :width width :center-text-p t
                                           :disabled-p (not (<= 1 y 9999))
                                           :foreground (if (zerop offset) foreground muted)
                                           :selected-p (and selected (equal (list y m day) (subseq selected 0 3))))
                        (return-from picker-calendar (values (list y m day) t)))))))))))
    (row (:width (lui.layout:grow))
      (when (calendar-item (list id :clear) "Clear" :foreground ink)
        (return-from picker-calendar (values nil t)))
      (column (:width (lui.layout:grow)))
      (when (calendar-item (list id :today) "Today" :foreground ink)
        (return-from picker-calendar (values (subseq (local-today) 0 3) t))))
    (values nil nil)))

(defun picker-display (parts mode)
  (if (eq mode :time) (picker-string parts mode)
      (format nil "~2,'0D/~2,'0D/~4,'0D~A" (second parts) (third parts) (first parts)
              (if (eq mode :datetime) (concatenate 'string " " (picker-string parts :time)) ""))))

(defun parse-picker-input (draft mode)
  (or (picker-parts draft mode)
      (when (and (member mode '(:date :datetime))
                 (= (length draft) (if (eq mode :date) 10 16))
                 (char= #\/ (char draft 2)) (char= #\/ (char draft 5))
                 (or (eq mode :date) (char= #\Space (char draft 10))))
        (picker-parts (concatenate 'string (subseq draft 6 10) "-" (subseq draft 0 2)
                                   "-" (subseq draft 3 5)
                                   (if (eq mode :date) ""
                                       (concatenate 'string "T" (subseq draft 11))))
                      mode))))

(defun calendar-popup (id state parts)
  (let* ((trigger (list id :calendar)) (popup (list id :popup))
         (focus (context-focus *context*))
         (terminal (context-text-mode-p *context*)))
    (let* ((input (list id :input))
           (field-click (or (activated-p input) (activated-p (list id :field))))
           (icon-click (calendar-item trigger "▦" :icon :calendar :accessible-name "Choose date"
                                     :height (lui.layout:grow) :width (lui.layout:fixed (if terminal 3 26)))))
      (cond ((and icon-click (picker-state-open-p state))
             (setf (picker-state-open-p state) nil (context-focus *context*) trigger))
            ((or icon-click field-click)
             (when (or icon-click (not (picker-state-open-p state)))
               (let ((initial (or parts (local-today))))
                 (setf (picker-state-open-p state) t (picker-state-months-p state) nil
                       (picker-state-year state) (first initial)
                       (picker-state-month state) (second initial))
                 (when icon-click
                   (setf (context-focus *context*) (list id :day (third initial))))))
             (when field-click (setf (context-focus *context*) input)))))
    (when (picker-state-open-p state)
      (let ((press (lui.frame::context-pointer-press *context*))
            (bounds (previous-box popup)))
        (cond ((and press bounds
                    (not (some (lambda (target) (find :press (events-for target) :key #'event-kind))
                               (list trigger (list id :input) (list id :field))))
                    (not (lui.frame::contains-p bounds (event-x press) (event-y press))))
               (setf (picker-state-open-p state) nil))
              ((find :escape (events-for focus) :key #'event-key)
               (setf (picker-state-open-p state) nil (context-focus *context*) trigger))
              ((and bounds focus (not (and (consp focus) (equal (first focus) id))))
               (setf (picker-state-open-p state) nil))
              (t
               (let ((*parent* (anchored-popup popup *parent*
                                 (opt :width (lui.layout:fixed (if terminal 32 260))))))
                 (multiple-value-bind (date action) (picker-calendar id state (or parts (local-today)))
                   (when action
                     (pop (lui.frame::context-popups *context*))
                     (setf (picker-state-open-p state) nil (context-focus *context*) trigger)
                     (return-from calendar-popup (values date t)))))))))
    (values nil nil)))

(defun date-time-picker (id value &optional options)
  "Edit a local date, time, or datetime. The field displays MM/DD/YYYY and
returns ISO strings. The calendar opens at the selected date or today's month."
  (let* ((mode (getf options :mode :datetime)) (parts (picker-parts value mode))
         (state (or (gethash id (context-state *context*))
                    (setf (gethash id (context-state *context*)) (make-picker-state))))
         (input (list id :input))
         (result value))
    (unless (equal value (picker-state-value state))
      (setf (picker-state-value state) value
            (picker-state-draft state) (if parts (picker-display parts mode) (or value ""))))
    (column (:id id :width (getf options :width (lui.layout:fit)))
      (panel (append (unless (eq mode :time)
                       (opt :id (list id :field) :interactive-p t :keyboard-focus-p nil))
                     (without-option :mode options) (opt :direction :row :padding 1 :gap 0))
        (let* ((old (picker-state-draft state))
               (draft (text-field input old
                        (opt :width (lui.layout:grow) :accessible-name
                             (ecase mode (:date "Date") (:time "Time") (:datetime "Date and time"))
                             :placeholder (ecase mode (:date "mm/dd/yyyy") (:time "hh:mm")
                                                 (:datetime "mm/dd/yyyy hh:mm")))))
               (parsed (parse-picker-input draft mode)))
          (unless (equal old draft)
            (setf (picker-state-draft state) draft)
            (cond (parsed (setf parts parsed result (picker-string parsed mode)
                                (picker-state-year state) (first parts)
                                (picker-state-month state) (second parts)))
                  ((zerop (length draft)) (setf result nil parts nil)))))
        (unless (eq mode :time)
          (multiple-value-bind (date action) (calendar-popup id state parts)
            (when action
              (let ((next (and date (append date (or (nthcdr 3 parts) '(0 0))))))
                (setf result (and next (picker-string next mode))
                      (picker-state-draft state) (if next (picker-display next mode) ""))
                (request-frame))))))
      (when (eq mode :time)
        (unless parts (setf parts (list 2000 1 1 0 0)))
        (dolist (field '((:hour "Hour" 3 23) (:minute "Minute" 4 59)))
          (destructuring-bind (key title index maximum) field
            (label title)
            (let ((next (round (slider (list id key) (nth index parts)
                                 (opt :minimum 0 :maximum maximum :step 1
                                      :accessible-name title)))))
              (unless (= next (nth index parts))
                (setf (nth index parts) next result (picker-string parts mode))))))))
    (unless (equal result value)
      (let ((parsed (picker-parts result mode)))
        (setf (picker-state-draft state) (if parsed (picker-display parsed mode) "")
              (picker-state-value state) result)))
    (when (or (picker-state-open-p state) (not (equal result value)))
      (when (or (activated-ids) (not (equal result value))) (request-frame)))
    result))

(defun date-picker (id value &optional options)
  "Pick a date by typing or clicking the field. Return YYYY-MM-DD, or NIL when cleared."
  (date-time-picker id value (list* :mode :date options)))
