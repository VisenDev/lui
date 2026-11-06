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
           #:date-time-picker #:searchable-combobox))

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
               max-results selected-p text)
  "Build widget options, preserving order, explicit NIL, and omitted keys."
  (declare (ignore width height padding gap align cross-align
                   id direction mode
                   clip-p scroll-p scrollbar-p scrollbar-width
                   floating-p offset-x offset-y interactive-p
                   keyboard-focus-p pointer-focus-p foreground background
                   radius frost minimum maximum step font-size font-family
                   font-weight opacity accent disabled-p painter
                   terminal-label accessible-name
                   max-results selected-p text))
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
  (value-widget :text-field style id value "" (append options defaults)))

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
  (open-p nil :type boolean)
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

(defun combobox-popup (id matches index anchor reveal)
  ;; Retain toolkit bindings while building the pane. END-FRAME places it
  ;; above ordinary content and below the debugger.
  (let* ((*parent* (lui.layout:make-element))
         (pane (declare-panel *toolkit*
                 (append (opt :id (list id :popup) :floating-p t :opacity 1
                              :scroll-p t :scrollbar-p nil :clip-p t
                              :interactive-p t :keyboard-focus-p nil :padding (units 1))
                         (toolkit-defaults))))
         (*parent* pane))
    (setf (lui.layout:element-popup-anchor pane) anchor)
    (push pane (lui.frame::context-popups *context*))
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

(defun picker-calendar (id state parts)
  (row (:width (lui.layout:grow) :gap (units 0.5))
    (when (button (list id :previous-month) "<"
                  (opt :accessible-name "Previous month"
                       :disabled-p (and (= (picker-state-year state) 1)
                                        (= (picker-state-month state) 1))))
      (if (= (picker-state-month state) 1)
          (setf (picker-state-month state) 12
                (picker-state-year state) (1- (picker-state-year state)))
          (decf (picker-state-month state))))
    (label (format nil "~4,'0D-~2,'0D" (picker-state-year state)
                   (picker-state-month state)) (opt :width (lui.layout:grow)))
    (when (button (list id :next-month) ">"
                  (opt :accessible-name "Next month"
                       :disabled-p (and (= (picker-state-year state) 9999)
                                        (= (picker-state-month state) 12))))
      (if (= (picker-state-month state) 12)
          (setf (picker-state-month state) 1
                (picker-state-year state) (1+ (picker-state-year state)))
          (incf (picker-state-month state)))))
  (row (:width (lui.layout:grow))
    (dolist (day '("Su" "Mo" "Tu" "We" "Th" "Fr" "Sa"))
      (label day (opt :width (lui.layout:percent (/ 1 7))))))
  (let* ((year (picker-state-year state)) (month (picker-state-month state))
         (start (calendar-start year month)) (count (month-days year month)))
    (dotimes (week (ceiling (+ start count) 7))
      (row (:width (lui.layout:grow))
        (dotimes (column 7)
          (let ((day (+ 1 (- (+ (* week 7) column) start))))
            (if (<= 1 day count)
                (when (tab (list id :day day) (format nil "~D" day)
                           (opt :width (lui.layout:percent (/ 1 7))
                                :selected-p
                                (and (= year (first parts))
                                     (= month (second parts))
                                     (= day (third parts)))))
                  (setf (first parts) year (second parts) month
                        (third parts) day
                        (picker-state-open-p state) nil))
                (label "" (opt :width (lui.layout:percent (/ 1 7))))))))))
  parts)

(defun date-time-picker (id value &optional options)
  "Pick a local date/time as YYYY-MM-DDTHH:MM, returning the current value.
Use :MODE :DATE or :TIME in OPT for YYYY-MM-DD or HH:MM. VALUE may be NIL.
Text accepts valid Gregorian dates and 24-hour times; invalid drafts remain
editable without replacing VALUE. The calendar initially shows January 2000
when VALUE is NIL. No timezone conversion is performed."
  (let* ((mode (getf options :mode :datetime))
         (parts (picker-parts value mode))
         (state (or (gethash id (context-state *context*))
                    (setf (gethash id (context-state *context*))
                          (make-picker-state))))
         (result value))
    (unless (equal value (picker-state-value state))
      (setf (picker-state-draft state) (or value "")
            (picker-state-value state) value)
      (when parts
        (setf (picker-state-year state) (first parts)
              (picker-state-month state) (second parts))))
    (panel (append (without-option :mode options)
                   (opt :id id :padding (units 1) :gap (units 0.5)))
      (let* ((draft (text-field (list id :input) (picker-state-draft state)
                                (opt :width (lui.layout:grow)
                                     :accessible-name
                                     (ecase mode (:date "Date") (:time "Time")
                                                 (:datetime
                                                  "Date and time")))))
             (parsed (picker-parts draft mode)))
        (when parsed
          (unless (equal draft (picker-state-draft state))
            (setf (picker-state-year state) (first parsed)
                  (picker-state-month state) (second parsed)))
          (setf parts parsed result draft))
        (setf (picker-state-draft state) draft)
        (when (and (plusp (length draft)) (not parsed))
          (label (ecase mode
                   (:date "Use YYYY-MM-DD")
                   (:time "Use HH:MM")
                   (:datetime "Use YYYY-MM-DDTHH:MM")))))
      (unless parts (setf parts (list 2000 1 1 0 0)))
      (unless (eq mode :time)
        (when (button (list id :calendar) "Choose date")
          (setf (picker-state-open-p state)
                (not (picker-state-open-p state))))
        (when (picker-state-open-p state)
          (picker-calendar id state parts)
          (unless (picker-state-open-p state)
            (setf result (picker-string parts mode)))))
      (unless (eq mode :date)
        (dolist (field '((:hour "Hour" 3 23) (:minute "Minute" 4 59)))
          (destructuring-bind (key title index maximum) field
            (label title)
            (let ((next (round (slider (list id key) (nth index parts)
                                      (opt :minimum 0 :maximum maximum
                                           :step 1 :accessible-name title)))))
              (unless (= next (nth index parts))
                (setf (nth index parts) next
                      result (picker-string parts mode))))))))
    (unless (equal result value)
      (setf (picker-state-value state) result
            (picker-state-draft state) result)
      (request-frame))
    result))
