(defpackage #:lui.terminal.io
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.widgets
        #:lui.terminal))

(in-package #:lui.terminal.io)

;; The portable system never loads this file or CFFI. Only this optional backend
;; accesses the terminal, through libc and the standard input/output descriptors.
(cffi:defcstruct pollfd
  (fd :int)
  (events :short)
  (revents :short))

(defstruct input
  (bytes nil :type list)
  (events nil :type list)
  (quit-p nil :type boolean))

(fn control ((stream stream) (command string) &rest arguments)
  (write-char #\Escape stream)
  (apply #'format stream command arguments))

(fn write-terminal ((text string))
  (cffi:with-foreign-string ((buffer allocated) text :encoding :utf-8)
    (let ((size (1- allocated)))
      (loop :with offset := 0
            :while (< offset size)
            :for written := (cffi:foreign-funcall
                             "write" :int 1
                             :pointer (cffi:inc-pointer buffer offset)
                             :size (- size offset) :long)
            :do (when (<= written 0)
                  (error "Terminal output failed."))
                (incf offset written)))))

(fn terminal-size ()
  (cffi:with-foreign-object (size :unsigned-short 4)
    (if (zerop (cffi:foreign-funcall
                "ioctl" :int 1 :unsigned-long
                #+linux #x5413
                #+(or darwin freebsd openbsd netbsd) #x40087468
                #-(or linux darwin freebsd openbsd netbsd) 0
                :pointer size :int))
        (values (max 1 (cffi:mem-aref size :unsigned-short 1))
                (max 1 (cffi:mem-aref size :unsigned-short 0)))
        (values 80 24))))

(fn read-input ((input input) &optional ((timeout integer) 100))
  (cffi:with-foreign-object (descriptor '(:struct pollfd))
    (setf (cffi:foreign-slot-value descriptor '(:struct pollfd) 'fd) 0
          (cffi:foreign-slot-value descriptor '(:struct pollfd) 'events) 1
          (cffi:foreign-slot-value descriptor '(:struct pollfd) 'revents) 0)
    (let ((ready (cffi:foreign-funcall "poll" :pointer descriptor
                                     :unsigned-long 1 :int timeout :int)))
      (when (plusp ready)
        (cffi:with-foreign-object (buffer :unsigned-char 4096)
          (let ((count (cffi:foreign-funcall "read" :int 0 :pointer buffer
                                           :size 4096 :long)))
            (cond ((plusp count)
                   (setf (input-bytes input)
                         (nconc (input-bytes input)
                                (loop :for index :below count
                                      :collect (cffi:mem-aref
                                                buffer :unsigned-char
                                                index)))))
                  ((zerop count) (setf (input-quit-p input) t)))))))))

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
         (let* ((order (if (eq (event-key event) :backward)
                           (reverse nodes) nodes))
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

(fn mouse-event ((input input) (sequence string))
  (let* ((first (position #\; sequence))
         (second (and first (position #\; sequence :start (1+ first))))
         (end (1- (length sequence)))
         (button (and first (parse-integer sequence :end first
                                                   :junk-allowed t)))
         (x (and second (parse-integer sequence :start (1+ first)
                                               :end second :junk-allowed t)))
         (y (and second (parse-integer sequence :start (1+ second)
                                               :end end :junk-allowed t))))
    (when (and button x y (plusp x) (plusp y))
      (push (make-event
             :kind (cond ((logbitp 6 button) :scroll)
                         ((char= (char sequence end) #\m) :release)
                         ((logbitp 5 button) :move)
                         (t :press))
             :x (1- x) :y (1- y)
             :value (if (logbitp 0 button) 3 -3))
            (input-events input)))))

(fn escape-event ((input input) (sequence string))
  (cond ((string= sequence "Z")
         (push (make-event :kind :tab :key :backward) (input-events input)))
        ((and (plusp (length sequence))
              (char= (char sequence 0) #\<))
         (mouse-event input (subseq sequence 1)))
        (t
         (let ((key (cdr (assoc sequence
                                '(("A" . :up) ("B" . :down)
                                  ("C" . :right) ("D" . :left)
                                  ("H" . :home) ("F" . :end)
                                  ("1~" . :home) ("4~" . :end)
                                  ("7~" . :home) ("8~" . :end)
                                  ("3~" . :delete)
                                  ("1;2C" . :shift-right)
                                  ("1;2D" . :shift-left)
                                  ("1;5C" . :word-right)
                                  ("1;5D" . :word-left)
                                  ("1;6C" . :shift-word-right)
                                  ("1;6D" . :shift-word-left)
                                  ("97;6u" . :select-all)
                                  ("65;6u" . :select-all))
                                :test #'string=))))
           (when key (key-event input key))))))

(fn decode-input ((input input) (context context))
  ;; Incomplete CSI sequences and UTF-8 code points stay buffered between polls.
  (when (intersection (input-bytes input) '(3 17))
    (setf (input-quit-p input) t))
  (loop :while (input-bytes input)
        :for bytes := (input-bytes input)
        :for byte := (first bytes)
        :do (cond
              ((= byte 27)
               (unless (rest bytes) (return))
               (if (member (second bytes) '(79 91))
                   (let ((end (position-if (lambda (value) (<= 64 value 126))
                                           bytes :start 2)))
                     (unless end (return))
                     (escape-event input
                                   (coerce (mapcar #'code-char
                                                   (subseq bytes 2 (1+ end)))
                                           'string))
                     (setf (input-bytes input) (nthcdr (1+ end) bytes)))
                   (let ((key (and (editing-input-p input context)
                                   (readline-key
                                    (if (= (second bytes) 127) "Backspace"
                                        (string (code-char (second bytes))))
                                    :alt t))))
                     (if key
                         (progn (key-event input key)
                                (setf (input-bytes input) (cddr bytes)))
                         (setf (input-bytes input) (rest bytes))))))
              ((< byte 32)
               (pop (input-bytes input))
               (case byte
                 ((3 17) (setf (input-quit-p input) t))
                 (9 (push (make-event :kind :tab) (input-events input)))
                 ((10 13)
                  (push (make-event :kind :activate) (input-events input)))
                 (otherwise
                  (when (editing-input-p input context)
                    (let ((key (readline-key
                                (string (code-char (+ byte 64))) :control t)))
                      (when key (key-event input key)))))))
              ((= byte 127)
               (pop (input-bytes input))
               (key-event input :backspace))
              ((= byte 32)
               (pop (input-bytes input))
               (let* ((node (input-focus input context))
                      (widget (and node (element-content node))))
                 (push (if (and (widget-p widget)
                                (member (widget-kind widget)
                                        '(:button :checkbox :tab)))
                           (make-event :kind :activate)
                           (make-event :kind :text :value " "))
                       (input-events input))))
              (t
               (let* ((size (cond ((< byte 128) 1) ((<= 194 byte 223) 2)
                                  ((<= 224 byte 239) 3)
                                  ((<= 240 byte 244) 4) (t 1)))
                      (code (logand byte (case size
                                          (1 127) (2 31) (3 15) (4 7))))
                      (valid (or (< byte 128) (> size 1))))
                 (when (< (length bytes) size)
                   (if (every (lambda (next) (<= 128 next 191)) (rest bytes))
                       (return)
                       (setf size 1 valid nil)))
                 (loop :for next :in (subseq bytes 1 size)
                       :do (unless (<= 128 next 191) (setf valid nil))
                           (setf code (+ (ash code 6) (logand next 63))))
                 (setf valid (and valid
                                  (>= code (case size
                                             (1 0) (2 128)
                                             (3 2048) (4 65536)))
                                  (<= code #x10ffff)
                                  (not (<= #xd800 code #xdfff))))
                 (setf (input-bytes input) (nthcdr (if valid size 1) bytes))
                 (when valid
                   (let ((character (code-char code)))
                     (when character
                       (push (make-event :kind :text
                                         :value (string character))
                             (input-events input))))))))))

(fn (slice-cells string) ((text string) (start integer) (width integer))
  (with-output-to-string (stream)
    (loop :with column := 0
          :for character :across text
          :for size := (character-width character)
          :while (<= (+ column size) (+ start width))
          :do (cond ((>= column start) (write-char character stream))
                    ((> (+ column size) start) (write-char #\Space stream)))
              (incf column size))))

(fn draw-focus ((stream stream) (context context))
  (let* ((node (focused-node context))
         (widget (and node (element-content node))))
    (when (and (widget-p widget)
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
             (text (widget-terminal-text widget)))
        (when (and (plusp width) (<= 0 y) (< y (context-height context))
                   (<= (cell-edge (box-y clip)) y)
                   (< y (cell-edge (+ (box-y clip) (box-height clip)))))
          (control stream "[~D;~DH" (1+ y) (1+ x))
          (control stream "[7m")
          (write-string (slice-cells text (+ offset (- x origin)) width)
                        stream)
          (control stream "[0m")
          (when field-p
            (let ((column (+ origin cursor (- offset))))
              (when (and (<= x column) (< column right))
                (control stream "[~D;~DH" (1+ y) (1+ column))
                (control stream "[?25h")))))))))

(fn display-frame ((context context))
  (write-terminal
   (with-output-to-string (stream)
     (control stream "[?25l")
     (control stream "[H")
     ;; Explicit positioning avoids ONLCR changes and last-column autowrap.
     (let* ((frame (render-terminal context :ansi t))
            (start 0)
            (row 1))
       (loop :for end := (position #\Newline frame :start start)
             :while end
             :do (control stream "[~D;1H" row)
                 (write-string frame stream :start start :end end)
                 (setf start (1+ end))
                 (incf row)))
     (draw-focus stream context))))

(fn wait-frame ((input input) (context context) width height)
  ;; Poll for resize without repainting idle frames; timers shorten the wait.
  (loop
    (let* ((deadline (context-next-frame context))
           (remaining (when deadline
                        (- deadline (/ (get-internal-real-time)
                                       internal-time-units-per-second)))))
      (when (and remaining (<= remaining 0)) (return))
      (read-input input (if remaining (min 100 (ceiling (* remaining 1000)))
                            100)))
    (decode-input input context)
    (when (or (input-events input) (input-quit-p input)) (return))
    (multiple-value-bind (columns rows) (terminal-size)
      (when (or (/= (or width columns) (context-width context))
                (/= (or height rows) (context-height context)))
        (return)))))

(fn run-raw-terminal
    ((draw function) &key title width height (interactive t))
  (cond
    ((or (not interactive)
         (zerop (cffi:foreign-funcall "isatty" :int 0 :int))
         (zerop (cffi:foreign-funcall "isatty" :int 1 :int)))
     (run-terminal draw :title title :width width :height height
                       :interactive interactive))
    (t
     ;; Opaque aligned storage accommodates libc's termios across POSIX targets.
     ;; No field offsets, Lisp stream internals or implementation FD APIs occur.
     (cffi:with-foreign-objects ((saved :unsigned-long 64)
                                (raw :unsigned-long 64))
       (unless (zerop (cffi:foreign-funcall "tcgetattr" :int 0
                                          :pointer saved :int))
         (error "Cannot read terminal attributes."))
       (unless (zerop (cffi:foreign-funcall "tcgetattr" :int 0
                                          :pointer raw :int))
         (error "Cannot read terminal attributes."))
       (cffi:foreign-funcall "cfmakeraw" :pointer raw :void)
       (let ((context (make-terminal-context))
             (*unit* 1)
             (input (make-input)))
         (unwind-protect
              (progn
                (unless (zerop (cffi:foreign-funcall "tcsetattr" :int 0 :int 0
                                                   :pointer raw :int))
                  (error "Cannot enter raw terminal mode."))
                (write-terminal
                 (with-output-to-string (stream)
                   (control stream "[?1049h")
                   (control stream "[?7l")
                   (control stream "[?1002h")
                   (control stream "[?1006h")
                   (control stream "[2J")))
                (loop
                  (multiple-value-bind (columns rows) (terminal-size)
                    (with-frame (context (or width columns) (or height rows)
                                         :events
                                         (nreverse (input-events input)))
                      (funcall draw)))
                  (setf (input-events input) nil)
                  (display-frame context)
                  (wait-frame input context width height)
                  (when (input-quit-p input) (return context))))
           ;; Restore termios even if output fails, or DRAW signals an error.
           (unwind-protect
                (write-terminal
                 (with-output-to-string (stream)
                   (control stream "[0m")
                   (control stream "[?1006l")
                   (control stream "[?1002l")
                   (control stream "[?7h")
                   (control stream "[?25h")
                   (control stream "[?1049l")))
             (cffi:foreign-funcall "tcsetattr" :int 0 :int 0
                                             :pointer saved :int))))))))

;; Other platforms retain the portable line-input backend.
#+(or linux darwin freebsd openbsd netbsd)
(register-backend :terminal #'run-raw-terminal)
