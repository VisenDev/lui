(defpackage #:lui.seven.model
  (:use #:cl #:lui.fn)
  (:export #:parse-number #:parse-date #:temperature #:flight-valid-p
           #:timer #:make-timer #:timer-elapsed #:timer-duration
           #:advance-timer #:timer-fraction
           #:crud #:make-crud #:crud-records #:crud-selected #:crud-select
           #:crud-create #:crud-update #:crud-delete #:crud-filter
           #:person-id #:person-name #:person-surname
           #:circles #:make-circles #:circles-items #:circles-editing
           #:circles-undo #:circles-redo #:circle-id #:circle-x #:circle-y
           #:circle-radius #:circle-find #:circle-add #:circle-hit
           #:circle-begin-adjust #:circle-preview #:circle-commit
           #:circle-cancel #:circle-undo #:circle-redo
           #:sheet #:make-sheet #:sheet-cell #:sheet-set #:sheet-recomputed
           #:cell-text #:cell-value #:cell-problem #:cell-revision
           #:cell-display #:cell-index #:cell-address #:parse-formula))
(in-package #:lui.seven.model)

;; JSCL's source reader does not recognize the named Return character.
(defparameter *whitespace* (mapcar #'code-char '(9 10 13 32)))

(fn whitespace-p ((char character))
  (not (null (find char *whitespace*))))

(fn finite-number-p (value)
  (and (realp value)
       (handler-case (zerop (- value value))
         (arithmetic-error () nil))))

(fn parse-number ((source string))
  "Parse a finite decimal/scientific number without invoking the Lisp reader."
  (let* ((text (string-trim *whitespace* source))
         (length (length text)) (at 0) (sign 1)
         (mantissa 0) (digits 0) (fraction 0) (exponent 0))
    (when (or (zerop length) (> length 256)) (return-from parse-number nil))
    (labels ((peek () (when (< at length) (char text at)))
             (digit () (and (peek) (digit-char-p (peek)))))
      (when (find (peek) "+-")
        (when (char= (peek) #\-) (setf sign -1))
        (incf at))
      (loop :while (digit)
            :do (setf mantissa (+ (* mantissa 10) (digit)))
                (incf digits) (incf at))
      (when (eql (peek) #\.)
        (incf at)
        (loop :while (digit)
              :do (setf mantissa (+ (* mantissa 10) (digit)))
                  (incf digits) (incf fraction) (incf at)))
      (when (zerop digits) (return-from parse-number nil))
      (when (and (peek) (find (peek) "eE"))
        (incf at)
        (let ((negative (eql (peek) #\-)) (count 0))
          (when (and (peek) (find (peek) "+-")) (incf at))
          (loop :while (digit)
                :do (setf exponent (+ (* exponent 10) (digit)))
                    (incf count) (incf at)
                    (when (> exponent 4096) (return-from parse-number nil)))
          (when (zerop count) (return-from parse-number nil))
          (when negative (setf exponent (- exponent)))))
      (unless (= at length) (return-from parse-number nil))
      (handler-case
          (let ((number (/ (* sign mantissa
                               (expt 10 (- exponent fraction)))
                            1.0d0)))
            (when (finite-number-p number) number))
        (arithmetic-error () nil)))))

(fn parse-date ((text string))
  "Validate DD.MM.YYYY and return an ordered YYYYMMDD integer or NIL."
  (when (and (= 10 (length text)) (char= (char text 2) #\.)
             (char= (char text 5) #\.)
             (loop :for i :in '(0 1 3 4 6 7 8 9)
                   :always (digit-char-p (char text i))))
    (let* ((day (parse-integer text :end 2))
           (month (parse-integer text :start 3 :end 5))
           (year (parse-integer text :start 6))
           (leap (or (zerop (mod year 400))
                     (and (zerop (mod year 4))
                          (not (zerop (mod year 100)))))))
      (when (and (<= 1 year 9999) (<= 1 month 12)
                 (<= 1 day (if (and (= month 2) leap) 29
                               (nth (1- month)
                                    '(31 28 31 30 31 30 31 31 30 31 30 31)))))
        (+ (* year 10000) (* month 100) day)))))

(fn temperature ((text string) (from symbol))
  (let ((number (parse-number text)))
    (when number
      (ecase from
        (:celsius (+ (/ (* number 9) 5) 32))
        (:fahrenheit (/ (* (- number 32) 5) 9))))))

(fn flight-valid-p ((start string) (end string) &optional return-p)
  (let ((departure (parse-date start)) (arrival (parse-date end)))
    (and departure (or (not return-p) (and arrival (>= arrival departure))))))

(defstruct* timer
  (elapsed 0 :type real) (duration 10 :type real)
  (last-time nil :type (or null real)))

(fn advance-timer ((timer timer) (now real) &key duration reset)
  "Integrate the old running state up to NOW, then apply duration/reset input.
A stopped timer never includes paused wall time when its duration is increased."
  (assert (and (>= now 0) (or (null duration) (and (realp duration)
                                                  (>= duration 0)))))
  (when (timer-last-time timer)
    (assert (>= now (timer-last-time timer)))
    (when (< (timer-elapsed timer) (timer-duration timer))
      (setf (timer-elapsed timer)
            (min (timer-duration timer)
                 (+ (timer-elapsed timer) (- now (timer-last-time timer)))))))
  (setf (timer-last-time timer) now)
  (when duration (setf (timer-duration timer) duration))
  (when reset (setf (timer-elapsed timer) 0))
  (values (timer-elapsed timer)
          (< (timer-elapsed timer) (timer-duration timer))))

(fn (timer-fraction real) ((timer timer))
  (if (zerop (timer-duration timer)) 1
      (min 1 (/ (timer-elapsed timer) (timer-duration timer)))))

(defstruct* person (id 0 :type integer) (name "" :type string)
  (surname "" :type string))
(defstruct* crud (records nil :type list) selected (next-id 0 :type integer))

(fn crud-select ((model crud) id)
  (let ((record (find id (crud-records model) :key #'person-id)))
    (setf (crud-selected model) (when record id))
    record))

(fn crud-create ((model crud) (name string) (surname string))
  (let ((record (make-person :id (incf (crud-next-id model))
                             :name name :surname surname)))
    (setf (crud-records model) (append (crud-records model) (list record)))
    record))

(fn crud-update ((model crud) id (name string) (surname string))
  (let ((record (find id (crud-records model) :key #'person-id)))
    (when record
      (setf (person-name record) name (person-surname record) surname)
      t)))

(fn crud-delete ((model crud) id)
  (let ((found (find id (crud-records model) :key #'person-id)))
    (when found
      (setf (crud-records model)
            (remove id (crud-records model) :key #'person-id))
      (when (eql id (crud-selected model)) (setf (crud-selected model) nil))
      t)))

(fn (crud-filter list) ((model crud) (prefix string))
  (remove-if-not
   (lambda (person)
     (let ((surname (person-surname person)))
       (and (<= (length prefix) (length surname))
            (string= prefix surname :end2 (length prefix)))))
   (crud-records model)))

(defstruct* circle
  (id 0 :type integer) (x 0 :type real) (y 0 :type real)
  (radius 20 :type real))
(defstruct* circles
  (items nil :type list) (next-id 0 :type integer)
  (undo nil :type list) (redo nil :type list) editing)

(fn circle-find ((model circles) id)
  (find id (circles-items model) :key #'circle-id))

(fn record-circle-change ((model circles) (change list))
  (push change (circles-undo model))
  (setf (circles-redo model) nil))

(fn circle-add
    ((model circles) (x real) (y real) &optional ((radius real) 20))
  (assert (and (null (circles-editing model)) (>= radius 0)))
  (let ((circle (make-circle :id (incf (circles-next-id model))
                             :x x :y y :radius radius)))
    (setf (circles-items model) (append (circles-items model) (list circle)))
    (record-circle-change model (list :create circle))
    circle))

(fn circle-hit ((model circles) (x real) (y real))
  (let ((nearest nil) (distance nil))
    (dolist (circle (circles-items model))
      (let ((d (+ (expt (- x (circle-x circle)) 2)
                  (expt (- y (circle-y circle)) 2))))
        (when (and (< d (expt (circle-radius circle) 2))
                   (or (null distance) (< d distance)))
          (setf nearest circle distance d))))
    nearest))

(fn circle-begin-adjust ((model circles) id)
  (assert (null (circles-editing model)))
  (let ((circle (circle-find model id)))
    (assert circle)
    (setf (circles-editing model) (cons id (circle-radius circle)))))

(fn circle-preview ((model circles) (radius real))
  (assert (and (circles-editing model) (>= radius 0)))
  (setf (circle-radius (circle-find model (car (circles-editing model))))
        radius))

(fn circle-commit ((model circles))
  (when (circles-editing model)
    (let* ((edit (shiftf (circles-editing model) nil))
           (radius (circle-radius (circle-find model (car edit)))))
      (unless (= radius (cdr edit))
        (record-circle-change
         model (list :resize (car edit) (cdr edit) radius))
        t))))

(fn circle-cancel ((model circles))
  (when (circles-editing model)
    (circle-preview model (cdr (circles-editing model)))
    (setf (circles-editing model) nil)))

(fn apply-circle-change ((model circles) (change list) forward)
  (ecase (first change)
    (:create
     (let ((circle (second change)))
       (setf (circles-items model)
             (if forward (append (circles-items model) (list circle))
                 (remove (circle-id circle) (circles-items model)
                         :key #'circle-id)))))
    (:resize
     (setf (circle-radius (circle-find model (second change)))
           (if forward (fourth change) (third change))))))

(fn circle-undo ((model circles))
  (assert (null (circles-editing model)))
  (let ((change (pop (circles-undo model))))
    (when change
      (apply-circle-change model change nil)
      (push change (circles-redo model))
      t)))

(fn circle-redo ((model circles))
  (assert (null (circles-editing model)))
  (let ((change (pop (circles-redo model))))
    (when change
      (apply-circle-change model change t)
      (push change (circles-undo model))
      t)))

(defstruct* cell
  (text "" :type string) (ast '(:text "")) parse-problem
  (value "") problem
  (dependencies nil :type list) (users nil :type list)
  (revision 0 :type integer))
(defstruct* sheet
  (cells (make-hash-table) :type hash-table)
  (recomputed nil :type list))

(fn cell-index (address)
  "Accept a row-major integer or an A0:Z99 address; return NIL if invalid."
  (typecase address
    (integer (when (<= 0 address 2599) address))
    (string
     (when (and (> (length address) 1)
                (<= (char-code #\A) (char-code (char-upcase (char address 0)))
                    (char-code #\Z))
                (loop :for at :from 1 :below (length address)
                      :always (digit-char-p (char address at))))
       (let ((row (parse-integer address :start 1)))
         (when (< row 100)
           (+ (* row 26)
              (- (char-code (char-upcase (char address 0))) 65))))))))

(fn (cell-address string) ((index integer))
  (assert (<= 0 index 2599))
  (format nil "~C~D" (code-char (+ 65 (mod index 26))) (floor index 26)))

(fn cell-range ((first integer) (last integer))
  (loop :for row :from (min (floor first 26) (floor last 26))
          :to (max (floor first 26) (floor last 26))
        :append (loop :for column :from (min (mod first 26) (mod last 26))
                        :to (max (mod first 26) (mod last 26))
                      :collect (+ (* row 26) column))))

(defparameter *operations*
  '(("add" . :add) ("sub" . :sub) ("mul" . :mul) ("div" . :div)
    ("mod" . :mod) ("sum" . :sum) ("prod" . :prod)))

(fn parse-formula ((source string))
  "Return AST, distinct dependency indices, and NIL or an error keyword.
Numeric/text literals and =function(arguments), references and ranges follow SCells.
No input is passed to READ, EVAL, or INTERN. Limit text length and nesting."
  (let* ((text (string-trim *whitespace* source))
         (length (length text)) (at 1) (refs (make-hash-table)))
    (when (> length 4096) (return-from parse-formula (values nil nil :parse)))
    (unless (and (plusp length) (char= (char text 0) #\=))
      (return-from parse-formula
        (values (or (parse-number text) (list :text (copy-seq source)))
                nil nil)))
    (catch 'formula-error
      (labels ((fail (reason) (throw 'formula-error (values nil nil reason)))
               (peek () (when (< at length) (char text at)))
               (space () (loop :while (and (peek) (whitespace-p (peek)))
                              :do (incf at)))
               (take (char)
                 (space)
                 (when (eql (peek) char) (incf at) t))
               (word ()
                 (space)
                 (let ((start at))
                   (loop :while (and (peek) (alphanumericp (peek)))
                         :do (incf at))
                   (when (= start at) (fail :parse))
                   (subseq text start at)))
               (reference (name)
                 (let ((index (cell-index name)))
                   (unless index (fail :reference))
                   (setf (gethash index refs) t)
                   index))
               (expression (depth)
                 (when (> depth 64) (fail :parse))
                 (space)
                 (cond
                   ((and (peek) (find (peek) "+-.0123456789"))
                    (let ((start at))
                      (loop :while (and (peek)
                                        (find (peek) "+-.eE0123456789"))
                            :do (incf at))
                      (or (parse-number (subseq text start at))
                          (fail :parse))))
                   ((and (peek) (alpha-char-p (peek)))
                    (let ((name (word)))
                      (cond
                        ((take #\()
                         (let ((op (cdr (assoc name *operations*
                                             :test #'string-equal)))
                               (args nil))
                           (unless op (fail :name))
                           (unless (take #\))
                             (loop (push (expression (1+ depth)) args)
                                   (when (take #\)) (return))
                                   (unless (take #\,) (fail :parse))))
                           (cons :call (cons op (nreverse args)))))
                        ((take #\:)
                         (let* ((first (reference name))
                                (last (reference (word))))
                           (dolist (index (cell-range first last))
                             (setf (gethash index refs) t))
                           (list :range first last)))
                        (t (cons :ref (reference name))))))
                   (t (fail :parse)))))
        (let ((ast (expression 0)))
          (space)
          (unless (= at length) (fail :parse))
          (values ast (sort (loop :for index :being :the :hash-keys :of refs
                                  :collect index) #'<)
                  nil))))))

(fn (sheet-cell cell) ((model sheet) address)
  (let ((index (cell-index address)))
    (assert index () "Invalid cell address ~S." address)
    (or (gethash index (sheet-cells model))
        (setf (gethash index (sheet-cells model)) (make-cell)))))

(fn apply-operation ((operation symbol) (arguments list))
  (when (and (member operation '(:add :sub :mul :div :mod))
             (/= (length arguments) 2))
    (return-from apply-operation (values nil :value)))
  (when (and (member operation '(:div :mod)) (zerop (second arguments)))
    (return-from apply-operation (values nil :division)))
  (handler-case
      (let ((value
              (ecase operation
                (:add (+ (first arguments) (second arguments)))
                (:sub (- (first arguments) (second arguments)))
                (:mul (* (first arguments) (second arguments)))
                (:div (/ (first arguments) (second arguments)))
                (:mod (rem (first arguments) (second arguments)))
                (:sum (reduce #'+ arguments :initial-value 0))
                (:prod (reduce #'* arguments :initial-value 1)))))
        (if (finite-number-p value) value (values nil :number)))
    (arithmetic-error () (values nil :number))))

(fn evaluate-formula ((model sheet) ast)
  (catch 'evaluation-error
    (labels ((fail (problem) (throw 'evaluation-error (values nil problem)))
             (reference (index)
               (let ((cell (sheet-cell model index)))
                 (when (cell-problem cell) (fail (cell-problem cell)))
                 ;; As in SCells, textual cells have numeric value zero.
                 (if (numberp (cell-value cell)) (cell-value cell) 0)))
             (evaluate (node)
               (if (numberp node) node
                   (ecase (first node)
                     (:text (second node))
                     (:ref (reference (cdr node)))
                     (:range (mapcar #'reference
                                     (cell-range (second node) (third node))))
                     (:call
                      (let* ((arguments
                               (loop :for arg :in (cddr node)
                                     :for value := (evaluate arg)
                                     :append (if (listp value) value
                                                 (list value)))))
                        (multiple-value-bind (value problem)
                            (apply-operation (second node) arguments)
                          (when problem (fail problem))
                          value)))))))
      (let ((value (evaluate ast)))
        (if (listp value) (values nil :value) value)))))

(fn affected-cells ((model sheet) (start integer))
  (let ((seen (make-hash-table)) (pending (list start)))
    (loop :for index := (pop pending)
          :while index
          :unless (gethash index seen)
            :do (setf (gethash index seen) t)
                (dolist (user (cell-users (sheet-cell model index)))
                  (push user pending)))
    seen))

(fn sheet-set ((model sheet) address (text string))
  "Edit one cell and return changed value/error indices. Recompute only affected
cells whose inputs changed. SHEET-RECOMPUTED exposes evaluation work for tests."
  (let* ((index (cell-index address)) (cell (sheet-cell model address))
         (changed (make-hash-table)) (remaining (make-hash-table))
         (queue nil) (evaluated nil))
    (setf (sheet-recomputed model) nil)
    (when (string= text (cell-text cell)) (return-from sheet-set nil))
    (multiple-value-bind (ast dependencies problem) (parse-formula text)
      (dolist (dependency (cell-dependencies cell))
        (let ((source (sheet-cell model dependency)))
          (setf (cell-users source) (remove index (cell-users source)))))
      (setf (cell-text cell) (copy-seq text) (cell-ast cell) ast
            (cell-parse-problem cell) problem
            (cell-dependencies cell) dependencies)
      (dolist (dependency dependencies)
        (pushnew index (cell-users (sheet-cell model dependency)))))
    (let ((affected (affected-cells model index)))
      ;; Kahn ordering is iterative, including for 2600-cell chains. Leftovers
      ;; are cycles or depend on cycles; both display the cycle error.
      (maphash
       (lambda (id present)
         (declare (ignore present))
         (let ((degree (count-if (lambda (dep) (gethash dep affected))
                                 (cell-dependencies (sheet-cell model id)))))
           (setf (gethash id remaining) degree)
           (when (zerop degree) (push id queue))))
       affected)
      (labels ((assign (id value problem)
                 (let ((target (sheet-cell model id)))
                   (push id evaluated)
                   (incf (cell-revision target))
                   (unless (and (equalp value (cell-value target))
                                (eq problem (cell-problem target)))
                     (setf (gethash id changed) t))
                   (setf (cell-value target) value
                         (cell-problem target) problem))))
        (loop :for id := (pop queue)
              :for target := (when id (sheet-cell model id))
              :while id
              :do (remhash id remaining)
                  (when (or (= id index)
                            (some (lambda (dep) (gethash dep changed))
                                  (cell-dependencies target)))
                    (multiple-value-bind (value problem)
                        (if (cell-parse-problem target)
                            (values nil (cell-parse-problem target))
                            (evaluate-formula model (cell-ast target)))
                      (assign id value problem)))
                  (dolist (user (cell-users target))
                    (when (gethash user remaining)
                      (when (zerop (decf (gethash user remaining)))
                        (push user queue)))))
        (maphash
         (lambda (id degree)
           (declare (ignore degree))
           (when (or (= id index)
                     (not (eq :cycle (cell-problem (sheet-cell model id)))))
             (assign id nil :cycle)))
         remaining)))
    (setf (sheet-recomputed model) (sort evaluated #'<))
    (sort (loop :for id :being :the :hash-keys :of changed :collect id) #'<)))

(fn (cell-display string) ((cell cell))
  (if (cell-problem cell)
      (format nil "#~A!" (case (cell-problem cell)
                          (:division "DIV/0") (:reference "REF")
                          (otherwise (symbol-name (cell-problem cell)))))
      (if (stringp (cell-value cell)) (cell-value cell)
          (let ((*read-default-float-format* 'double-float))
            (format nil "~A" (cell-value cell))))))
