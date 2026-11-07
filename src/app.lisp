(defpackage #:lui
  (:use #:cl #:lui.fn #:lui.widgets #:lui.frame)
  (:export #:run #:register-backend #:available-backends #:units #:*backend*
           #:*unit* #:with-toolkit #:with-palette #:toolkit-palette #:widget-color #:current-toolkit #:toolkit-defaults
           #:register-toolkit #:toolkit-revision
           #:register-toolkit-rendering #:toolkit-paint #:toolkit-geometry
           #:toolkit-native-labels-p
           #:control
           #:define-toolkit
           #:table #:table-row #:table-cell
           #:opt #:panel #:label
           #:button #:tab #:checkbox #:radio #:slider
           #:text-field #:cell #:list-item #:gauge #:canvas
           #:date-picker #:searchable-combobox
           #:*default-backend-function*
           #:*toolkit-revision*))
(in-package #:lui)

(defvar *backends* (make-hash-table :test 'eq))
(defvar *default-backend-function* nil
  "A thunk that returns default backend when called.")
(defvar *backend* nil "Default backend override; NIL selects an available backend.")
(defvar *unit* 1 "Layout spacing unit supplied by the active backend.")

(fn (units real) ((count real))
  "Convert spacing units to backend coordinates: terminal cells or graphical units."
  (* count *unit*))

(fn (register-backend function) ((name symbol) (runner function))
  "Install a runner function under NAME; normally called by a backend."
  (setf (gethash name *backends*) runner))

(fn (available-backends (vector symbol)) ()
  "Return a vector of backend names registered in this Lisp image."
  (let (results)
    (maphash (lambda (name runner)
               (declare (ignore runner))
               (push name results))
             *backends*)
    (make-array (length results) :element-type 'symbol :initial-contents results)))

(fn (run t)
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
                   (loop for backend across (available-backends) return backend)))
         (runner (gethash name *backends*)))
    (unless runner
      (error "Backend ~S is not loaded. Available: ~S" name
             (available-backends)))
    (funcall runner draw :title title :width width :height height
             :interactive interactive)))

(defvar *toolkit* :glass)
(defvar *toolkit-definition* nil)
(defvar *palette* nil)

(defstruct (toolkit (:conc-name %toolkit-))
  parent defaults controls (paint :inherit) (geometry :inherit) (native-labels :inherit))
(defvar *toolkits* (make-hash-table :test 'eq))

(defvar *toolkit-revision* 0)

(fn (find-toolkit toolkit) ((name symbol))
  (or (gethash name *toolkits*) (error "Unknown toolkit ~S." name)))

(fn (rendering-option t) ((name symbol) (key symbol))
  (let* ((entry (find-toolkit name))
         (value (ecase key (:paint (%toolkit-paint entry))
                          (:geometry (%toolkit-geometry entry))
                          (:native-labels (%toolkit-native-labels entry)))))
    (if (not (eq value :inherit)) value
        (when (and (%toolkit-parent entry)
                   (or (not (eq key :native-labels))
                       (and (eq (%toolkit-paint entry) :inherit)
                            (eq (%toolkit-geometry entry) :inherit))))
          (rendering-option (%toolkit-parent entry) key)))))

(fn (toolkit-paint (or null function)) ((name symbol))
  "Return NAME's graphical painter, inherited through its parent, or NIL."
  (rendering-option name :paint))

(fn (toolkit-geometry (or null function)) ((name symbol))
  "Return NAME's graphical geometry callback (widget -> geometry), inherited from its parent."
  (rendering-option name :geometry))

(fn (toolkit-native-labels-p boolean) ((name symbol))
  "Return whether NAME delegates graphical labels to native text rendering."
  (not (null (rendering-option name :native-labels))))

(fn (register-toolkit-rendering symbol) ((name symbol) &key (paint nil paint-p)
                                           (geometry nil geometry-p)
                                           (native-labels nil labels-p))
  "Set graphical callbacks for registered NAME. Omitted keys retain their
settings or inherit from :PARENT; explicit NIL disables the inherited setting."
  (let ((entry (find-toolkit name)))
    (when paint-p (check-type paint (or null function)))
    (when geometry-p (check-type geometry (or null function)))
    (when paint-p (setf (%toolkit-paint entry) paint))
    (when geometry-p (setf (%toolkit-geometry entry) geometry))
    (when labels-p (setf (%toolkit-native-labels entry) (not (null native-labels))))
    (incf *toolkit-revision*))
  name)

(fn (register-toolkit symbol) ((name symbol) &key parent defaults controls
                                   (paint nil paint-p) (geometry nil geometry-p)
                                   (native-labels nil labels-p))
  "Register a toolkit. DEFAULTS is a plist or a zero-argument function.
CONTROLS maps control names to functions taking the public arguments and options.
PAINT, GEOMETRY and NATIVE-LABELS configure graphical rendering; omitted values
inherit only from an explicit PARENT."
  (loop :for ancestor := parent
          :then (%toolkit-parent (find-toolkit ancestor))
        :while ancestor :when (eq ancestor name)
          :do (error "Circular toolkit inheritance at ~S." name))
  (when paint-p (check-type paint (or null function)))
  (when geometry-p (check-type geometry (or null function)))
  (incf *toolkit-revision*)
  (setf (gethash name *toolkits*)
        (make-toolkit :parent parent :defaults defaults :controls controls
                      :paint (if paint-p paint :inherit)
                      :geometry (if geometry-p geometry :inherit)
                      :native-labels (if labels-p (not (null native-labels)) :inherit)))
  name)

(fn (current-toolkit symbol) ()
  "Return the toolkit name active in this drawing scope."
  *toolkit*)

(fn (defaults-of list) ((entry toolkit))
  (let* ((parent (%toolkit-parent entry))
         (source (%toolkit-defaults entry))
         (defaults (if (functionp source) (funcall source) source)))
    (if parent (append defaults (defaults-of (find-toolkit parent)))
        defaults)))

(fn (resolve-palette list) ((defaults list))
  (labels ((colors (tail)
             (cond ((null tail) lui.widgets::*base-palette*)
                   ((eq (car tail) :palette) (append (cadr tail) (colors (cddr tail))))
                   ((member (car tail) '(:foreground :background :accent))
                    (list* (car tail) (cadr tail) (colors (cddr tail))))
                   (t (colors (cddr tail))))))
    (append *palette* (colors defaults))))

(fn (toolkit-palette list) (&optional (name *toolkit*))
  "Return scoped semantic colors followed by NAME's inherited palette."
  (resolve-palette (defaults-of (find-toolkit name))))

(fn (toolkit-defaults (values list list)) (&optional (name *toolkit*))
  "Return resolved appearance defaults and the captured palette as a second value."
  (let* ((defaults (defaults-of (find-toolkit name)))
         (palette (copy-list (resolve-palette defaults))))
    (values (list* :palette palette
                   :foreground (lui.widgets::palette-color palette :foreground)
                   :background (lui.widgets::palette-color palette :background)
                   :accent (lui.widgets::palette-color palette :accent)
                   (without-option :palette defaults))
            palette)))

(fn (call-with-palette t) ((palette list) (draw function))
  (let ((*palette* (append palette *palette*))) (funcall draw)))

(defmacro with-palette ((palette) &body body)
  "Draw BODY with semantic color overrides from PALETTE, a plist.
Nested scopes inherit unspecified roles and restore their parent on exit."
  `(call-with-palette ,palette (lambda () ,@body)))

(fn (override (or null function)) ((kind symbol) (entry toolkit))
  (or (cdr (assoc kind (%toolkit-controls entry)))
      (let ((parent (%toolkit-parent entry)))
        (when parent (override kind (find-toolkit parent))))))

(fn (control t) ((kind symbol) &rest arguments)
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
               id direction clip-p scroll-p scrollbar-p scrollbar-width
               floating-p offset-x offset-y
               interactive-p keyboard-focus-p pointer-focus-p
               foreground background palette radius frost minimum maximum step
               font-size font-family font-weight opacity accent disabled-p
               painter terminal-label terminal-border accessible-name
               placeholder max-results selected-p text)
  "Build widget options, preserving order, explicit NIL, and omitted keys."
  (declare (ignore width height padding gap align cross-align
                   id direction
                   clip-p scroll-p scrollbar-p scrollbar-width
                   floating-p offset-x offset-y interactive-p
                   keyboard-focus-p pointer-focus-p foreground background
                   palette radius frost minimum maximum step font-size font-family
                   font-weight opacity accent disabled-p painter
                   terminal-label terminal-border accessible-name
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
    `(fn (,name t) (,@args &optional options)
       ,doc
       (let* ((entry (or *toolkit-definition* (find-toolkit *toolkit*)))
              (custom (override ,kind entry)))
         (if custom (funcall custom ,@args options)
             (let ((style *toolkit*))
               (multiple-value-bind (defaults palette) (toolkit-defaults)
                 (declare (ignorable palette))
                 ,@body)))))))

(define-control label (text)
  "Display selectable text. Width determines wrapping; no ID is needed."
  (apply #'declare-widget :label style nil text (append options defaults)))

(define-control button (id text)
  "Return true in the frame where the control with this ID activates."
  (apply #'declare-widget :button style id text (append options defaults)))

(fn (without-option list) ((key symbol) (options list))
  (let ((result nil))
    (do ((tail options (cddr tail))) ((null tail) (nreverse result))
      (unless (eq (car tail) key)
        (push (car tail) result)
        (push (cadr tail) result)))))

(fn (selectable boolean) ((kind symbol) (style symbol) id (text string)
                (options list) (defaults list))
  ;; Extract selection while removing its public option in one pass. Preserve
  ;; GETF's first-value rule, including an explicitly supplied NIL.
  (let ((selected nil) (selected-seen nil) (appearance nil))
    (do ((tail options (cddr tail))) ((null tail))
      (if (eq (car tail) :selected-p)
          (unless selected-seen
            (setf selected (cadr tail) selected-seen t))
          (progn
            (push (car tail) appearance)
            (push (cadr tail) appearance))))
    (apply #'declare-widget kind style id text :value selected
           (nreconc appearance defaults))))

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
              (list* :background (lui.widgets::palette-color palette :cell-background "#ffffff")
                     :foreground (lui.widgets::palette-color palette :cell-foreground "#202430") defaults)))

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
  "Register NAME with drawing-time DEFAULTS. Generate PANEL-NAME and local
control functions in label/button/tab/checkbox/radio/slider/text-field/cell/
list-item/gauge/canvas order. Each control accepts a final OPT form."
  (let ((functions '(label button tab checkbox radio slider text-field cell
                     list-item gauge canvas))
        (args '((text) (id text) (id text) (id value text) (id value choice text)
                (id value) (id value) (id text) (id text) (id fraction)
                (id commands))))
    `(progn
       (register-toolkit ,name :defaults (lambda () ,defaults))
       ,@(loop :for local :in names :for fn :in functions :for a :in args
               :collect
               `(fn (,local t) (,@a &optional options)
                  (with-toolkit (,name)
                    (,fn ,@a options))))
       (defmacro ,panel-name (options &body body)
         (list 'with-toolkit (list ,name) (list* 'panel options body))))))

(defstruct picker-state
  (year 2000 :type integer) (month 1 :type integer)
  (open-p nil :type boolean) months-p
  (draft "" :type string) value)

(defstruct (combobox-state (:include edit-state))
  open-p focused-p filter-p highlight)

(fn (combobox-matches (vector (cons integer string))) ((query string) (choices sequence) (limit (integer 1 *)))
  ;; Keep the source index for IDs so filtering never retargets a pointer event.
  (let ((index 0) (count 0) matches)
    (block collect
      (map nil (lambda (choice)
                 (when (search query choice :test #'char-equal)
                   (push (cons index choice) matches)
                   (when (= (incf count) limit) (return-from collect)))
                 (incf index))
           choices))
    (make-array count :element-type '(cons integer string) :initial-contents (nreverse matches))))

(fn (anchored-popup lui.layout:element) (id (anchor lui.layout:element) (options list))
  (let* ((*parent* (lui.layout:make-element))
         (pane (declare-panel *toolkit*
                 (append options (opt :id id :floating-p t :opacity 1
                                      :scroll-p t :scrollbar-p nil :clip-p t
                                      :interactive-p t :keyboard-focus-p nil :padding (units 1))
                         (toolkit-defaults)))))
    (setf (lui.layout:element-popup-anchor pane) anchor)
    (push pane (lui.frame::context-popups *context*))
    pane))

(fn (combobox-popup null) (id (matches (vector (cons integer string))) index (anchor lui.layout:element) reveal)
  (let* ((pane (anchored-popup (list id :popup) anchor nil))
         (*parent* pane))
    (loop for match across matches for i from 0
          for row-id = (list id :choice (car match))
          do (list-item row-id (cdr match)
                        (opt :width (lui.layout:grow) :selected-p (eql i index)))
             (let ((row (gethash row-id (lui.frame::context-ids *context*))))
               (setf (lui.layout:element-keyboard-focus-p row) nil)
               (when (and reveal (eql index i))
                 (setf (lui.layout:element-popup-reveal pane) row))))))

(fn (combobox-completion (or null string)) (id (state combobox-state) (text string)
                         (choices sequence) (limit (integer 1 *))
                         (events (vector event)) (anchor lui.layout:element))
  (let ((navigate (find-if (lambda (event)
                             (and (eq :key (event-kind event))
                                  (member (event-key event) '(:up :down)))) events)))
    (when (or navigate (combobox-state-open-p state))
      (let* ((matches (combobox-matches (if (combobox-state-filter-p state) text "")
                                        choices limit))
             (last (1- (length matches)))
             (old (and (combobox-state-open-p state) (combobox-state-highlight state)))
             (index (and (plusp (length matches)) old (min old last))))
        (loop for event across events do
          (case (event-kind event)
            (:key (case (event-key event)
                    ((:up :down)
                     (setf (combobox-state-open-p state) t
                           index (when (plusp (length matches))
                                   (if (eq :down (event-key event))
                                       (min last (1+ (or index -1)))
                                       (max 0 (1- (or index (1+ last))))))))
                    (:escape (setf (combobox-state-open-p state) nil))))
            (:activate
             (when (combobox-state-open-p state)
               (setf (combobox-state-open-p state) nil)
               (return-from combobox-completion (and index (cdr (aref matches index))))))))
        (setf (combobox-state-highlight state) index)
        (when (and (plusp (length matches)) (combobox-state-open-p state))
          (let ((clicked (find-if (lambda (match) (activated-p (list id :choice (car match))))
                                  matches)))
            (when clicked
              (setf (combobox-state-open-p state) nil)
              (return-from combobox-completion (cdr clicked))))
          (combobox-popup id matches index anchor navigate)))))
  nil)

(fn (searchable-combobox (values t boolean))
    (id value (choices sequence) &optional ((options list) nil))
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

(fn (month-days (integer 28 31)) ((year integer) (month (integer 1 12)))
  (if (= month 2)
      (if (and (zerop (mod year 4))
               (or (not (zerop (mod year 100))) (zerop (mod year 400))))
          29 28)
      (if (member month '(4 6 9 11)) 30 31)))

(deftype date-parts () '(vector integer 3))

(fn (make-date-parts date-parts) ((year integer) (month integer) (day integer))
  (make-array 3 :element-type 'integer :initial-contents (list year month day)))

(fn (parse-picker-date (or null date-parts)) (text)
  "Parse YYYY-MM-DD or MM/DD/YYYY into a year/month/day vector, checking leap years."
  (when (and (stringp text) (= 10 (length text)))
    (flet ((number-at (start end)
             (when (every #'digit-char-p (subseq text start end))
               (parse-integer text :start start :end end))))
      (multiple-value-bind (year month day)
          (cond ((and (char= (char text 4) #\-) (char= (char text 7) #\-))
                 (values (number-at 0 4) (number-at 5 7) (number-at 8 10)))
                ((and (char= (char text 2) #\/) (char= (char text 5) #\/))
                 (values (number-at 6 10) (number-at 0 2) (number-at 3 5))))
        (when (and year month day (<= 1 year 9999) (<= 1 month 12)
                   (<= 1 day (month-days year month)))
          (make-date-parts year month day))))))

(fn (picker-display string) ((date (or null date-parts)))
  (if date (format nil "~2,'0D/~2,'0D/~4,'0D" (aref date 1) (aref date 2) (aref date 0)) ""))

(fn (picker-value (or null string)) ((date (or null date-parts)))
  (when date (format nil "~4,'0D-~2,'0D-~2,'0D" (aref date 0) (aref date 1) (aref date 2))))

(fn (calendar-start (integer 0 6)) ((year integer) (month (integer 1 12)))
  ;; Gregorian weekday, Sunday = 0, independent of time zones and OS clocks.
  (let* ((previous (1- year))
         (days (+ (* 365 previous) (floor previous 4)
                  (- (floor previous 100)) (floor previous 400))))
    (loop :for m :from 1 :below month :do (incf days (month-days year m)))
    (mod (1+ days) 7)))

(defparameter *month-names*
  #("January" "February" "March" "April" "May" "June" "July" "August"
    "September" "October" "November" "December"))

(fn (local-today date-parts) ()
    (multiple-value-bind (s m h day month year)
        (decode-universal-time (get-universal-time))
        (declare (ignore s m h))
    (make-date-parts year month day)))

(fn (shift-month (values integer (integer 1 12)))
    ((year integer) (month (integer 1 12)) (delta integer))
  (multiple-value-bind (year-offset index) (floor (+ month -1 delta) 12)
    (values (+ year year-offset) (1+ index))))

(fn (calendar-item boolean) (id (text string) &rest options)
  (list-item id text (append options (opt :font-size 14))))

(fn (calendar-arrow-focus null) (id (state picker-state))
  (let ((focus (context-focus *context*)))
    (when (and (consp focus) (equal (first focus) id) (eq (second focus) :day))
      (let ((day (third focus)))
        (loop for event across (events-for focus) do
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

(fn (picker-calendar (values (or null date-parts) boolean))
    (id (state picker-state) (selected (or null date-parts)))
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
                                     :width (lui.layout:percent (/ 1 3)) :selected-p (= m month))
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
                                           :selected-p (equalp (make-date-parts y m day) selected))
                        (return-from picker-calendar (values (make-date-parts y m day) t)))))))))))
    (row (:width (lui.layout:grow))
      (when (calendar-item (list id :clear) "Clear" :foreground ink)
        (return-from picker-calendar (values nil t)))
      (column (:width (lui.layout:grow)))
      (when (calendar-item (list id :today) "Today" :foreground ink)
        (return-from picker-calendar (values (local-today) t))))
    (values nil nil)))

(fn (calendar-popup (values (or null date-parts) boolean))
    (id (state picker-state) (parts (or null date-parts)))
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
                       (picker-state-year state) (aref initial 0)
                       (picker-state-month state) (aref initial 1))
                 (when icon-click
                   (setf (context-focus *context*) (list id :day (aref initial 2))))))
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

(fn (date-picker (or null string)) (id value &optional ((options list) nil))
  "Type a date as MM/DD/YYYY or pick it from the calendar. Return YYYY-MM-DD
or NIL when cleared. An incomplete or invalid draft preserves the model value."
  (let* ((date (parse-picker-date value))
         (state (or (gethash id (context-state *context*))
                    (setf (gethash id (context-state *context*)) (make-picker-state))))
         (result value))
    (unless (equal value (picker-state-value state))
      (setf (picker-state-value state) value
            (picker-state-draft state) (if date (picker-display date) (or value ""))))
    (column (:id id :width (getf options :width (lui.layout:fit)))
      (panel (append (opt :id (list id :field) :interactive-p t :keyboard-focus-p nil)
                     options (opt :direction :row :padding 1 :gap 0))
        (let* ((old (picker-state-draft state))
               (draft (text-field (list id :input) old
                                  (opt :width (lui.layout:grow) :accessible-name "Date"
                                       :placeholder "mm/dd/yyyy"))))
          (unless (equal old draft)
            (let ((parsed (parse-picker-date draft)))
              (setf (picker-state-draft state) draft)
              (when (or parsed (zerop (length draft)))
                (setf date parsed result (picker-value parsed)))
              (when parsed
                (setf (picker-state-year state) (aref parsed 0)
                      (picker-state-month state) (aref parsed 1))))))
        (multiple-value-bind (chosen action) (calendar-popup id state date)
          (when action
            (setf date chosen result (picker-value chosen)
                  (picker-state-draft state) (picker-display chosen))
            (request-frame)))))
    (unless (equal result value)
      (setf (picker-state-draft state) (picker-display date)
            (picker-state-value state) result)
      (request-frame))
    (when (and (picker-state-open-p state) (plusp (length (activated-ids)))) (request-frame))
    result))
