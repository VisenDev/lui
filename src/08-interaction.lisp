(defpackage #:lui.interaction
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame)
  (:import-from #:lui
                #:key-pressed-p #:text-input-event #:visible-span #:list-index
                #:reveal-rect #:take-events #:event-targets #:reset-editor
                #:edit-value)
  (:export #:key-pressed-p #:text-input-event #:visible-span #:list-index
           #:reveal-rect #:take-events #:event-targets #:reset-editor
           #:edit-value))
(in-package #:lui.interaction)

(fn (key-pressed-p boolean)
    ((key symbol) &optional ((context context) *context*))
  "Whether this frame contains a press of the semantic KEY."
  (loop :for events :being :the :hash-values :of (context-events context)
        :thereis (some (lambda (event)
                         (and (eq (event-kind event) :key)
                              (eq (event-key event) key)))
                       events)))

(fn (take-events (vector event)) ((id object-id))
  "Return and consume a vector of a control's ordered frame events."
  (setf id (lui.frame:widget-id id))
  (prog1 (events-for id)
    (setf (gethash id (context-events *context*)) nil)))

(fn (event-targets (vector object-id)) ()
  "Return a vector of control IDs with unconsumed events in the current frame.
ID types are unrestricted and may differ between vector elements."
  (let ((ids nil))
    (maphash (lambda (id events) (when events (push id ids)))
             (context-events *context*))
    (make-array (length ids) :element-type 'object-id :initial-contents ids)))

(fn (reset-editor lui.widgets:edit-state) ((id object-id) (text string))
  "Reset owned text and editor state, placing the caret at the end of TEXT.
ID is a resolved widget ID or a unique declared key."
  (setf id (lui:widget-id id))
  (setf (gethash id (lui.frame:context-values *context*)) text)
  (let ((length (length text)))
    (setf (gethash id (context-state *context*))
          (lui.widgets:make-edit-state :cursor length :anchor length))))

(fn (edit-value string)
    ((id object-id) (text string) &optional
     ((events sequence) (take-events id)))
  "Apply editor events without declaring a widget; preserve caret and kill state."
  (setf id (lui:widget-id id))
  (let* ((state (or (gethash id (context-state *context*))
                    (reset-editor id text)))
         (next (lui.widgets:edit-text text state events)))
    (unless (equal text next) (request-frame))
    next))

(fn (text-input-event (or null event)) ((event event) (editing-p boolean))
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

(fn (visible-span (values integer integer))
    ((offset real) (viewport real) (size (real 0 *)) (header real)
     (count (integer 0 *)))
  "Return the visible half-open index range, including partially visible items."
  (values (max 0 (min (1- count) (floor (- offset header) size)))
          (min count (1+ (ceiling (- (+ offset viewport) header) size)))))

(fn (list-index (or null integer))
    ((key symbol) (index integer) (count
                                   (integer 0
                                            *)))
  "Move a bounded list selection; return NIL for an unrelated key/empty list."
  (when (plusp count)
    (case key
      (:up (max 0 (1- index)))
      (:down (min (1- count) (1+ index)))
      (:home 0) (:end (1- count)) (otherwise nil))))

(fn (reveal-rect (or null boolean))
    ((id object-id) (left real) (top real) (width real) (height real) &key
     ((leading-x real) 0) ((leading-y real) 0))
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
          (when (lui.frame:context-page-height-p *context*)
            (let* ((origin (+ (box-y viewport) top (- next-y)))
                   (current (lui.frame:context-page-top *context*))
                   (target
                     (max 0
                                (min (- origin leading-y)
                                     (max current
                                          (- (+ origin height)
                          (lui.frame:context-viewport-height
                                             *context*)))))))
              (unless (= target current)
                (setf (lui.frame:context-page-top *context*) target
                      (lui.frame:context-requested-page-top *context*)
                      target)
                (request-frame))))
          (unless (and (= x next-x) (= y next-y))
            (scroll-to id next-x next-y)
            (request-frame)
            t))))))
