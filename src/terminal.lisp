(defpackage #:lui.terminal
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame #:lui.widgets #:lui)
  (:export #:make-terminal-context #:render-terminal #:text-lines
           #:run-terminal #:character-width #:text-width #:cell-edge))

(in-package #:lui.terminal)

(fn (character-width integer) ((character character))
  "Portable cell-width approximation for combining marks, CJK and emoji."
  (let ((code (char-code character)))
    (cond ((or (<= #x0300 code #x036f) (<= #x1ab0 code #x1aff)
               (<= #x1dc0 code #x1dff) (<= #x20d0 code #x20ff)
               (<= #xfe00 code #xfe0f) (<= #xfe20 code #xfe2f)
               (= code #x200d) (<= #xe0100 code #xe01ef))
           0)
          ((or (<= #x1100 code #x115f) (<= #x2329 code #x232a)
               (<= #x2e80 code #xa4cf) (<= #xac00 code #xd7a3)
               (<= #xf900 code #xfaff) (<= #xfe10 code #xfe19)
               (<= #xfe30 code #xfe6f) (<= #xff01 code #xff60)
               (<= #xffe0 code #xffe6) (<= #x1f300 code #x1faff)
               (<= #x20000 code #x3fffd))
           2)
          (t 1))))

(fn (text-width integer) ((text string))
  "Return TEXT's terminal column width, accounting for wide and combining characters."
  (loop :for character :across text :sum (character-width character)))

(fn (text-lines list) ((text string) width)
  "Wrap at spaces, preserving explicit newlines. Long words overflow and are clipped."
  (let ((lines nil)
        (start 0)
        (length (length text)))
    (loop
      (let* ((newline (position #\Newline text :start start))
             (end (or newline length))
             (limit (if width (max 1 (floor width))
                        (max 1 (text-width (subseq text start end))))))
        (loop :while (> (text-width (subseq text start end)) limit)
              :do (let* ((split (loop :with columns := 0
                                     :for index :from start :below end
                                     :do (incf columns
                                               (character-width
                                                (char text index)))
                                     :when (> columns limit) :return index
                                     :finally (return end)))
                         (space (position #\Space text :start start
                                                 :end (min end (1+ split))
                                                 :from-end t)))
                    (unless (and space (> space start))
                      (setf space (position #\Space text :start split
                                                            :end end)))
                    (unless space (return))
                    (push (subseq text start space) lines)
                    (setf start (1+ space))))
        (push (subseq text start end) lines)
        (unless newline (return))
        (setf start (1+ newline))))
    (nreverse lines)))

(fn slider-line ((widget widget) (width integer))
  (let* ((fraction (min 1 (max 0 (/ (- (widget-value widget)
                                        (widget-minimum widget))
                                     (- (widget-maximum widget)
                                        (widget-minimum widget))))))
         (readout (format nil " ~D%" (round (* 100 fraction))))
         (label (widget-text widget))
         (prefix (if (and (plusp (length label))
                          (>= width (+ (text-width label)
                                       (length readout) 4)))
                     (concatenate 'string label " ") ""))
         (suffix (if (>= width (+ (text-width prefix) (length readout) 3))
                     readout ""))
         (length (max 1 (- width (text-width prefix) (length suffix))))
         (position (round (* fraction (1- length))))
         (track (make-string length :initial-element #\-)))
    (dotimes (index position) (setf (char track index) #\=))
    (setf (char track position) #\#)
    (values (concatenate 'string prefix track suffix)
            (text-width prefix) length)))

(fn measure-widget ((widget widget) width)
  (let ((lines (text-lines (widget-terminal-text widget) width)))
    (values (max (if (eq (widget-kind widget) :slider) 12 0)
                 (loop :for line :in lines :maximize (text-width line)))
            (length lines))))

(fn (make-terminal-context context) ()
  "Create a fresh frame context with dependency-free terminal text measurement."
  (make-context :text-mode-p t :measure #'measure-widget))

(fn (cell-edge integer) ((position real))
  "Snap every box and clip edge to the same nearest terminal-cell boundary."
  (floor (+ position 0.5)))

(fn (cell-visible-p boolean) ((clip box) (x integer) (y integer)
                             (width integer))
  (and (>= x (cell-edge (box-x clip)))
       (<= (+ x width) (cell-edge (+ (box-x clip) (box-width clip))))
       (>= y (cell-edge (box-y clip)))
       (<= (1+ y) (cell-edge (+ (box-y clip) (box-height clip))))))

(fn paint-character ((cells array) (colors array) style
                    (row integer) (column integer) (left integer)
                    (character character) (width integer))
  (if (zerop width)
      (when (> column left)
        (let ((previous (1- column)))
          (when (and (> previous left)
                     (string= "" (aref cells row previous)))
            (decf previous))
          (setf (aref cells row previous)
                (concatenate 'string (aref cells row previous)
                             (string character)))))
      (progn
        (setf (aref cells row column) (string character)
              (aref colors row column) style)
        (when (= width 2)
          (setf (aref cells row (1+ column)) ""
                (aref colors row (1+ column)) style)))))

(fn paint-panel ((cells array) (colors array) (borders array) style
                (node element) (widget widget))
  (let* ((box (element-box node))
         (left (cell-edge (box-x box)))
         (top (cell-edge (box-y box)))
         (right (1- (cell-edge (+ (box-x box) (box-width box)))))
         (bottom (1- (cell-edge (+ (box-y box) (box-height box)))))
         (square-p (not (eq (toolkit-surface (widget-style widget)) :glass)))
         (corners (if square-p "++++" "╭╮╰╯"))
         (horizontal (if square-p #\- #\─))
         (vertical (if square-p #\| #\│)))
    (flet ((put (x y character)
             (when (and (<= 0 x) (< x (array-dimension cells 1))
                        (<= 0 y) (< y (array-dimension cells 0))
                        (cell-visible-p (element-clip node) x y 1)
                        (not (aref borders y x)))
               (setf (aref cells y x) (string character)
                     (aref colors y x) style
                     (aref borders y x) t))))
      (when (and (<= left right) (<= top bottom))
        (loop :for x :from (1+ left) :below right
              :do (put x top horizontal) (put x bottom horizontal))
        (loop :for y :from (1+ top) :below bottom
              :do (put left y vertical) (put right y vertical))
        (put left top (char corners 0))
        (put right top (char corners 1))
        (put left bottom (char corners 2))
        (put right bottom (char corners 3))))))

(fn paint-canvas ((cells array) (colors array) (borders array)
                  (node element) (widget widget))
  (let ((box (element-box node)) (clip (element-clip node)))
    (dolist (command (widget-value widget))
      (destructuring-bind (kind cx cy radius stroke fill) command
        (assert (eq kind :circle))
        (let ((center-x (+ (box-x box) cx))
              (center-y (+ (box-y box) cy))
              (outline-style (list (or stroke (widget-foreground widget))
                                   (widget-background widget) nil))
              (fill-style (list (or fill (widget-foreground widget))
                                (or fill (widget-background widget)) nil)))
          (loop :for row :from (max 0 (cell-edge (box-y clip)))
                :below (min (array-dimension cells 0)
                            (cell-edge (+ (box-y clip) (box-height clip))))
                :do (loop :for column
                          :from (max 0 (cell-edge (box-x clip)))
                          :below (min (array-dimension cells 1)
                                      (cell-edge (+ (box-x clip)
                                                    (box-width clip))))
                          :unless (aref borders row column)
                            :do (let* ((distance
                                         (sqrt (+ (expt (- (+ column 0.5)
                                                           center-x) 2)
                                                  (expt (- (+ row 0.5)
                                                           center-y) 2))))
                                       (edge (and stroke
                                                  (<= (abs (- distance
                                                              radius))
                                                      0.6))))
                                  (when (or edge
                                            (and fill (< distance radius)))
                                    (setf (aref cells row column)
                                          (if edge "o" ".")
                                          (aref colors row column)
                                          (if edge outline-style
                                              fill-style)))))))))))

(fn terminal-style ((widget widget) (node element) (context context)
                   &optional background)
  (let* ((enabled (and (element-interactive-p node)
                       (not (widget-disabled-p widget))))
         (hover (and enabled
                     (equal (element-id node) (context-hover context))))
         (selected (and enabled (member (widget-kind widget)
                                       '(:tab :list-item :cell))
                        (widget-value widget)))
         (pressed (and hover
                       (equal (element-id node) (context-active context))))
         (filled (or selected pressed))
         (cell-p (eq (widget-kind widget) :cell)))
    (list (cond ((and (widget-disabled-p widget)
                      (not (eq (widget-kind widget) :cell))) "#777777")
                ((and filled cell-p) (widget-foreground widget))
                (filled "#ffffff")
                (hover (widget-accent widget))
                (t (widget-foreground widget)))
          (if filled (if cell-p "#e7effa" (widget-accent widget))
              (or background (widget-background widget)))
          (eq (widget-font-weight widget) :bold)
          (and hover (not filled)))))

(fn write-cell-style ((stream stream) style)
  (destructuring-bind (foreground background bold &optional underline) style
    (format stream "~C[0;~D;~Dm" #\Escape (if bold 1 22)
            (if underline 4 24))
    (loop :for color :in (list foreground background)
          :for channel :in '(38 48)
          :do (when (and (= (length color) 7) (char= (char color 0) #\#))
                (format stream "~C[~D;2;~D;~D;~Dm" #\Escape channel
                        (parse-integer color :start 1 :end 3 :radix 16)
                        (parse-integer color :start 3 :end 5 :radix 16)
                        (parse-integer color :start 5 :end 7 :radix 16))))))

(fn (render-terminal string) ((context context) &key ansi)
  "Return a cell frame; ANSI colors are optional for the raw terminal backend."
  (let* ((root (or (context-root context) (error "No completed frame.")))
         (width (cell-edge (box-width (element-box root))))
         (height (cell-edge (box-height (element-box root))))
         (dimensions (list height width))
         (cells (make-array dimensions :initial-element " "))
         (colors (make-array dimensions :initial-element nil))
         (borders (make-array dimensions :initial-element nil)))
    (visible-elements
     root
     (lambda (node)
       (let ((widget (element-content node))
             (box (element-box node))
             (clip (element-clip node)))
         (when (widget-p widget)
           ;; An opaque floating pane covers sibling borders behind it.
           (when (and (element-floating-p node)
                      (eq (widget-kind widget) :panel))
             (loop :for row :from (max 0 (cell-edge (box-y clip)))
                   :below (min height (cell-edge (+ (box-y clip)
                                                    (box-height clip))))
                   :do (loop :for column
                             :from (max 0 (cell-edge (box-x clip)))
                             :below (min width (cell-edge (+ (box-x clip)
                                                           (box-width clip))))
                             :do (setf (aref borders row column) nil))))
           (let* ((highlight-p (eq (widget-kind widget) :highlight))
                  (splitter-p (eq (widget-kind widget) :splitter))
                  (horizontal-p (eq (widget-orientation widget) :horizontal))
                  (rail-style
                    (when splitter-p
                      (if (and (context-focus-visible-p context)
                               (equal (element-id node)
                                      (context-focus context)))
                          (list (widget-background widget)
                                (widget-accent widget) t)
                          (list (widget-accent widget)
                                (widget-background widget) t))))
                  (thumb (when (eq (widget-kind widget) :scrollbar)
                           (scrollbar-thumb node)))
                  (thumb-top (when thumb (cell-edge (box-y thumb))))
                  (thumb-end (when thumb
                              (cell-edge (+ (box-y thumb)
                                            (box-height thumb)))))
                  (label-p (member (widget-kind widget) '(:label :splitter)))
                  (left (max 0 (cell-edge (box-x clip))))
                  (top (max 0 (cell-edge (box-y clip))))
                  (background (when (and (member (widget-kind widget)
                                                '(:label :list-item))
                                         (< left width)
                                         (< top height))
                                (second (aref colors top left))))
                  (style (terminal-style widget node context background))
                  (padding (element-padding node))
                  (x (cell-edge (+ (box-x box) padding)))
                  (y (cell-edge (+ (box-y box) padding)))
                  (right (cell-edge (+ (box-x box) (box-width box)
                                       (- padding))))
                  (bottom (cell-edge (+ (box-y box) (box-height box)
                                        (- padding))))
                  (w (max 0 (- right x)))
                  (text (cond ((or highlight-p splitter-p thumb) "")
                              ((eq (widget-kind widget) :slider)
                               (slider-line widget w))
                              (t (widget-terminal-text widget)))))
             ;; Parent borders remain intact even with zero child padding.
             (loop :for row :from (max 0 (cell-edge (box-y clip)))
                   :below (min height (cell-edge (+ (box-y clip)
                                                    (box-height clip))))
                   :do (loop :for column
                             :from (max 0 (cell-edge (box-x clip)))
                             :below (min width (cell-edge (+ (box-x clip)
                                                           (box-width clip))))
                             :do (cond
                                   ((and thumb
                                         (or (not (aref borders row column))
                                             (member (aref cells row column)
                                                     '("│" "|")
                                                     :test #'string=)))
                                    (setf (aref cells row column)
                                          (if (and (<= thumb-top row)
                                                   (< row thumb-end))
                                              "█"
                                              (if (eq (toolkit-surface
                                                       (widget-style widget))
                                                      :garnet)
                                                  "░" "│"))
                                          (aref colors row column) style))
                                   ((and splitter-p
                                         (if horizontal-p
                                             (= row (floor (+ y bottom) 2))
                                             (= column
                                                (floor (+ x right) 2))))
                                    (setf (aref cells row column)
                                          (if horizontal-p "─" "│")
                                          (aref colors row column)
                                          rail-style))
                                   (highlight-p
                                    (when (or (plusp (widget-opacity widget))
                                              (= row y) (= row (1- bottom))
                                              (= column x)
                                              (= column (1- right)))
                                      (setf (aref colors row column)
                                            (list "#000000"
                                                  (widget-accent widget) t))))
                                   ((not (or label-p
                                             (aref borders row column)))
                                    (setf (aref cells row column) " "
                                          (aref colors row column) style)))))
             (when (eq (widget-kind widget) :panel)
               (paint-panel cells colors borders style node widget))
             (when (eq (widget-kind widget) :canvas)
               (paint-canvas cells colors borders node widget))
             (loop :for line :in (text-lines text w)
                   :for row :from y :below (min height bottom)
                   :do (loop :with column := x
                             :for char :across line
                             :for size := (character-width char)
                             :while (<= (+ column size) (min width right))
                             :do (when (and (>= row 0) (>= column 0)
                                            (cell-visible-p
                                             clip (if (zerop size)
                                                      (1- column) column)
                                             row (max 1 size))
                                            (loop :for index
                                                  :from (if (zerop size)
                                                            (1- column)
                                                            column)
                                                  :below (+ column size)
                                                  :never (aref borders row
                                                               index)))
                                   (paint-character cells colors style row
                                                    column x char size))
                                 (incf column size))))))))
    (with-output-to-string (stream)
      (let ((previous nil))
        (dotimes (row height)
          (dotimes (column width)
            (let ((style (aref colors row column)))
              (when (and ansi (not (equal style previous)))
                (if style (write-cell-style stream style)
                    (format stream "~C[0m" #\Escape))
                (setf previous style))
              (write-string (aref cells row column) stream)))
          (when ansi
            (format stream "~C[0m" #\Escape)
            (setf previous nil))
          (terpri stream))))))

(fn run-terminal ((draw function) &key title width height (interactive t))
  "Run DRAW using portable text frames and optional line-oriented input.
INTERACTIVE NIL writes one plain frame and returns its context. In interactive
mode, :next moves focus, an empty line activates, and :quit exits. Loading the
optional raw terminal backend replaces this registered runner."
  (declare (ignore title))
  (let ((context (make-terminal-context))
        (*unit* 1)
        (events nil)
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
      (let ((line (read-line *standard-input* nil)))
        (when (or (null line) (string= line ":quit")) (return context))
        (setf events
              (cond ((string= line ":next") (list (make-event :kind :tab)))
                    ((string= line "") (list (make-event :kind :activate)))
                    (t (list (make-event :kind :text :value line)))))))))

(register-backend :terminal #'run-terminal)
