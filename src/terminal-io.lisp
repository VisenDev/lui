(defpackage #:lui.terminal.io
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.widgets
        #:lui.terminal))

(in-package #:lui.terminal.io)

;; Terminal state, terminal capabilities and input decoding belong to uncursed.
(defstruct input
  (pending "" :type string)
  (escape-time nil)
  (events nil :type list)
  (quit-p nil :type boolean))

(fn show-cursor ()
  ;; Uncursed has no visibility-only API; its shape API and terminfo
  ;; cnorm/cvvis also change blinking.
  ;; Visibility alone preserves the user's inherited shape and blink mode.
  (format *terminal-io* "~C[?25h" #\Escape))

(fn terminal-size ()
  (let ((size (uncursed:terminal-dimensions)))
    (values (max 1 (cdr size)) (max 1 (car size)))))

(fn focused-node ((context context))
  (let ((found nil))
    (when (context-focus context)
      (walk-elements (context-root context)
                     (lambda (node)
                       (when (equal (element-id node) (context-focus context))
                         (setf found node)))))
    found))

(fn input-focus ((input input) (context context))
  ;; A single read can contain several tabs and a space. Resolve the focus those
  ;; events will establish, without mutating the previous completed frame.
  (let ((nodes nil)
        (focus (context-focus context)))
    (walk-elements (context-root context)
                   (lambda (node)
                     (when (element-interactive-p node) (push node nodes))))
    (setf nodes (nreverse nodes))
    (dolist (event (reverse (input-events input)))
      (case (event-kind event)
        (:tab
         (let* ((focusable (remove-if-not #'element-keyboard-focus-p nodes))
                (order (if (eq (event-key event) :backward)
                           (reverse focusable) focusable))
                (next (or (second (member focus order :key #'element-id
                                                     :test #'equal))
                          (first order))))
           (setf focus (and next (element-id next)))))
        (:press
         (dolist (node nodes)
           (let ((clip (element-clip node)))
             (when (and (element-pointer-focus-p node)
                        (<= (box-x clip) (event-x event))
                        (< (event-x event) (+ (box-x clip) (box-width clip)))
                        (<= (box-y clip) (event-y event))
                        (< (event-y event)
                           (+ (box-y clip) (box-height clip))))
               (setf focus (element-id node))))))))
    (find focus nodes :key #'element-id :test #'equal)))

(fn editing-input-p ((input input) (context context))
  (let* ((node (input-focus input context))
         (widget (and node (element-content node))))
    (and (widget-p widget) (eq (widget-kind widget) :text-field)
         (not (widget-disabled-p widget)))))

(fn key-event ((input input) (key symbol))
  (push (make-event :kind :key :key key) (input-events input)))

(fn slider-change ((input input) (context context) (event event))
  (let ((capture (context-active context)))
    (dolist (pending (reverse (rest (input-events input))))
      (case (event-kind pending)
        (:press
         (setf capture (or (event-id pending)
                           (lui.frame::hit context (event-x pending)
                                           (event-y pending)))))
        ((:release :cancel) (setf capture nil))
        (:move
         (when (and (event-buttons pending)
                    (not (logbitp 0 (event-buttons pending))))
           (setf capture nil)))))
    (let* ((press (eq (event-kind event) :press))
           (id (if press (lui.frame::hit context (event-x event)
                                               (event-y event)) capture))
           (target (gethash id (lui.frame::context-ids context)))
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
              (lui.terminal::slider-line widget width)
            (declare (ignore line))
            (push (make-event
                   :kind :change :id id
                   :value (+ (widget-minimum widget)
                             (* (- (widget-maximum widget)
                                   (widget-minimum widget))
                                (min 1 (max 0
                                  (/ (- (floor (event-x event)) left offset)
                                     (max 1 (1- length))))))))
                  (input-events input))))))))

(fn mouse-event ((input input) (data uncursed:mouse-data) &optional context)
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
      (slider-change input context (first (input-events input))))))

(fn decode-event ((input input) event (context context))
  (let* ((kind (uncursed:event-kind event))
         (control (uncursed:event-controlp event))
         (alt (uncursed:event-altp event))
         (shift (uncursed:event-shiftp event))
         (key (case kind (:left-arrow :left) (:right-arrow :right)
                         (:up-arrow :up) (:down-arrow :down)
                         (otherwise (when (keywordp kind) kind))))
         (name (if (characterp kind) (string kind)
                   (and key (symbol-name key))))
         (editing (editing-input-p input context))
         (command (and name editing
                       (readline-key name :control control :alt alt
                                          :shift shift))))
    (cond
      ((uncursed:mouse-event-p event) (mouse-event input kind context))
      ((and control (characterp kind) (find kind "cq" :test #'char-equal))
       (setf (input-quit-p input) t))
      ((and (characterp kind) (char= kind #\i) control)
       (push (make-event :kind :tab :key (when shift :backward))
             (input-events input)))
      ((eql kind #\Tab)
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
                            (case key (:left :shift-left) (:right :shift-right)
                                      (:home :shift-home) (:end :shift-end)
                                      (otherwise key)) key)))
      ((and (characterp kind) (not control) (not alt))
       (let* ((node (input-focus input context))
              (widget (and node (element-content node))))
         (push (if (and (eql kind #\Space) (widget-p widget)
                        (member (widget-kind widget)
                                '(:button :checkbox :radio :tab :list-item :cell)))
                   (make-event :kind :activate)
                   (make-event :kind :text :value (string kind)))
               (input-events input)))))))

(fn input-sequence-length ((text string))
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

(fn read-input ((input input) (context context) (timeout real))
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
              :do (let* ((*standard-input*
                           (make-string-input-stream
                             (subseq (input-pending input) 0 size)))
                         (event (uncursed-sys:read-event)))
                    (decode-event input event context)
                    (setf (input-pending input)
                          (subseq (input-pending input) size)
                          (input-escape-time input) nil)))
        (when (string= (input-pending input) (string #\Escape))
          (let ((now (get-internal-real-time)))
            (if (and (input-escape-time input)
                     (>= (- now (input-escape-time input))
                         (* 0.1 internal-time-units-per-second)))
                (progn (key-event input :escape)
                       (setf (input-pending input) ""
                             (input-escape-time input) nil))
                (unless (input-escape-time input)
                  (setf (input-escape-time input) now)))))
        (when (or (input-events input) (input-quit-p input)
                  (>= (get-internal-real-time) end))
          (return))
        (sleep 0.005)))))

(fn (slice-cells string) ((text string) (start integer) (width integer))
  (with-output-to-string (stream)
    (loop :with column := 0
          :for character :across text
          :for size := (character-width character)
          :while (<= (+ column size) (+ start width))
          :do (cond ((>= column start) (write-char character stream))
                    ((> (+ column size) start) (write-char #\Space stream)))
              (incf column size))))

(fn draw-focus ((context context))
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
                         (cell-edge (+ (box-x clip) (box-width clip)))
                         (cell-edge (+ (box-x box) (box-width box)
                                       (- padding)))))
             (width (max 0 (- right x)))
             (state (gethash (element-id node) (context-state context)))
             (field-p (eq (widget-kind widget) :text-field))
             (cursor (if (and field-p state)
                         (1+ (text-width
                              (subseq (widget-value widget) 0
                                      (min (length (widget-value widget))
                                           (edit-state-cursor state)))))
                         0))
             (offset (max 0 (- cursor (max 1 (1- width)))))
             (text (if (eq (widget-kind widget) :slider)
                       (lui.terminal::slider-line
                        widget (max 0 (- (cell-edge
                                          (+ (box-x box) (box-width box)
                                             (- padding)))
                                         origin)))
                       (widget-terminal-text widget))))
        (when (and (plusp width) (<= 0 y) (< y (context-height context))
                   (<= (cell-edge (box-y clip)) y)
                   (< y (cell-edge (+ (box-y clip) (box-height clip)))))
          (uncursed-sys:set-cursor-position y x)
          (uncursed-sys:set-style (uncursed:make-style :reversep t))
          (write-string (slice-cells text (+ offset (- x origin)) width)
                        *terminal-io*)
          (uncursed-sys:set-style uncursed:*default-style*)
          (when field-p
            (let ((column (+ origin cursor (- offset))))
              (when (and (<= x column) (< column right))
                (uncursed-sys:set-cursor-position y column)
                (show-cursor)))))))))

(fn display-frame ((context context))
  (uncursed:set-cursor-shape :invisible)
  (uncursed-sys:set-cursor-position 0 0)
  (let* ((frame (render-terminal context :ansi t)) (start 0) (row 0))
    (loop :for end := (position #\Newline frame :start start)
          :while end
          :do (uncursed-sys:set-cursor-position row 0)
              (write-string frame *terminal-io* :start start :end end)
              (setf start (1+ end))
              (incf row)))
  (draw-focus context)
  (finish-output *terminal-io*))

(fn wait-frame ((input input) (context context) width height)
  (loop
    (let ((remaining (lui.frame::frame-wait context)))
      (read-input input context (max 0.001 (min 0.1 remaining)))
      (when (or (zerop remaining) (input-events input) (input-quit-p input))
        (return)))
    (multiple-value-bind (columns rows) (terminal-size)
      (when (or (/= (or width columns) (context-width context))
                (/= (or height rows) (context-height context)))
        (return)))))

(fn run-uncursed-terminal
    ((draw function) &key title width height (interactive t))
  (if (or (not interactive)
          (not (interactive-stream-p *standard-input*))
          (not (interactive-stream-p *standard-output*))
          #+unix (let ((term (uiop:getenv "TERM")))
                   (or (null term) (zerop (length term))
                       (string-equal term "dumb"))))
      (run-terminal draw :title title :width width :height height
                         :interactive interactive)
      (let ((context (make-terminal-context)) (*unit* 1) (input (make-input))
            (saved nil))
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
                 (display-frame context)
                 (wait-frame input context width height)
                 (when (input-quit-p input) (return context))
                 (lui.frame::limit-frame-rate context)))
          (when saved
            (unwind-protect
                 (progn
                   (uncursed-sys:set-style uncursed:*default-style*)
                   (uncursed:disable-mouse)
                   (show-cursor)
                   (uncursed-sys:disable-alternate-screen)
                   (finish-output *terminal-io*))
              (uncursed-sys:restore-terminal saved
                                             #+unix uncursed-sys:+stdin+)))))))

(register-backend :terminal #'run-uncursed-terminal)
