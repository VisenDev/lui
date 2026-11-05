(defpackage #:lui.terminal
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame #:lui.widgets #:lui)
  (:export #:make-terminal-context #:render-terminal #:text-lines))

(in-package #:lui.terminal)

(fn (text-lines list) ((text string) width)
  "Wrap at spaces, preserving explicit newlines. Long words overflow and are clipped."
  (let ((lines nil) (start 0) (length (length text)))
    (loop
      (let*
        ((newline (position #\Newline text :start start))
          (end (or newline length))
          (limit (if width (max 1 (floor width)) (max 1 (- end start)))))
        (loop :while (> (- end start) limit) :do
          (let
            ((space
                (position #\Space text :start start :end
                  (min end (+ start limit 1)) :from-end t)))
            (unless (and space (> space start))
              (setf space
                (position #\Space text :start (+ start limit) :end
                  end)))
            (unless space (return))
            (push (subseq text start space) lines)
            (setf start (1+ space))))
        (push (subseq text start end) lines)
        (unless newline (return))
        (setf start (1+ newline))))
    (nreverse lines)))

(fn measure-widget ((widget widget) width)
  (let ((lines (text-lines (widget-terminal-text widget) width)))
    (values (loop :for line :in lines :maximize (length line))
      (length lines))))

(fn (make-terminal-context context) ()
  (make-context :measure #'measure-widget))

(fn (render-terminal string) ((context context))
  "Return a plain cell frame. Terminal event decoding and ANSI output are separate."
  (let*
    ((root (or (context-root context) (error "No completed frame.")))
      (width (floor (box-width (element-box root))))
      (height (floor (box-height (element-box root))))
      (cells
        (make-array (list height width) :element-type 'character
          :initial-element #\Space)))
    (visible-elements root
      (lambda (node)
        (let ((widget (element-content node)) (box (element-box node)))
          (when (widget-p widget)
            (let*
              ((padding (element-padding node))
                (x (floor (+ (box-x box) padding)))
                (y (floor (+ (box-y box) padding)))
                (w (max 0 (floor (- (box-width box) (* 2 padding)))))
                (h (max 0 (floor (- (box-height box) (* 2 padding))))))
              (loop :for line :in
                (text-lines (widget-terminal-text widget) w) :for row
                :from y :below (min height (+ y h)) :do
                (loop :for char :across line :for column :from x
                  :below (min width (+ x w)) :do
                  (when
                    (and (>= row 0) (>= column 0)
                      (>= column
                        (ceiling (box-x (element-clip node))))
                      (< column
                        (+ (box-x (element-clip node))
                          (box-width (element-clip node))))
                      (>= row
                        (ceiling (box-y (element-clip node))))
                      (< row
                        (+ (box-y (element-clip node))
                          (box-height (element-clip node)))))
                    (setf (aref cells row column) char)))))))))
    (with-output-to-string (stream)
      (dotimes (row height)
        (dotimes (column width)
          (write-char (aref cells row column) stream)) (terpri stream)))))

(fn run-terminal ((draw function) &key title width height (interactive t))
  (declare (ignore title))
  (let
    ((context (make-terminal-context)) (*unit* 1) (events nil)
      (width (or width 80)) (height (or height 24)))
    (loop (with-frame (context width height :events events) (funcall draw))
      (when interactive (format t "~C[H~C[2J" #\Escape #\Escape))
      (write-string (render-terminal context)) (finish-output)
      (unless interactive (return context))
      ;; Portable line-input fallback. Native terminal raw input is added separately.
      (let ((line (read-line *standard-input* nil)))
        (when (or (null line) (string= line ":quit")) (return context))
        (setf events
          (cond ((string= line ":next") (list (make-event :kind :tab)))
            ((string= line "") (list (make-event :kind :activate)))
            (t (list (make-event :kind :text :value line)))))))))

(register-backend :terminal #'run-terminal)
