(defpackage #:lui.terminal
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame #:lui.widgets #:lui)
  (:export #:make-terminal-context #:render-terminal #:text-lines
           #:run-terminal #:character-width #:text-width))

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

(fn measure-widget ((widget widget) width)
  (let ((lines (text-lines (widget-terminal-text widget) width)))
    (values (loop :for line :in lines :maximize (text-width line))
            (length lines))))

(fn (make-terminal-context context) ()
  (make-context :measure #'measure-widget))

(fn (cell-visible-p boolean) ((clip box) (x integer) (y integer)
                             (width integer))
  (and (>= x (ceiling (box-x clip)))
       (<= (+ x width) (+ (box-x clip) (box-width clip)))
       (>= y (ceiling (box-y clip)))
       (< y (+ (box-y clip) (box-height clip)))))

(fn paint-character ((cells array) (row integer) (column integer)
                    (left integer) (character character) (width integer))
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
        (setf (aref cells row column) (string character))
        (when (= width 2)
          (setf (aref cells row (1+ column)) "")))))

(fn paint-panel ((cells array) (node element) (widget widget))
  (let* ((box (element-box node))
         (left (floor (box-x box)))
         (top (floor (box-y box)))
         (right (1- (floor (+ (box-x box) (box-width box)))))
         (bottom (1- (floor (+ (box-y box) (box-height box)))))
         (motif-p (eq (widget-style widget) :motif))
         (corners (if motif-p "++++" "╭╮╰╯"))
         (horizontal (if motif-p #\- #\─))
         (vertical (if motif-p #\| #\│)))
    (flet ((put (x y character)
             (when (and (<= 0 x) (< x (array-dimension cells 1))
                        (<= 0 y) (< y (array-dimension cells 0))
                        (cell-visible-p (element-clip node) x y 1))
               (setf (aref cells y x) (string character)))))
      (when (and (<= left right) (<= top bottom))
        (loop :for x :from (1+ left) :below right
              :do (put x top horizontal) (put x bottom horizontal))
        (loop :for y :from (1+ top) :below bottom
              :do (put left y vertical) (put right y vertical))
        (put left top (char corners 0))
        (put right top (char corners 1))
        (put left bottom (char corners 2))
        (put right bottom (char corners 3))))))

(fn (render-terminal string) ((context context))
  "Return a plain cell frame. Terminal event decoding and ANSI output are separate."
  (let* ((root (or (context-root context) (error "No completed frame.")))
         (width (floor (box-width (element-box root))))
         (height (floor (box-height (element-box root))))
         (cells (make-array (list height width) :initial-element " ")))
    (visible-elements
     root
     (lambda (node)
       (let ((widget (element-content node))
             (box (element-box node)))
         (when (widget-p widget)
           (when (eq (widget-kind widget) :panel)
             (paint-panel cells node widget))
           (let* ((padding (element-padding node))
                  (x (floor (+ (box-x box) padding)))
                  (y (floor (+ (box-y box) padding)))
                  (w (max 0 (floor (- (box-width box) (* 2 padding)))))
                  (h (max 0 (floor (- (box-height box) (* 2 padding))))))
             (loop :for line :in (text-lines (widget-terminal-text widget) w)
                   :for row :from y :below (min height (+ y h))
                   :do (loop :with column := x
                             :for char :across line
                             :for size := (character-width char)
                             :while (<= (+ column size) (min width (+ x w)))
                             :do (when (and (>= row 0) (>= column 0)
                                            (cell-visible-p
                                             (element-clip node)
                                             (if (zerop size)
                                                 (1- column) column)
                                             row (max 1 size)))
                                   (paint-character cells row column x
                                                    char size))
                                 (incf column size))))))))
    (with-output-to-string (stream)
      (dotimes (row height)
        (dotimes (column width)
          (write-string (aref cells row column) stream))
        (terpri stream)))))

(fn run-terminal ((draw function) &key title width height (interactive t))
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
