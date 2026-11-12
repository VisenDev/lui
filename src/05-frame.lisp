(defpackage #:lui.frame
  (:use #:cl #:lui.fn #:lui.layout)
  (:export #:*min-fps* #:*max-fps* #:contains-p #:context-after-layout
           #:context-ids #:context-page-height-p #:context-page-top
           #:context-pointer-press #:context-popups
           #:context-requested-page-top #:context-viewport-height
           #:frame-wait #:hit #:limit-frame-rate #:memoized
           #:pointer-cancel-p
           #:context #:make-context #:context-root #:context-focus
           #:context-focus-input #:context-active #:context-measure
           #:*context* #:*parent*
    #:with-frame #:with-key #:widget-key #:widget-id #:focus-widget
    #:call-with-frame #:call-with-key #:call-site-id #:context-values
           #:row #:column #:event #:event-kind #:event-x #:event-y #:event-id
           #:event-value #:event-key #:event-button #:event-clicks
           #:event-dragging-p #:event-buttons #:event-scroll-mode
           #:context-events #:events-for
           #:previous-box
           #:context-state #:context-width #:context-height #:emit
           #:activated-p #:activated-ids #:record-activation
           #:make-event #:begin-frame #:end-frame #:context-hover #:hovered-p
           #:context-previous-root #:context-activated
           #:context-focus-visible-p #:frame-time #:request-frame
           #:context-next-frame #:parent-scroll-position
           #:scroll-position #:scroll-to
           #:pending-input-context #:context-overlay #:context-overlay-state
           #:context-tabs-handled-p #:context-text-mode-p
           #:context-copy #:context-input-handler #:context-selection))

(in-package #:lui.frame)

(defstruct event
  "Backend-neutral input: a kind, target ID, optional key/value, and coordinates.
BUTTONS is NIL when unknown; otherwise bit 0 means primary and bit 1 secondary,
with zero meaning no buttons held. :CANCEL ends capture without activation.
DRAGGING-P is resolved from capture and the supplied physical button state."
  (kind :move :type
        (member :move :press :release :tab :activate :change
                :key :text :scroll :cancel))
  (button :primary :type (member :primary :secondary))
  (clicks 1 :type integer)
  (dragging-p nil :type boolean)
  ;; NIL means unknown; otherwise bit0=primary, bit1=secondary, 0=unpressed.
  (buttons nil :type (or null integer))
  ;; Precise OS inertia uses :IMMEDIATE; :AUTO keeps plain text contexts direct.
  (scroll-mode :auto :type (member :auto :smooth :immediate))
  (id nil :type object-id)
  value
  key
  (x 0 :type real)
  (y 0 :type real))

(defstruct scroll-motion
  ;; IDs intentionally accept mixed types, including application-defined keys.
  (path #() :type (vector object-id))
  (remaining 0 :type real)
  (time 0 :type real)
  (last-input 0 :type real)
  (level 1 :type integer))

(defvar *min-fps* 1)
(defvar *max-fps* 240)

(defstruct memo-entry (key nil :type list) (value nil :type t))

(defstruct frame-statistics
  (samples (make-array 30 :element-type 'real :initial-element 0)
           :type (vector real))
  (index 0 :type integer)
  (count 0 :type integer)
  (total-ms 0 :type real)
  (fps 0 :type real)
  (frames 0 :type integer)
  (start nil :type (or null real)))

(defstruct context
  "Per-window frame state: completed tree, focus, events, editing, and scrolling.
The backend supplies measurement, clipboard, and optional input callbacks."
  (root nil :type (or null element))
  (text-mode-p nil :type boolean)
  popups
  pointer-press
  overlay-state
  (overlay nil :type (or null function))
  (after-layout nil :type list)
  (tabs-handled-p nil :type boolean)
  (previous-root nil :type (or null element))
  (width 0 :type real)
  (height 0 :type real)
  (viewport-height 0 :type real)
  page-height-p (page-top 0 :type real) requested-page-top
  (copy nil :type (or null function))
  (input-handler nil :type (or null function))
  selection
  focus-input
  last-click
  (min-fps *min-fps* :type real)
  (max-fps *max-fps* :type real)
  (statistics (make-frame-statistics) :type frame-statistics)
  (time 0 :type real)
  (next-frame nil :type (or null real))
  (focus nil :type object-id)
  (focus-visible-p nil :type boolean)
  (hover nil :type object-id)
  (active nil :type object-id)
  (values (make-hash-table :test 'equal) :type hash-table)
  (state (make-hash-table :test 'equal) :type hash-table)
  (regions (make-hash-table :test 'equal) :type hash-table)
  (events (make-hash-table :test 'equal) :type hash-table)
  (scroll (make-hash-table :test 'equal) :type hash-table)
  (scroll-motion nil :type (or null scroll-motion))
  (activation-order nil :type list)
  (activated (make-hash-table :test 'equal) :type hash-table)
  (ids (make-hash-table :test 'equal) :type hash-table)
  (building-p nil :type boolean)
  (memo #() :type (vector memo-entry))
  (pending-memo #() :type (vector memo-entry))
  ;; Supplied by the output backend: (widget available-width) -> width, height.
  (measure nil :type (or null function)))

(defvar *context*)
(setf (documentation '*context* 'variable)
      "Dynamically bound context for the drawing function currently building a frame.")

(defvar *parent*)
(setf (documentation '*parent* 'variable)
      "Dynamically bound layout parent receiving declarations in the current scope.")

(defvar *key-scope* nil "Instance keys enclosing the current declaration.")

(fn (call-with-key (values &rest t)) ((key object-id) (draw function))
  "Call DRAW with KEY added to the identity scope; restore the scope on exit."
  (let ((*key-scope* (cons key *key-scope*))) (funcall draw)))

(defmacro with-key (key &body body)
  "Scope widget identity to KEY, evaluated once. Use stable item keys in loops."
  `(call-with-key ,key (lambda () ,@body)))

(fn (resolved-widget-id-p boolean) ((id object-id))
  "Recognize opaque call-site IDs and internal child IDs derived from them."
  (and (consp id)
    (or (eq (car id) :lui-widget-id)
      (resolved-widget-id-p (car id)))))

(fn (call-site-id list) ((site symbol) (options list))
  "Combine identity components, rejecting repeated declarations before state changes."
  (let* ((key (getf options :id site))
         (id (list :lui-widget-id site *key-scope* key)))
    (when (gethash id (context-ids *context*))
      (error 'lui.conditions:configuration-error
             :operation :declare-widget :setting :id :value key
             :format-control
             (if (eq key site)
                 "This control call site ran more than once in a frame. Supply a distinct (lui:opt :id key) for each instance, or wrap repeated groups in (lui:with-key key ...)."
                 "Repeated control key ~S at the same call site and key scope. Use distinct :id keys or WITH-KEY scopes for each instance.")
             :format-arguments (unless (eq key site) (list key))))
    id))

(fn (widget-key object-id) ((id object-id))
  "Return the declared key of an opaque widget ID, including derived child keys."
  (cond ((and (consp id) (eq (car id) :lui-widget-id)) (fourth id))
    ((resolved-widget-id-p id) (mapcar #'widget-key id))
    (t id)))

(fn (id-scope list) ((id object-id))
  "Return the enclosing key scope of a widget or internal child ID."
  (cond ((and (consp id) (eq (car id) :lui-widget-id)) (third id))
    ((resolved-widget-id-p id) (id-scope (car id)))
    (t nil)))

(fn (lookup-widget-id object-id) ((key object-id) (table hash-table))
  "Find KEY in TABLE within this scope; signal an error for ambiguous keys."
  (let ((found nil))
    (maphash
      (lambda (id value)
        (declare (ignore value))
        (when (and (equal key (widget-key id))
                (equal *key-scope* (id-scope id)))
          (when (and found (not (equal found id)))
            (error 'lui.conditions:configuration-error
              :operation :widget-id :setting :id :value key
              :format-control "Ambiguous widget key ~S; use a resolved ID."
              :format-arguments (list key)))
          (setf found id)))
      table)
    found))

(fn (widget-id object-id)
    ((key object-id) &optional ((context context) *context*))
  "Resolve KEY in the current key scope to a widget ID, or return KEY if absent.
Opaque IDs pass through unchanged. A key shared by call sites is ambiguous;
use the third value returned by a widget instead. IDs are local to CONTEXT."
  (if (or (resolved-widget-id-p key) (gethash key (context-ids context))) key
    (or (lookup-widget-id key (context-ids context))
      (lookup-widget-id key (context-regions context)) key)))

(fn (focus-widget (values)) ((id object-id))
  "Request focus for a resolved ID or unique key, including a newly declared widget."
  (setf (context-focus *context*) (widget-id id)
    (context-focus-visible-p *context*) t)
  (values))

(fn (resolve-frame-identities (values)) ((context context))
  "Resolve programmatic focus, hover, and capture keys against declared identities."
  (setf (context-focus context) (and (context-focus context)
                                  (widget-id (context-focus context)
                                    context))
    (context-hover context) (and (context-hover context)
                              (widget-id (context-hover context)
                                context))
    (context-active context) (and (context-active context)
                               (widget-id (context-active context)
                                 context)))
  (values))

(fn (prune-widget-values (values)) ((context context))
  "Release owned values for widgets absent from the completed frame."
  (dolist (table (list (context-values context) (context-state context)))
    (maphash (lambda (id value)
               (declare (ignore value))
               (unless (gethash id (context-ids context)) (remhash id table)))
      table))
  (values))

(fn (memoized t) ((key list) (compute function))
  "Reuse a frame-local value for KEY, computing it with FUNCTION on a cache miss."
  ;; Compare call slots, not hashes. Reordering only causes cache misses.
  ;; Keys snapshot top-level strings; compound IDs follow the stable-ID contract.
  (if (and (boundp '*context*) (context-building-p *context*))
      (let* ((pending (context-pending-memo *context*))
             (previous (context-memo *context*)) (index (length pending))
             (old (when (< index (length previous)) (aref previous index)))
             (entry (if (and old (equal key (memo-entry-key old))) old
                        (make-memo-entry
                         :key (mapcar (lambda (v)
                                        (if (stringp v) (copy-seq v) v)) key)
                         :value (funcall compute)))))
        (vector-push-extend entry pending)
        (memo-entry-value entry))
      (funcall compute)))

(fn (frame-time real) ()
  "Monotonic seconds sampled once for the current frame."
  (context-time *context*))

(fn (layout-clock real) ()
  "High-resolution elapsed-time clock in milliseconds."
  #+jscl (#j:performance:now)
  #-jscl (* 1000 (/ (get-internal-real-time)
                    internal-time-units-per-second)))

(fn (record-frame-statistics (values))
    ((stats frame-statistics) (ms real) (now real))
  "Average the last 30 layout solves; sample actual cadence every half second."
  (let ((samples (frame-statistics-samples stats))
        (index (frame-statistics-index stats)))
    (incf (frame-statistics-total-ms stats) (- ms (aref samples index)))
    (setf (aref samples index) ms
          (frame-statistics-index stats) (mod (1+ index) (length samples))
          (frame-statistics-count stats)
          (min (length samples) (1+ (frame-statistics-count stats)))))
  (if (null (frame-statistics-start stats))
      (setf (frame-statistics-start stats) now)
      (let ((elapsed (- now (frame-statistics-start stats))))
        (incf (frame-statistics-frames stats))
        (when (>= elapsed 0.5f0)
          (setf (frame-statistics-fps stats)
                (/ (frame-statistics-frames stats) elapsed)
                (frame-statistics-frames stats) 0
                (frame-statistics-start stats) now))))
  (values))

(fn (frame-rate-label string) ()
  "Report actual FPS and mean layout processing time, excluding painting."
  (let* ((stats (context-statistics *context*))
         (count (frame-statistics-count stats)))
    (if (zerop count)
        "FPS: measuring… · Layout: measuring…"
        (format nil "~,1F FPS · ~,1F ms/frame (layout)"
                (frame-statistics-fps stats)
                (/ (frame-statistics-total-ms stats) count)))))

(fn (frame-wait real)
    ((context context) &optional ((urgent (or boolean list)) nil)
     ((now real) (/ (get-internal-real-time) internal-time-units-per-second)))
  "Return seconds until the next allowed frame, honoring idle and active limits."
  (let* ((start (context-time context))
         (first (+ start (/ 1 (context-max-fps context))))
         (idle (+ start (/ 1 (context-min-fps context))))
         (due (min idle (or (context-next-frame context) idle))))
    (max 0 (- (if urgent first (max first due)) now))))

#-jscl
(fn (limit-frame-rate (values)) ((context context))
  (let ((remaining (frame-wait context t)))
    (when (plusp remaining) (sleep remaining)))
  (values))

(fn (request-frame real) (&optional ((delay real) 0))
  "Request another frame after DELAY seconds; earliest request wins."
  (assert (>= delay 0))
  ;; Some implementations return epoch-sized clocks. Single-float addition
  ;; would discard sub-minute delays there, so compute deadlines in doubles.
  (let ((deadline #+jscl (+ (frame-time) delay)
                  #-jscl (+ (coerce (frame-time) 'double-float)
                            (coerce delay 'double-float))))
    (setf (context-next-frame *context*)
          (if (context-next-frame *context*)
              (min deadline (context-next-frame *context*))
              deadline))))

(fn (contains-p boolean) ((bounds box) (x real) (y real))
  "Test whether X/Y lies inside BOUNDS, excluding its right and bottom edges."
  (and (<= (box-x bounds) x) (< x (box-right bounds))
       (<= (box-y bounds) y) (< y (box-bottom bounds))))

(fn (hit object-id) ((context context) (x real) (y real))
  "Find the deepest interactive element whose solved clip contains X/Y."
  (let ((found nil))
    (when (and (context-root context) (<= 0 x) (< x (context-width context))
               (<= 0 y) (< y (context-height context)))
      (walk-elements (context-root context)
                     (lambda (node)
                       (when (and (element-interactive-p node)
                                  (contains-p (element-clip node) x y))
                         (setf found (element-id node))))))
    found))

(fn (focus-next object-id)
    ((context context) &optional ((backward boolean) nil))
  "Advance keyboard focus through eligible elements in declaration order."
  (let ((ids nil))
    (when (context-root context)
      (walk-elements (context-root context)
                     (lambda (node)
                       (when (and (element-interactive-p node)
                                  (element-keyboard-focus-p node))
                         (push (element-id node) ids)))))
    (setf ids (if backward ids (nreverse ids))
          (context-focus context)
          (or (second (member (context-focus context) ids :test #'equal))
              (first ids)))))

(fn (pending-input-context context)
    ((context context) (events sequence)
     &optional ((width (or null real)) nil) ((height (or null real)) nil))
  "Predict focus after a newest-first pending EVENTS batch without mutating CONTEXT.
Return CONTEXT unchanged when no prediction is needed or dimensions changed.
Native key translators use this to interpret a key after a batched click or Tab."
  ;; Translate keys against earlier pointer/Tab events in the same input batch.
  ;; The completed frame remains untouched until BEGIN-FRAME consumes them.
  (if (and (or (null width) (= width (context-width context)))
           (or (null height) (= height (context-height context)))
           (some (lambda (event)
                   (member (event-kind event) '(:press :tab))) events))
      (let ((predicted (copy-context context)))
        (loop :for event-index :downfrom (1- (length events)) :to 0
              :for event := (elt events event-index) :do
              (case (event-kind event)
                (:tab (focus-next
                       predicted (eq (event-key event) :backward)))
                (:press
                 (let* ((id (hit predicted (event-x event) (event-y event)))
                        (node (gethash id (context-ids predicted))))
                   (when (and node (element-pointer-focus-p node))
                     (setf (context-focus predicted) id)))) (otherwise nil)))
        predicted)
      context))

(fn (scroll-path (vector object-id)) ((context context) (x real) (y real))
  "Collect scrollable ancestor IDs under X/Y for nested wheel propagation.
IDs may mix symbols, numbers, strings, and compound or application-defined keys."
  ;; Follow the painted hit path, deepest scroller first.
  (let ((scrollers nil))
    (labels ((visit (node parents)
               (when (contains-p (element-clip node) x y)
                 (let ((path (if (element-scroll-p node)
                                 (cons (element-id node) parents) parents)))
                   (setf scrollers path)
                   (do-children (child node)
                     (visit child path))))))
      (when (context-root context) (visit (context-root context) nil)))
    (make-array (length scrollers) :element-type 'object-id :initial-contents
                scrollers)))

(fn (scroll-along real)
    ((context context) (path (vector object-id)) (amount real))
  "Apply a scroll delta along the heterogeneous ID PATH; return the amount consumed."
  ;; Bubble the unused portion outward, including during the animated tail.
  (let ((requested amount))
    (loop :for id :across path :do
          (let ((node (gethash id (context-ids context))))
            (when (and node (element-scroll-p node))
              (let* ((old (element-scroll-y node))
                     (new (min (element-scroll-limit-y node)
                               (max 0 (+ old amount)))))
                (decf amount (- new old))
                (setf (element-scroll-y node) new
                      (gethash id (context-scroll context))
                      (cons (element-scroll-x node) new))))))
    (- requested amount)))

(fn (advance-scroll (values)) ((context context) (now real))
  "Advance CONTEXT's smooth scrolling to NOW and discard completed motion."
  (let ((motion (context-scroll-motion context)))
    (when motion
      (let* ((remaining (scroll-motion-remaining motion))
             (elapsed (max 0 (- now (scroll-motion-time motion))))
             ;; Exponential decay is independent of redraw frequency.
             (tail (* remaining (exp (/ (- elapsed) 0.07d0))))
             (step (if (< (abs tail) 0.05d0) remaining
                       (- remaining tail)))
             (used (scroll-along context (scroll-motion-path motion) step)))
        (decf (scroll-motion-remaining motion) used)
        (setf (scroll-motion-time motion) now)
        (when (or (< (abs (scroll-motion-remaining motion)) 1d-7)
                  (> (abs (- step used)) 1d-7))
          (setf (context-scroll-motion context) nil)))))
  (values))

(fn (wheel-scroll (or null real scroll-motion)) ((context context) (event
                                                                    event))
  "Route wheel input to immediate scrolling or accumulate smooth scroll motion."
  (let ((path (scroll-path context (event-x event) (event-y event)))
        (amount (event-value event))
        (now (context-time context))
        (mode (event-scroll-mode event)))
    (cond
      ((or (eq mode :immediate)
           (and (eq mode :auto) (context-text-mode-p context)))
       (setf (context-scroll-motion context) nil)
       (scroll-along context path amount))
      ((and (plusp (length path)) (not (zerop amount)))
       (let* ((old (context-scroll-motion context))
              (continuing
               (and old (= (length path) (length (scroll-motion-path old)))
                    (every #'equal path (scroll-motion-path old))
                    (plusp (* amount (scroll-motion-remaining old)))
                    (<= (- now (scroll-motion-last-input old)) 0.15d0)))
              (level (if continuing
                         (min 4 (1+ (scroll-motion-level old))) 1))
              ;; Repeated wheel notches travel faster, with a bounded gain.
              ;; OS-provided inertia bypasses this path via :IMMEDIATE.
              (delta (* amount (+ 1 (* 0.35d0 (1- level))))))
         (if continuing
             (setf (scroll-motion-remaining old)
                   (+ (scroll-motion-remaining old) delta)
                   (scroll-motion-last-input old) now
                   (scroll-motion-level old) level)
             (setf (context-scroll-motion context)
                   (make-scroll-motion :path path :remaining delta
                                       :time (- now (/ 1d0 60))
                                       :last-input now :level level)))))
      (t (setf (context-scroll-motion context) nil)))))

(fn (record-activation (eql t)) ((context context) (id object-id))
  "Record an activated ID so the next frame can consume its action."
  (push id (context-activation-order context))
  (setf (gethash id (context-activated context)) t))

(fn (activated-ids (vector object-id))
    (&optional ((context context) *context*))
  "Return active widget IDs in input order, including repeated activations.
ID types are unrestricted and may differ between vector elements."
  (let ((ids (remove-if-not (lambda (id) (gethash id (context-activated
                                                      context)))
                            (context-activation-order context))))
    (make-array (length ids) :element-type 'object-id :initial-contents
                (nreverse ids))))

(fn (pointer-cancel-p boolean) ((event event))
  "Recognize input that cancels an active pointer gesture or capture."
  (or (eq (event-kind event) :cancel)
      (and (eq (event-kind event) :move) (event-buttons event)
           (not (logbitp 0 (event-buttons event))))))

(fn (route-pointer-press (values))
    ((context context) (event event) (target object-id))
  "Record pointer presses, detect double clicks, and update capture and focus."
  (setf (context-pointer-press context) event)
  (let ((previous (context-last-click context)))
    (when (and previous (equal target (second previous))
               (eq (event-button event) (third previous))
               (<= (- (context-time context) (first previous)) 0.4f0)
               (< (abs (- (event-x event) (fourth previous))) 4)
               (< (abs (- (event-y event) (fifth previous))) 4))
      (setf (event-clicks event) 2))
    (setf (context-last-click context)
          (unless (= (event-clicks event) 2)
            (list (context-time context) target (event-button event)
                  (event-x event) (event-y event)))))
  (when (eq (event-button event) :primary)
    (setf (context-active context) target
          (context-focus-visible-p context) nil))
  (let ((node (gethash target (context-ids context))))
    (when (and node (element-pointer-focus-p node))
      (setf (context-focus context) target)))
  (values))

(fn (update-pointer-capture object-id)
    ((context context) (event event) (captured object-id))
  "Cancel stale capture and mark whether EVENT belongs to an active drag."
  (when (and captured
             (or (and (eq (event-kind event) :press)
                      (eq (event-button event) :primary))
                 (and (eq (event-kind event) :move)
                      (pointer-cancel-p event))))
    ;; A replacement press or a known unpressed motion ends the old drag.
    (push (make-event :kind :cancel :id captured :buttons 0)
          (gethash captured (context-events context)))
    (setf (context-active context) nil
          (context-last-click context) nil
          (context-scroll-motion context) nil
          captured nil))
  (when (eq (event-kind event) :cancel)
    (setf (context-active context) nil (context-hover context) nil
          (context-last-click context) nil
          (context-scroll-motion context) nil))
  (setf (event-dragging-p event)
        (and (not (null captured))
             (not (eq (event-kind event) :cancel))
             (or (null (event-buttons event))
                 (logbitp 0 (event-buttons event)))))
  captured)

(fn (dispatch-frame-event (values))
    ((context context) (event event) (target object-id) (resized boolean))
  "Apply one event to scrolling, activation, focus, and pointer state."
  (case (event-kind event)
    (:scroll
     (unless resized
       (wheel-scroll context event)))
    (:press
     (route-pointer-press context event target))
    (:release
     (when (and (eq (event-button event) :primary)
                target (equal target (context-active context)))
       (record-activation context target))
     (when (eq (event-button event) :primary)
       (setf (context-active context) nil)))
    (:tab
     (setf (context-focus-visible-p context) t)
     (focus-next context (eq (event-key event) :backward)))
    (:key (setf (context-focus-visible-p context) t))
    (:activate
     (let ((id (or (event-id event) (context-focus context))))
       (when id
         (record-activation context id))))
    (otherwise nil))  (values))

(fn (route-frame-event (values)) ((context context) (event event) (resized
                                                                   boolean))
  "Route EVENT against completed geometry and enqueue it for its owning widget."
  (when (event-id event)
    (setf event (copy-event event)
      (event-id event) (widget-id (event-id event) context)))
  (let ((target (or (and (member (event-kind event) '(:press :release))
                         (event-id event))
                    (unless resized
                      (hit context (event-x event) (event-y event)))))
        (captured (context-active context)))
    (when (member (event-kind event)
                  '(:press :release :tab :key :text :activate :change))
      (setf (context-scroll-motion context) nil))
    (setf captured (update-pointer-capture context event captured))
    (when (member (event-kind event) '(:move :press :release))
      (setf (context-hover context) target))
    (dispatch-frame-event context event target resized)
    (let ((id (or (event-id event)
                  (case (event-kind event)
                    ((:press :move :release)
                     (or (context-active context) captured target))
                    (:cancel captured)
                    (otherwise (context-focus context))))))
      (when id (push event (gethash id (context-events context))))))
  (values))

(fn (reset-frame-declarations (eql t)) ((context context) (width real)
                                        (height real))
  "Preserve completed hit regions and initialize declarations for the next frame."
  (clrhash (context-regions context))
  (when (context-root context)
    (walk-elements
     (context-root context)
     (lambda (node)
       (when (element-id node)
         (setf (gethash (element-id node) (context-regions context))
               (element-box node))))))
  (clrhash (context-ids context))
  (setf (context-after-layout context) nil
        (context-pending-memo context)
        (make-array 0 :element-type 'memo-entry :adjustable t :fill-pointer 0)
        (context-tabs-handled-p context) nil
        (context-previous-root context) (context-root context)
        (context-width context) width
        (context-height context) (if (and (context-page-height-p context)
                                          (context-root context))
                                     (max height (context-height context))
                                     height)
        (context-viewport-height context) height
        (context-root context) (make-element :width (grow) :height (grow))
        (context-building-p context) t))

(fn (begin-frame (eql t)) ((context context) (width real) (height real)
                           (events sequence))
  "Begin rebuilding CONTEXT at WIDTH and HEIGHT after routing EVENTS.
Input is resolved against the previous completed tree; this resets the frame
clock, redraw deadline, declarations, and per-frame activation state."
  (assert (not (context-building-p context)))
  (resolve-frame-identities context)
  (assert (and (>= width 0) (>= height 0)))
  (setf (context-time context)
        (/ (get-internal-real-time) internal-time-units-per-second)
        (context-next-frame context) nil)
  (when (context-input-handler context)
    (if (and (= width (context-width context))
             (= height (context-viewport-height context)))
        (funcall (context-input-handler context) context events)
        (setf (context-selection context) nil)))
  (setf (context-activation-order context) nil)
  (setf (context-pointer-press context) nil (context-popups context) nil)
  (clrhash (context-activated context))
  (clrhash (context-events context))
  ;; Old hit regions are invalid after resizing. Establish new geometry first.
  (let ((resized (or (/= width (context-width context))
                     (/= height (context-viewport-height context)))))
    (when resized
      (setf (context-active context) nil (context-hover context) nil))
    (when (or resized
              (some (lambda (event)
                      (member (event-kind event)
                              '(:press :release :tab :key :text
                                :activate :change :cancel))) events))
      (setf (context-scroll-motion context) nil))
    (unless resized (advance-scroll context (context-time context)))
    (loop :for event-index :below (length events)
          :for event := (elt events event-index) :do
          (route-frame-event context event resized))
    (unless resized (advance-scroll context (context-time context))))
  ;; Native selection still needs the focused input after a composite editor
  ;; consumes its events. Share the immutable event list with the observer.
  (setf (context-focus-input context)
        (when (context-selection context)
          (let* ((id (context-focus context))
                 (input (gethash id (context-events context))))
            (when input (cons id input)))))
  (reset-frame-declarations context width height))

(fn (emit element) ((node element))
  "Append NODE to the current parent, registering its ID and saved scroll state.
Return NODE. Interactive and scrolling nodes require unique, non-NIL IDs."
  (assert (context-building-p *context*))
  (when (element-interactive-p node) (assert (element-id node)))
  (when (element-id node)
    (assert (not (gethash (element-id node) (context-ids *context*))) ()
            "Duplicate UI ID: ~S" (element-id node))
    (setf (gethash (element-id node) (context-ids *context*)) node))
  (when (element-scroll-p node)
    (assert (element-id node))
    (let ((offset (gethash (element-id node) (context-scroll *context*))))
      (when offset
        (setf (element-scroll-x node) (car offset)
              (element-scroll-y node) (cdr offset)))))
  (append-child *parent* node))

(fn (parent-scroll-position (values real real)) ()
  "Return the current layout parent's retained horizontal and vertical scroll.
Subtract these from an absolute POSITION to opt into parent scrolling."
  (values (element-scroll-x *parent*) (element-scroll-y *parent*)))

(fn (scroll-position (values real real)) ((id object-id))
  "Return the retained horizontal and vertical scroll offsets."
  (let ((offset (gethash id (context-scroll *context*))))
    (values (or (car offset) 0) (or (cdr offset) 0))))

(fn (scroll-to (or null real)) ((id object-id) (x real) (y real))
  "Set scroll offsets; layout clamps them to the content extent."
  (setf (context-scroll-motion *context*) nil)
  (let ((offset (cons (max 0 x) (max 0 y))))
    (setf (gethash id (context-scroll *context*)) offset)
    (let ((node (gethash id (context-ids *context*))))
      (when node
        (setf (element-scroll-x node) (car offset)
              (element-scroll-y node) (cdr offset))))))

(fn (previous-box (values (or null box) boolean)) ((id object-id))
  "Return ID's solved box from the previous completed frame, or NIL."
  (gethash (widget-id id) (context-regions *context*)))

(fn (events-for (vector event)) ((id object-id))
  "Return a vector of ID's input events in chronological order for this frame."
  (let ((events (gethash (widget-id id) (context-events *context*))))
    (make-array (length events) :element-type 'event :initial-contents
                (reverse events))))

(fn (hovered-p boolean) ((id object-id))
  "Whether the pointer currently hovers over the non-NIL control ID."
  (and id (equal (widget-id id) (context-hover *context*))))

(fn (activated-p boolean) ((id object-id))
  "Whether ID was activated by this frame's pointer or keyboard input."
  (not (null (gethash (widget-id id) (context-activated *context*)))))

(fn (end-frame element) ((context context))
  "Complete CONTEXT: draw its overlay, solve layout, and retain input regions.
Clear focus/hover for removed controls and return the completed root element."
  (assert (context-building-p context))
  (resolve-frame-identities context)
  (dolist (popup (nreverse (context-popups context)))
    (append-child (context-root context) popup))
  (when (context-overlay context)
    (let ((*context* context) (*parent* (context-root context)))
      (funcall (context-overlay context) (context-previous-root context))))
  (let ((page-top (when (context-page-height-p context)
                    (context-page-top context)))
        (started (layout-clock)))
    (solve (context-root context) (context-width context)
           (context-viewport-height context) page-top)
    (record-frame-statistics (context-statistics context)
                             (- (layout-clock) started)
                             (context-time context))
    (setf (context-height context)
          (box-height (element-box (context-root context)))))
  (dolist (decorate (nreverse (context-after-layout context)))
    (funcall decorate))
  (flet ((interactive-p (id)
           (let ((node (gethash id (context-ids context))))
             (and node (element-interactive-p node)))))
    (unless (interactive-p (context-focus context))
      (setf (context-focus context) nil
            (context-focus-visible-p context) nil))
    (unless (interactive-p (context-hover context))
      (setf (context-hover context) nil))
    (unless (interactive-p (context-active context))
      (setf (context-active context) nil)))
  (prune-widget-values context)
  (clrhash (context-scroll context))
  (walk-elements
   (context-root context)
   (lambda (node)
     (when (and (element-id node) (element-scroll-p node))
       (setf (gethash (element-id node) (context-scroll context))
             (cons (element-scroll-x node) (element-scroll-y node))))))
  (let ((motion (context-scroll-motion context)))
    (when motion
      (if (gethash (aref (scroll-motion-path motion) 0) (context-ids context))
          (let ((*context* context)) (request-frame (/ 1 60)))
          (setf (context-scroll-motion context) nil))))
  (setf (context-building-p context) nil
        (context-memo context) (context-pending-memo context)
        (context-previous-root context) nil)
  (context-root context))

(fn (call-with-frame element)
    ((context context) (width real) (height real) (draw function)
     &key ((events sequence) nil))
  "Dispatch EVENTS, call DRAW once, solve CONTEXT, and return its root.
An aborted drawing or layout invalidates geometry and clears frame state."
  (let ((*context* context) (*key-scope* nil))
    (begin-frame context width height events)
    (let ((*parent* (context-root context)) (complete nil))
      (unwind-protect
           (progn
             (funcall draw)
             (end-frame context)
             (setf complete t)
             (context-root context))
        (unless complete
          (setf (context-root context) nil
                (context-memo context) #()
                (context-pending-memo context) #()
                (context-building-p context) nil
                (context-previous-root context) nil
                (context-hover context) nil
                (context-focus-visible-p context) nil
                (context-active context) nil
                (context-focus context) nil))))))

(defmacro with-frame ((context width height &key events) &body body)
  "Dispatch input, build and solve one frame, and return its root element."
  `(call-with-frame ,context ,width ,height (lambda () ,@body)
                    :events ,events))

(defmacro row (options &body body)
  "Lay out BODY horizontally using an OPTIONS expression, such as OPT.
OPTIONS evaluates once to a list of element options."
  `(let ((*parent* (emit
                   (apply #'make-element :direction :row ,options))))
     ,@body))

(defmacro column (options &body body)
  "Lay out BODY vertically using an OPTIONS expression, such as OPT.
OPTIONS evaluates once to a list of element options."
  `(let ((*parent* (emit
                   (apply #'make-element :direction :column ,options))))
     ,@body))
