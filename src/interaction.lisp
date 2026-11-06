(defpackage #:lui.interaction
  (:use #:cl #:lui.layout #:lui.frame)
  (:export #:key-pressed-p #:text-input-event #:visible-span #:list-index
           #:reveal-rect #:take-events #:event-targets #:reset-editor
           #:edit-value))
(in-package #:lui.interaction)

(defun key-pressed-p (key &optional (context *context*))
  "Whether this frame contains a press of the semantic KEY."
  (let ((pressed nil))
    (maphash (lambda (id events)
               (declare (ignore id))
               (when (some (lambda (event)
                             (and (eq (event-kind event) :key)
                                  (eq (event-key event) key)))
                           events)
                 (setf pressed t)))
             (context-events context))
    pressed))

(defun take-events (id)
  "Consume a control's ordered frame events before a later declaration."
  (prog1 (events-for id)
    (setf (gethash id (context-events *context*)) nil)))

(defun event-targets ()
  "Return control IDs with unconsumed events in the current frame."
  (let ((ids nil))
    (maphash (lambda (id events) (when events (push id ids)))
             (context-events *context*))
    ids))

(defun reset-editor (id text)
  "Start a fresh editor with its caret at the end of TEXT."
  (let ((length (length text)))
    (setf (gethash id (context-state *context*))
          (lui.widgets:make-edit-state :cursor length :anchor length))))

(defun edit-value (id text &optional (events (take-events id)))
  "Apply editor events without declaring a widget; preserve caret and kill state."
  (let* ((state (or (gethash id (context-state *context*))
                    (reset-editor id text)))
         (next (lui.widgets:edit-text text state events)))
    (unless (equal text next) (request-frame))
    next))

(defun text-input-event (event editing-p)
  "Normalize raw Readline control text during editing; reject control-only input
outside editing. Return an event or NIL; printable input remains text."
  (if (and (eq (event-kind event) :text) (stringp (event-value event)))
      (let* ((text (event-value event))
             (code (when (= (length text) 1) (char-code (char text 0)))))
        (cond
          ((and code (or (< code 32) (= code 127)))
           (when editing-p
             (let ((key (if (= code 127) :backspace
                            (lui.widgets:readline-key
                             (string (code-char (+ code 64))) :control t))))
               (when key (make-event :kind :key :key key)))))
          (t
           (let ((clean (remove-if (lambda (char)
                                     (or (< (char-code char) 32)
                                         (= (char-code char) 127)))
                                   text)))
             (when (plusp (length clean))
               (make-event :kind :text :value clean))))))
      event))

(defun visible-span (offset viewport size header count)
  "Return the visible half-open index range, including partially visible items."
  (values (max 0 (min (1- count) (floor (- offset header) size)))
          (min count (1+ (ceiling (- (+ offset viewport) header) size)))))

(defun list-index (key index count)
  "Move a bounded list selection; return NIL for an unrelated key/empty list."
  (when (plusp count)
    (case key
      (:up (max 0 (1- index)))
      (:down (min (1- count) (1+ index)))
      (:home 0) (:end (1- count)))))

(defun reveal-rect (id left top width height &key (leading-x 0) (leading-y 0))
  "Scroll a content rectangle into view, reserving optional leading header space."
  (let ((viewport (previous-box id)))
    (when viewport
      (multiple-value-bind (x y) (scroll-position id)
        (let ((next-x (max 0 (min (- left leading-x)
                                  (max x (- (+ left width)
                                            (box-width viewport))))))
              (next-y (max 0 (min (- top leading-y)
                                  (max y (- (+ top height)
                                            (box-height viewport)))))))
          (when (lui.frame::context-page-height-p *context*)
            (let* ((origin (+ (box-y viewport) top (- next-y)))
                   (current (lui.frame::context-page-top *context*))
                   (target (max 0 (min (- origin leading-y)
                                       (max current (- (+ origin height)
                                                       (lui.frame::context-viewport-height *context*)))))))
              (unless (= target current)
                (setf (lui.frame::context-page-top *context*) target
                      (lui.frame::context-requested-page-top *context*) target)
                (request-frame))))
          (unless (and (= x next-x) (= y next-y))
            (scroll-to id next-x next-y)
            (request-frame)
            t))))))
