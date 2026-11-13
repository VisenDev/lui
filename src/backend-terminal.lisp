(defpackage #:lui.terminal
  (:use #:cl #:%lui.fn #:%lui.layout #:%lui.frame #:%lui.widgets #:lui)
  (:import-from #:uncursed #:character-width)
  (:export #:make-terminal-context #:render-terminal #:text-lines
           #:%run-terminal #:character-width #:terminal-text-width
           #:cell-edge))

(in-package #:lui.terminal)

(fn (terminal-text-width integer) ((text string))
  "Return the terminal cell width of TEXT, including wide characters."
  (uncursed:display-width text))

(fn (text-lines (vector string)) ((text string) width)
  "Wrap TEXT to WIDTH terminal cells; NIL preserves its explicit line breaks."
  (%lui.text:wrap-lines text (and width (max 1 (floor width)))
                       (lambda (string start end)
                         (loop :for index :from start :below end
                               :sum (character-width (char string index))))))

(defvar *rect*)

(fn (make-buffer array) ((width integer) (height integer))
  "Create a terminal cell array with WIDTH columns and HEIGHT rows."
  ;; Uncursed exposes drawing and redisplay, but buffer construction is internal.
  (let ((buffer (make-array (list height width))))
    (uncursed::clear-buffer buffer)
    buffer))

(fn (cell-style uncursed:style) (foreground background &optional bold
                                                         underline)
  "Construct an uncursed style from foreground, background, and emphasis options."
  (flet ((color (value)
           (if (stringp value)
               (and (= (length value) 7) (char= (char value 0) #\#)
                    (parse-integer value :start 1 :radix 16)) value)))
    (uncursed:make-style :fg (color foreground) :bg (color background)
                         :boldp bold :underlinep underline)))

(fn (slider-line (values string integer integer)) ((widget widget) (width
                                                                    integer))
  "Return a slider's text and the track limits used for terminal pointer input."
  (let* ((fraction (min 1 (max 0 (/ (- (widget-value widget)
                                       (widget-minimum widget))
                                    (- (widget-maximum widget)
                                       (widget-minimum widget))))))
         (readout (format nil " ~D%" (round (* 100 fraction))))
         (label (widget-text widget))
         (prefix (if (and (plusp (length label))
                          (>= width (+ (terminal-text-width label)
                                       (length readout) 4)))
                     (concatenate 'string label " ") ""))
         (suffix (if (>= width (+ (terminal-text-width prefix) (length
                                                                readout) 3))
                     readout ""))
         (length (max 1 (- width (terminal-text-width prefix) (length
                                                               suffix))))
         (position (round (* fraction (1- length))))
         (track (make-string length :initial-element #\-)))
    (dotimes (index position) (setf (char track index) #\=))
    (setf (char track position) #\#)
    (values (concatenate 'string prefix track suffix)
            (terminal-text-width prefix) length)))

(fn (measure-widget (values integer integer)) ((widget widget) width)
  "Measure a widget with terminal cell widths and toolkit geometry."
  (let ((lines (text-lines (widget-terminal-text widget) width)))
    (values (max (if (eq (widget-kind widget) :slider) 12 0)
                 (loop :for line :across lines :maximize (terminal-text-width
                                                          line)))
            (length lines))))

(fn (make-terminal-context context) ()
  "Create a fresh frame context with uncursed terminal text measurement."
  (make-context :text-mode-p t :measure #'measure-widget))

(fn (cell-edge integer) ((position real))
  "Snap every box and clip edge to the same nearest terminal-cell boundary."
  (floor (+ position 0.5f0)))

(fn (cell-visible-p boolean) ((clip box) (x integer) (y integer)
                              (width integer))
  "Test whether a cell span is contained in the solved clip rectangle."
  (and (>= x (cell-edge (box-x clip)))
       (<= (+ x width) (cell-edge (box-right clip)))
       (>= y (cell-edge (box-y clip)))
       (<= (1+ y) (cell-edge (box-bottom clip)))))

(fn (paint-character (or null integer)) ((cells array) style (row integer)
                                         (column integer)
                                         (left integer) (character character)
                                         (width integer))
  "Write a character and style into a visible terminal cell span."
  (when (or (plusp width) (> column left))
    (when (zerop width)
      (decf column)
      (when (and (> column left)
                 (zerop (length (uncursed::cell-string (aref cells row
                                                             column)))))
        (decf column)))
    (handler-bind ((uncursed:wide-char-overwrite-error
                    (lambda (condition) (declare (ignore condition))
                      (invoke-restart 'uncursed:overwrite-char))))
      (uncursed:put character (1+ row) (1+ column) *rect* style cells))))

(fn (paint-panel boolean) ((cells array) (borders array) style
                           (node element) (widget widget))
  "Paint a terminal panel's background and toolkit border characters."
  (let* ((box (element-box node))
         (left (cell-edge (box-x box)))
         (top (cell-edge (box-y box)))
         (right (1- (cell-edge (box-right box))))
         (bottom (1- (cell-edge (box-bottom box))))
         (border (or (widget-terminal-border widget)
                     (if (zerop (widget-radius widget)) "++++-|" "╭╮╰╯─│")))
         (horizontal (char border 4))
         (vertical (char border 5)))
    (flet ((put (x y character)
             (when (and (<= 0 x) (< x (array-dimension cells 1))
                        (<= 0 y) (< y (array-dimension cells 0))
                        (cell-visible-p (element-clip node) x y 1)
                        (not (aref borders y x)))
               (setf (uncursed::cell-string (aref cells y x)) (string
                                                               character)
                     (uncursed::cell-style (aref cells y x)) style
                     (aref borders y x) t))))
      (when (and (<= left right) (<= top bottom))
        (loop :for x :from (1+ left) :below right
              :do (put x top horizontal) (put x bottom horizontal))
        (loop :for y :from (1+ top) :below bottom
              :do (put left y vertical) (put right y vertical))
        (put left top (char border 0))
        (put right top (char border 1))
        (put left bottom (char border 2))
        (put right bottom (char border 3))))))

(fn (paint-canvas (values)) ((cells array) (borders array)
                             (node element) (widget widget))
  "Translate custom canvas commands into terminal cells within the node's clip."
  (let ((box (element-box node)) (clip (element-clip node)))
    (dolist (command (widget-value widget))
      (destructuring-bind (kind cx cy radius stroke fill) command
        (assert (eq kind :circle))
        (let ((center-x (+ (box-x box) cx))
              (center-y (+ (box-y box) cy))
              (extent (+ radius (if stroke 0.6f0 0)))
              (outline-style (cell-style (or stroke (widget-foreground
                                                     widget))
                                         (widget-background widget) nil))
              (fill-style (cell-style (or fill (widget-foreground widget))
                                      (or fill (widget-background widget))
                                      nil)))
          (loop :for row :from (max 0 (cell-edge (box-y clip))
                                    (ceiling (- center-y extent 0.5f0)))
                :below (min (array-dimension cells 0)
                            (cell-edge (box-bottom clip))
                            (1+ (floor (+ center-y extent -0.5f0))))
                :do (loop :for column
                          :from (max 0 (cell-edge (box-x clip))
                                     (ceiling (- center-x extent 0.5f0)))
                          :below (min (array-dimension cells 1)
                                      (cell-edge (box-right clip))
                                      (1+ (floor (+ center-x extent -0.5f0))))
                          :unless (aref borders row column)
                          :do (let* ((distance
                                      (sqrt (+ (expt (- (+ column 0.5f0)
                                                        center-x) 2)
                                               (expt (- (+ row 0.5f0)
                                                        center-y) 2))))
                                     (edge (and stroke
                                                (<= (abs (- distance
                                                            radius))
                                                    0.6f0))))
                                (when (or edge
                                          (and fill (< distance radius)))
                                  (setf (uncursed::cell-string
                                         (aref cells
                                               row column))
                                        (if edge "o" ".")
                                        (uncursed::cell-style (aref cells row
                                                                    column))
                                        (if edge outline-style
                                            fill-style))))))))))
  (values))

(fn (terminal-style uncursed:style) ((widget widget) (node element) (context
                                                                     context)
                                     &optional background)
  "Resolve a widget's terminal colors and interaction emphasis."
  (let* ((enabled (and (element-interactive-p node)
                       (not (widget-disabled-p widget))))
         (hover (and enabled
                     (member (widget-kind widget)
                             '(:button :tab :checkbox :radio :list-item
                               :cell))
                     (equal (element-id node) (context-hover context))))
         (selected (and enabled (member (widget-kind widget)
                                        '(:tab :list-item :cell))
                        (widget-value widget)))
         (pressed (and hover
                       (equal (element-id node) (context-active context))))
         (filled (or selected pressed))
         (cell-p (eq (widget-kind widget) :cell)))
    (cell-style (cond ((and (widget-disabled-p widget)
                            (not (eq (widget-kind widget) :cell))) "#777777")
                      ((and filled cell-p) (widget-foreground widget))
                      (filled "#ffffff")
                      (hover (widget-accent widget))
                      (t (widget-foreground widget)))
                (if filled (if cell-p "#e7effa" (widget-accent widget))
                    (or background (widget-background widget)))
                (eq (widget-font-weight widget) :bold)
                (and hover (not filled)))))

(defstruct terminal-paint-state
  "Resolved cell geometry and styles shared by a widget's background and text."
  (widget (make-widget) :type widget)
  (clip (make-box) :type box)
  (style nil :type (or null uncursed:style))
  (rail-style nil :type (or null uncursed:style))
  (thumb nil :type (or null box))
  (x 0 :type integer) (y 0 :type integer)
  (right 0 :type integer) (bottom 0 :type integer))

(fn (terminal-background-color t) ((cells array) (widget widget) (clip box))
  "Read the underlying cell background for transparent labels and list items."
  (let ((left (max 0 (cell-edge (box-x clip))))
        (top (max 0 (cell-edge (box-y clip)))))
    (when (and (member (widget-kind widget) '(:label :list-item))
               (< left (array-dimension cells 1))
               (< top (array-dimension cells 0)))
      (uncursed:bg (uncursed::cell-style (aref cells top left))))))

(fn (terminal-paint-state terminal-paint-state)
    ((context context) (cells array) (node element))
  "Resolve a widget's terminal colors, padding, scrollbar, and splitter emphasis."
  (let* ((widget (element-content node)) (box (element-box node))
         (clip (element-clip node)) (padding (element-padding node))
         (rail-style
          (when (eq (widget-kind widget) :splitter)
            (if (and (context-focus-visible-p context)
                     (equal (element-id node) (context-focus context)))
                (cell-style (widget-background widget)
                            (widget-accent widget) t)
                (cell-style (widget-accent widget)
                            (widget-background widget) t)))))
    (make-terminal-paint-state
     :widget widget :clip clip :rail-style rail-style
     :style (terminal-style
             widget node context (terminal-background-color cells widget
                                                            clip))
     :thumb (when (eq (widget-kind widget) :scrollbar) (scrollbar-thumb node))
     :x (cell-edge (+ (box-x box) padding))
     :y (cell-edge (+ (box-y box) padding))
     :right (cell-edge (- (box-right box) padding))
     :bottom (cell-edge (- (box-bottom box) padding)))))

(fn (paint-terminal-cell (values))
    ((state terminal-paint-state) cell border (row integer) (column integer))
  "Paint one background cell, preserving borders and special rail/highlight shapes."
  (let* ((widget (terminal-paint-state-widget state))
         (kind (widget-kind widget)) (thumb (terminal-paint-state-thumb
                                             state))
         (horizontal (eq (widget-orientation widget) :horizontal))
         (x (terminal-paint-state-x state)) (y (terminal-paint-state-y state))
         (right (terminal-paint-state-right state))
         (bottom (terminal-paint-state-bottom state)))
    (cond
      ((and thumb (or (not border)
                      (member (uncursed::cell-string cell) '("│" "|")
                              :test #'string=)))
       (setf (uncursed::cell-string cell)
             (if (<= (cell-edge (box-y thumb)) row
                     (1- (cell-edge (box-bottom thumb))))
                 "█" "│")
             (uncursed::cell-style cell) (terminal-paint-state-style state)))
      ((and (eq kind :splitter)
            (if horizontal (= row (floor (+ y bottom) 2))
                (= column (floor (+ x right) 2))))
       (setf (uncursed::cell-string cell) (if horizontal "─" "│")
             (uncursed::cell-style cell) (terminal-paint-state-rail-style
                                          state)))
      ((member kind '(:hr :vr))
       (setf (uncursed::cell-string cell) (if (eq kind :hr) "─" "│")
             (uncursed::cell-style cell) (terminal-paint-state-style state)))
      ((eq kind :highlight)
       (when (or (plusp (widget-opacity widget)) (= row y) (= row (1- bottom))
                 (= column x) (= column (1- right)))
         (setf (uncursed::cell-style cell)
               (cell-style "#000000" (widget-accent widget) t))))
      ((not (or (member kind '(:label :splitter)) border))
       (setf (uncursed::cell-string cell) " "
             (uncursed::cell-style cell) (terminal-paint-state-style
                                          state)))))
  (values))

(fn (paint-terminal-text (values))
    ((state terminal-paint-state) (cells array) (borders array))
  "Paint wrapped text without splitting wide characters or overwriting borders."
  (let* ((widget (terminal-paint-state-widget state))
         (x (terminal-paint-state-x state)) (y (terminal-paint-state-y state))
         (right (terminal-paint-state-right state))
         (bottom (terminal-paint-state-bottom state))
         (width (array-dimension cells 1)) (height (array-dimension cells 0))
         (clip (terminal-paint-state-clip state)) (w (max 0 (- right x)))
         (text (case (widget-kind widget)
                 ((:highlight :splitter :scrollbar) "")
                 (:slider (slider-line widget w))
                 (otherwise (widget-terminal-text widget)))))
    (loop :for line :across (text-lines text w)
          :for row :from y :below (min height bottom)
          :do (loop :with column := x
                    :for char :across line :for size := (character-width char)
                    :while (<= (+ column size) (min width right))
                    :do (when (and (>= row 0) (>= column 0)
                                   (cell-visible-p
                                    clip (if (zerop size) (1- column) column)
                                    row (max 1 size))
                                   (loop :for index
                                         :from (if (zerop size)
                                                   (1- column) column)
                                         :below (+ column size)
                                         :never (aref borders row index)))
                          (paint-character cells (terminal-paint-state-style
                                                  state)
                                           row column x char size))
                    (incf column size))))
  (values))

(fn (paint-terminal-node (values))
    ((context context) (cells array) (borders array) (node element))
  "Paint a widget's clipped background, border or canvas, and terminal text."
  (let ((widget (element-content node)))
    (when (widget-p widget)
      (let ((state (terminal-paint-state context cells node))
            (clip (element-clip node))
            (opaque (and (not (eq (element-position node) :automatic))
                         (eq (widget-kind widget) :panel))))
        (loop :for row :from (max 0 (cell-edge (box-y clip)))
              :below (min (array-dimension cells 0)
                          (cell-edge (box-bottom clip)))
              :do (loop :for column :from (max 0 (cell-edge (box-x clip)))
                        :below (min (array-dimension cells 1)
                                    (cell-edge (box-right clip)))
                        :do (when opaque (setf (aref borders row column) nil))
                        (paint-terminal-cell state (aref cells row column)
                                             (aref borders row column)
                                             row column)))
        (case (widget-kind widget)
          (:panel
           (paint-panel cells borders (terminal-paint-state-style state)
                        node widget))
          (:canvas (paint-canvas cells borders node widget))
          (otherwise nil))
        (paint-terminal-text state cells borders))))
  (values))

(fn (paint-terminal array) ((context context) (cells array))
  "Paint the solved context into CELLS using toolkit geometry and terminal styles."
  (let* ((root (or (context-root context)
                   (error '%lui.conditions:frame-state-error
                          :operation :paint-terminal
                          :format-control "No completed frame.")))
         (height (array-dimension cells 0)) (width (array-dimension cells 1))
         (*rect* (uncursed:make-rect :x 0 :y 0 :rows height :cols width))
         (borders (make-array (list height width) :initial-element nil)))
    (visible-elements root (lambda (node)
                             (paint-terminal-node context cells borders
                                                  node)))
    cells))

(fn (render-terminal string) ((context context) &key ansi)
  "Render a plain or ANSI-colored snapshot through uncursed's cells and styles."
  (let ((cells (make-buffer (cell-edge (context-width context))
                            (cell-edge (context-height context))))
        (previous uncursed:*default-style*))
    (paint-terminal context cells)
    (with-output-to-string (stream)
      (let ((*terminal-io* stream))
        (dotimes (row (array-dimension cells 0))
          (dotimes (column (array-dimension cells 1))
            (let ((cell (aref cells row column)))
              (when ansi
                (uncursed-sys:set-style-from-old previous
                                                 (uncursed::cell-style cell))
                (setf previous (uncursed::cell-style cell)))
              (write-string (uncursed::cell-string cell) stream)))
          (when ansi
            (uncursed-sys:set-style-from-old previous
                                             uncursed:*default-style*)
            (setf previous uncursed:*default-style*))
          (terpri stream))))))

(fn (terminal-line (or null string (eql :quit))) ((context context) buffer)
  "Read a fallback terminal command, update focus, and return text or a quit request."
  (loop :for char := (read-char-no-hang *standard-input* nil :eof)
        :do (cond ((or (eql char #\Newline) (eq char :eof))
                   (when (and (eq char :eof) (zerop (length buffer)))
                     (return :quit))
                   (return (prog1 (copy-seq buffer)
                             (setf (fill-pointer buffer) 0))))
                  (char (vector-push-extend char buffer))
                  (t (let ((delay (%lui.frame:frame-wait context)))
                       (when (zerop delay) (return nil))
                       (sleep (min delay 0.02f0)))))))

(fn (run-line-terminal context) ((draw function) &key title width height
                                                   (interactive t))
  "Plain snapshots and line-oriented input for redirected or limited terminals."
  (declare (ignore title))
  (let ((context (make-terminal-context))
        (*unit* 1)
        (events nil)
        (buffer (make-array 32 :element-type 'character
                            :adjustable t :fill-pointer 0))
        (width (or width 80))
        (height (or height 24)))
    (loop
     (with-frame (context width height :events events)
       (funcall draw))
     (when interactive (format t "~C[H~C[2J" #\Escape #\Escape))
     (write-string (render-terminal context))
     (finish-output)
     (unless interactive (return context))
     ;; Portable line-input fallback. Native terminal raw input is added separately.
     (let ((line (terminal-line context buffer)))
       (when (or (eq line :quit) (equal line ":quit")) (return context))
       (%lui.frame:limit-frame-rate context)
       (setf events
             (cond ((null line) nil)
                   ((string= line ":next") (list (make-event :kind :tab)))
                   ((string= line "") (list (make-event :kind :activate)))
                   (t (list (make-event :kind :text :value line)))))))))

;; Terminal state, terminal capabilities and input decoding belong to uncursed.
(defstruct input
  (pending "" :type string)
  (escape-time nil)
  (events nil :type list)
  (quit-p nil :type boolean))

(fn (show-cursor (values)) ()
  "Restore cursor visibility on the terminal output stream."
  ;; Uncursed has no visibility-only API; its shape API and terminfo
  ;; cnorm/cvvis also change blinking.
  ;; Visibility alone preserves the user's inherited shape and blink mode.
  (format *terminal-io* "~C[?25h" #\Escape)
  (values))

(fn (terminal-size (values integer integer)) ()
  "Return the terminal's current column and row counts."
  (let ((size (uncursed:terminal-dimensions)))
    (values (max 1 (cdr size)) (max 1 (car size)))))

(fn (focused-node (values (or null element) boolean)) ((context context))
  "Look up the focused element in CONTEXT's completed layout."
  (gethash (context-focus context) (%lui.frame:context-ids context)))

(fn (input-focus (values (or null element) boolean)) ((input input) (context
                                                                     context))
  "Resolve the input parser's focus override or the context's current focus."
  (focused-node (pending-input-context context (input-events input))))

(fn (editing-input-p boolean) ((input input) (context context))
  "Test whether the current input target is a text editor."
  (text-field-focused-p (pending-input-context context (input-events input))))

(fn (key-event (values)) ((input input) (key symbol))
  "Queue a semantic keyboard event in the terminal input state."
  (push (make-event :kind :key :key key) (input-events input))
  (values))

(fn (slider-change (values)) ((input input) (context context) (event event))
  "Translate terminal slider pointer input into a value-change event."
  (let ((capture (context-active context)))
    (dolist (pending (reverse (rest (input-events input))))
      (case (event-kind pending)
        (:press
         (setf capture (or (event-id pending)
                           (%lui.frame:hit context (event-x pending)
                                           (event-y pending)))))
        ((:release :cancel) (setf capture nil))
        (:move
         (when (and (event-buttons pending)
                    (not (logbitp 0 (event-buttons pending))))
           (setf capture nil))) (otherwise nil)))
    (let* ((press (eq (event-kind event) :press))
           (id (if press (%lui.frame:hit context (event-x event)
                                         (event-y event)) capture))
           (target (gethash id (%lui.frame:context-ids context)))
           (widget (when target (element-content target))))
      ;; Preserve the topmost target even when a batch starts on a non-slider.
      (when press (setf (event-id event) id))
      (when (and (widget-p widget) (eq (widget-kind widget) :slider)
                 (not (widget-disabled-p widget)))
        (let* ((box (element-box target))
               (padding (element-padding target))
               (left (cell-edge (+ (box-x box) padding)))
               (width (- (cell-edge (+ (box-x box) (box-width box)
                                       (- padding))) left)))
          (multiple-value-bind (line offset length)
              (slider-line widget width)
            (declare (ignore line))
            (push (make-event
                   :kind :change :id id
                   :value (+ (widget-minimum widget)
                             (* (- (widget-maximum widget)
                                   (widget-minimum widget))
                                (min 1 (max 0
                                            (/ (- (floor (event-x event))
                                                  left offset)
                                               (max 1 (1- length))))))))
                  (input-events input)))))))
  (values))

(fn (mouse-event (values))
    ((input input) (data uncursed:mouse-data) &optional context)
  "Translate terminal mouse coordinates, button state, and wheel actions into input."
  (let* ((button (uncursed:mouse-data-button data))
         (state (uncursed:mouse-data-state data))
         (wheel (member button '(:wheel-up :wheel-down)))
         (release (eq state :release))
         (move (or (eq state :drag) (eq button :hover))))
    (push (make-event
           :kind (cond (wheel :scroll) (release :release) (move :move)
                       (t :press))
           :x (- (uncursed:mouse-data-col data) 0.500001d0)
           :y (- (uncursed:mouse-data-row data) 0.500001d0)
           :button (if (eq button :right) :secondary :primary)
           :buttons (unless wheel
                      (if release 0
                          (case button (:left 1) (:middle 4) (:right 2)
                                (otherwise 0))))
           :dragging-p (and move (eq button :left))
           :scroll-mode :smooth :value (if (eq button :wheel-down) 3 -3))
          (input-events input))
    (when (and context (eq button :left) (not release))
      (slider-change input context (first (input-events input)))))
  (values))

(fn (terminal-character-input (values))
    ((input input) (context context) (kind character))
  "Queue text input or activate the focused control for an unmodified space."
  (let* ((node (input-focus input context))
         (widget (and node (element-content node))))
    (push (if (and (eql kind #\Space) (widget-p widget)
                   (member (widget-kind widget)
                           '(:button :checkbox :radio :tab :list-item :cell)))
              (make-event :kind :activate)
              (make-event :kind :text :value (string kind)))
          (input-events input)))
  (values))

(fn (terminal-key-name (or null string))
    (kind key)
  "Return the textual key name used by shared editor shortcut translation."
  (if (characterp kind) (string kind)
      (and key (symbol-name key))))

(fn (terminal-tab-p boolean)
    (kind control)
  "Recognize a literal tab or the terminal Control-I equivalent."
  (or (and (eql kind #\i) control) (eql kind #\Tab)))

(fn (terminal-quit-p boolean)
    (kind control)
  "Recognize Control-C and Control-Q as terminal session exit requests."
  (and control (characterp kind) (not (null
                                       (find kind "cq" :test #'char-equal)))))

(fn (terminal-navigation-key symbol)
    (kind)
  "Map uncursed arrow names to shared keys and preserve other keyword events."
  (case kind (:left-arrow :left) (:right-arrow :right)
        (:up-arrow :up) (:down-arrow :down)
        (otherwise (when (keywordp kind) kind))))

(fn (decode-event (values)) ((input input) event (context context))
  "Translate an uncursed event into LUI input or terminal lifecycle state."
  (let* ((kind (uncursed:event-kind event))
         (control (uncursed:event-controlp event))
         (alt (uncursed:event-altp event))
         (shift (uncursed:event-shiftp event))
         (key (terminal-navigation-key kind))
         (name (terminal-key-name kind key))
         (editing (editing-input-p input context))
         (command (and name editing
                       (readline-key name :control control :alt alt
                                     :shift shift))))
    (cond
      ((uncursed:mouse-event-p event) (mouse-event input kind context))
      ((terminal-quit-p kind control)
       (setf (input-quit-p input) t))
      ((terminal-tab-p kind control)
       (push (make-event :kind :tab :key (when shift :backward))
             (input-events input)))
      ((or (eql kind #\Newline) (eql kind #\Return))
       (push (make-event :kind :activate) (input-events input)))
      (command (key-event input command))
      ((or (eql kind #\Rubout) (eq key :backspace))
       (key-event input :backspace))
      ((eql kind #\Escape) (key-event input :escape))
      (key
       (key-event input (if shift
                            (case key (:left :shift-left) (:right
                                                           :shift-right)
                                  (:home :shift-home) (:end :shift-end)
                                  (otherwise key)) key)))
      ((and (characterp kind) (not control) (not alt))
       (terminal-character-input input context kind))))
  (values))

(fn (input-sequence-length (or null integer)) ((text string))
  "Find the length of a complete terminal escape sequence, or return NIL."
  ;; Frame complete character sequences; uncursed owns their interpretation.
  (cond ((zerop (length text)) nil)
        ((char/= (char text 0) #\Escape) 1)
        ((= (length text) 1) nil)
        ((find (char text 1) "[O")
         (let ((end (position-if (lambda (character)
                                   (<= 64 (char-code character) 126))
                                 text :start 2)))
           (and end (1+ end))))
        (t 2)))

(fn (read-input (values)) ((input input) (context context) (timeout real))
  "Read available terminal input with TIMEOUT and retain incomplete sequences."
  (let ((end (+ (get-internal-real-time)
                (* timeout internal-time-units-per-second))))
    (loop
     (let ((chunk (with-output-to-string (stream)
                    (loop :for character := (read-char-no-hang
                                             *terminal-io* nil :eof)
                          :while (characterp character)
                          :do (write-char character stream)
                          :finally (when (eq character :eof)
                                     (setf (input-quit-p input) t))))))
       (setf (input-pending input) (concatenate 'string
                                                (input-pending input) chunk))
       ;; Emergency quit stays available even after a truncated control sequence.
       (when (or (find (code-char 3) chunk) (find (code-char 17) chunk))
         (setf (input-quit-p input) t))
       (loop :for size := (input-sequence-length (input-pending input))
             :while size
             :do (let ((*standard-input*
                        (make-string-input-stream
                         (subseq (input-pending input) 0 size))))
                   (decode-event input (uncursed-sys:read-event) context)
                   (setf (input-pending input)
                         (subseq (input-pending input) size)
                         (input-escape-time input) nil)))
       (when (string= (input-pending input) (string #\Escape))
         (let ((now (get-internal-real-time)))
           (cond ((and (input-escape-time input)
                       (>= (- now (input-escape-time input))
                           (* 0.1f0 internal-time-units-per-second)))
                  (key-event input :escape)
                  (setf (input-pending input) ""
                        (input-escape-time input) nil))
                 ((null (input-escape-time input))
                  (setf (input-escape-time input) now)))))
       (when (or (input-events input) (input-quit-p input)
                 (>= (get-internal-real-time) end))
         (return))
       (sleep 0.005f0))))
  (values))

(fn (slice-cells string) ((text string) (start integer) (width integer))
  "Extract TEXT's visible cell interval without splitting wide characters."
  (with-output-to-string (stream)
    (loop :with column := 0
          :for character :across text
          :for size := (character-width character)
          :while (<= (+ column size) (+ start width))
          :do (cond ((>= column start) (write-char character stream))
                    ((> (+ column size) start) (write-char #\Space stream)))
          (incf column size))))

(fn (draw-focus (values)) ((context context) screen)
  "Position the terminal cursor at the focused editor's visible caret."
  (let* ((node (focused-node context))
         (widget (and node (element-content node))))
    (when (and (widget-p widget)
               (not (eq (widget-kind widget) :splitter))
               (or (context-focus-visible-p context)
                   (eq (widget-kind widget) :text-field)))
      (let* ((box (element-box node))
             (clip (element-clip node))
             (padding (element-padding node))
             (origin (cell-edge (+ (box-x box) padding)))
             (x (max 0 origin (cell-edge (box-x clip))))
             (y (cell-edge (+ (box-y box) padding)))
             (right (min (context-width context)
                         (cell-edge (box-right clip))
                         (cell-edge (+ (box-x box) (box-width box)
                                       (- padding)))))
             (width (max 0 (- right x)))
             (state (gethash (element-id node) (context-state context)))
             (field-p (eq (widget-kind widget) :text-field))
             (cursor (if (and field-p state)
                         (1+ (terminal-text-width
                              (subseq (widget-display-value widget) 0
                                      (min (length (widget-value widget))
                                           (edit-state-cursor state)))))
                         0))
             (offset (max 0 (- cursor (max 1 (1- width)))))
             (text (if (eq (widget-kind widget) :slider)
                       (slider-line
                        widget (max 0 (- (cell-edge
                                          (+ (box-x box) (box-width box)
                                             (- padding)))
                                         origin)))
                       (widget-terminal-text widget))))
        (when (and (plusp width) (<= 0 y) (< y (context-height context))
                   (<= (cell-edge (box-y clip)) y)
                   (< y (cell-edge (box-bottom clip))))
          ;; Focus is part of the canvas so incremental redraws can erase it.
          (let ((text (slice-cells text (+ offset (- x origin)) width)))
            ;; Focus uses the terminal's default colors, not the panel palette.
            (loop :for column :from x :below (+ x (terminal-text-width text))
                  :do (setf (uncursed::cell-style
                             (aref uncursed::*put-buffer* y column))
                            uncursed:*default-style*))
            (uncursed:puts text (1+ y) (1+ x) (uncursed:screen-rect)
                           (uncursed:make-style :reversep t)))
          (when field-p
            (let ((column (+ origin cursor (- offset))))
              (when (and (<= x column) (< column right))
                (setf (screen-cursor screen) (list y column)))))))))
  (values))

(defclass terminal-screen (uncursed:tui)
  ((context :accessor screen-context) (cursor :initform nil :accessor
                                              screen-cursor))
  (:documentation "Uncursed screen retaining the LUI frame and visible editor cursor."))

(defmethod uncursed:redisplay ((screen terminal-screen))
  (paint-terminal (screen-context screen) uncursed::*put-buffer*)
  (setf (screen-cursor screen) nil)
  (draw-focus (screen-context screen) screen))

(fn (display-frame (values)) ((context context) screen)
  "Present a solved frame through uncursed and update the visible cursor."
  (let ((width (cell-edge (context-width context)))
        (height (cell-edge (context-height context))))
    (unless (and (slot-boundp screen 'uncursed::%canvas)
                 (= width (uncursed:cols screen)) (= height (uncursed:rows
                                                             screen)))
      (setf (uncursed::canvas screen) (make-buffer width height)
            (uncursed::screen screen) (make-buffer width height))
      (uncursed-sys:clear-screen))
    (setf (screen-context screen) context)
    (uncursed:set-cursor-shape :invisible)
    (let ((*standard-output* *terminal-io*)) (uncursed:redisplay screen))
    (when (screen-cursor screen)
      (apply #'uncursed-sys:set-cursor-position (screen-cursor screen))
      (show-cursor))
    (finish-output *terminal-io*))
  (values))

(fn (wait-frame (values)) ((input input) (context context) width height)
  "Wait for input, resize, or the context's next scheduled frame."
  (loop
   (let ((remaining (%lui.frame:frame-wait context)))
     (read-input input context (max 0.001f0 (min 0.1f0 remaining)))
     (when (or (zerop remaining) (input-events input) (input-quit-p input))
       (return)))
   (multiple-value-bind (columns rows) (terminal-size)
     (when (or (/= (or width columns) (context-width context))
               (/= (or height rows) (context-height context)))
       (return))))
  (values))

(fn (%run-terminal context)
    ((draw function) &key title width height (interactive t))
  "Run an interactive uncursed session with terminal restoration on every exit."
  (if (or (not interactive)
          (not (interactive-stream-p *standard-input*))
          (not (interactive-stream-p *standard-output*))
          #+unix (let ((term (uiop:getenv "TERM")))
                   (or (null term) (zerop (length term))
                       (string-equal term "dumb"))))
      (run-line-terminal draw :title title :width width :height height
                         :interactive interactive)
      (let ((context (make-terminal-context)) (*unit* 1) (input (make-input))
            (saved nil) (screen (make-instance 'terminal-screen)))
        (unwind-protect
             (progn
               #+unix (terminfo:set-terminal (uiop:getenv "TERM"))
               (setf saved (uncursed-sys:setup-terminal
                            #+unix uncursed-sys:+stdin+))
               (uncursed-sys:enable-alternate-screen)
               (uncursed:enable-mouse :hover t)
               (uncursed-sys:clear-screen)
               (loop
                (multiple-value-bind (columns rows) (terminal-size)
                  (let ((events (nreverse (input-events input))))
                    (with-frame (context (or width columns) (or height rows)
                                         :events events)
                      (funcall draw))
                    (when events
                      (let ((*context* context)) (request-frame)))))
                (setf (input-events input) nil)
                (display-frame context screen)
                (wait-frame input context width height)
                (when (input-quit-p input) (return context))
                (%lui.frame:limit-frame-rate context)))
          (when saved
            (unwind-protect
                 (progn
                   (uncursed-sys:set-style uncursed:*default-style*)
                   (uncursed:disable-mouse)
                   (show-cursor)
                   (uncursed-sys:disable-alternate-screen)
                   (finish-output *terminal-io*))
              (uncursed-sys:restore-terminal saved
                                             #+unix
                                             uncursed-sys:+stdin+)))))))

(register-backend :terminal #'%run-terminal)
