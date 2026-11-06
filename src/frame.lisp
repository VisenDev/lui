(defpackage #:lui.frame
  (:use #:cl #:lui.fn #:lui.layout)
  (:export #:context #:make-context #:context-root #:context-focus
           #:context-focus-input #:context-active #:context-measure
           #:*context* #:*parent*
           #:with-frame
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
           #:context-next-frame #:scroll-position #:scroll-to
           #:pending-input-context #:context-overlay #:context-overlay-state
           #:context-tabs-handled-p #:context-text-mode-p
           #:context-copy #:context-input-handler #:context-selection))

(in-package #:lui.frame)

(defstruct* event
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
  id
  value
  key
  (x 0 :type real)
  (y 0 :type real))

(defstruct* scroll-motion
  (path nil :type list)
  (remaining 0 :type real)
  (time 0 :type real)
  (last-input 0 :type real)
  (level 1 :type integer))

(defvar *min-fps* 1)
(defvar *max-fps* 240)

(defstruct* context
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
  (time 0 :type real)
  (next-frame nil :type (or null real))
  focus
  (focus-visible-p nil :type boolean)
  hover
  active
  (state (make-hash-table :test 'equal) :type hash-table)
  (regions (make-hash-table :test 'equal) :type hash-table)
  (events (make-hash-table :test 'equal) :type hash-table)
  (scroll (make-hash-table :test 'equal) :type hash-table)
  (scroll-motion nil :type (or null scroll-motion))
  (activation-order nil :type list)
  (activated (make-hash-table :test 'equal) :type hash-table)
  (ids (make-hash-table :test 'equal) :type hash-table)
  (building-p nil :type boolean)
  ;; Supplied by the output backend: (widget available-width) -> width, height.
  (measure nil :type (or null function)))

(defvar *context*)
(setf (documentation '*context* 'variable)
      "Dynamically bound context for the drawing function currently building a frame.")

(defvar *parent*)
(setf (documentation '*parent* 'variable)
      "Dynamically bound layout parent receiving declarations in the current scope.")

(fn (frame-time real) ()
  "Monotonic seconds sampled once for the current frame."
  (context-time *context*))

(defstruct* frame-rate
  (fps 0.0 :type real)
  (count 0 :type integer)
  (start nil :type (or null real)))

(fn (frame-rate-label string) ((rate frame-rate))
  "Sample frame cadence without scheduling additional redraws."
  (when (context-text-mode-p *context*)
    (return-from frame-rate-label "Terminal: event-driven rendering"))
  (let ((now (frame-time)))
    (if (null (frame-rate-start rate))
        (setf (frame-rate-start rate) now)
        (let ((elapsed (- now (frame-rate-start rate))))
          (incf (frame-rate-count rate))
          (when (>= elapsed 0.5)
            (setf (frame-rate-fps rate) (/ (frame-rate-count rate) elapsed)
                  (frame-rate-count rate) 0
                  (frame-rate-start rate) now)))))
  (let ((fps (frame-rate-fps rate)))
    (format nil "~,1F FPS · ~,2F ms/frame" fps
            (if (plusp fps) (/ 1000 fps) 0.0))))

(fn frame-wait ((context context) &optional urgent
                (now (/ (get-internal-real-time)
                        internal-time-units-per-second)))
  (let* ((start (context-time context))
         (first (+ start (/ 1 (context-max-fps context))))
         (idle (+ start (/ 1 (context-min-fps context))))
         (due (min idle (or (context-next-frame context) idle))))
    (max 0 (- (if urgent first (max first due)) now))))

#-jscl
(fn limit-frame-rate ((context context))
  (let ((remaining (frame-wait context t)))
    (when (plusp remaining) (sleep remaining))))

(fn request-frame (&optional ((delay real) 0))
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
  (and (<= (box-x bounds) x) (< x (+ (box-x bounds) (box-width bounds)))
       (<= (box-y bounds) y) (< y (+ (box-y bounds) (box-height bounds)))))

(fn hit ((context context) (x real) (y real))
  (let ((found nil))
    (when (and (context-root context) (<= 0 x) (< x (context-width context))
               (<= 0 y) (< y (context-height context)))
      (walk-elements (context-root context)
                     (lambda (node)
                       (when (and (element-interactive-p node)
                                  (contains-p (element-clip node) x y))
                         (setf found (element-id node))))))
    found))

(fn focus-next ((context context) &optional backward)
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
    ((context context) (events list)
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
        (dolist (event (reverse events))
          (case (event-kind event)
            (:tab (focus-next
                   predicted (eq (event-key event) :backward)))
            (:press
             (let* ((id (hit predicted (event-x event) (event-y event)))
                    (node (gethash id (context-ids predicted))))
               (when (and node (element-pointer-focus-p node))
                 (setf (context-focus predicted) id))))))
        predicted)
      context))

(fn scroll-path ((context context) (x real) (y real))
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
    scrollers))

(fn scroll-along ((context context) (path list) (amount real))
  ;; Bubble the unused portion outward, including during the animated tail.
  (let ((requested amount))
    (dolist (id path)
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

(fn advance-scroll ((context context) (now real))
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
          (setf (context-scroll-motion context) nil))))))

(fn wheel-scroll ((context context) (event event))
  (let* ((path (scroll-path context (event-x event) (event-y event)))
         (amount (event-value event))
         (now (context-time context))
         (mode (event-scroll-mode event)))
    (cond
      ((or (eq mode :immediate)
           (and (eq mode :auto) (context-text-mode-p context)))
       (setf (context-scroll-motion context) nil)
       (scroll-along context path amount))
      ((and path (not (zerop amount)))
       (let* ((old (context-scroll-motion context))
              (continuing
                (and old (equal path (scroll-motion-path old))
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

(fn record-activation ((context context) id)
  (push id (context-activation-order context))
  (setf (gethash id (context-activated context)) t))

(fn (activated-ids list) (&optional ((context context) *context*))
  "Return active widget IDs in input order, including repeated activations."
  (reverse (remove-if-not
            (lambda (id) (gethash id (context-activated context)))
            (context-activation-order context))))

(fn (pointer-cancel-p boolean) ((event event))
  (or (eq (event-kind event) :cancel)
      (and (eq (event-kind event) :move) (event-buttons event)
           (not (logbitp 0 (event-buttons event))))))

(fn begin-frame ((context context) (width real) (height real) (events list))
  "Begin rebuilding CONTEXT at WIDTH and HEIGHT after routing EVENTS.
Input is resolved against the previous completed tree; this resets the frame
clock, redraw deadline, declarations, and per-frame activation state."
  (assert (not (context-building-p context)))
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
    (dolist (event events)
      (let ((target (or (and (member (event-kind event) '(:press :release))
                             (event-id event))
                        (unless resized
                          (hit context (event-x event) (event-y event)))))
            (captured (context-active context)))
        (when (member (event-kind event)
                      '(:press :release :tab :key :text :activate :change))
          (setf (context-scroll-motion context) nil))
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
        (when (member (event-kind event) '(:move :press :release))
          (setf (context-hover context) target))
        (case (event-kind event)
          (:scroll
           (unless resized
             (wheel-scroll context event)))
          (:press
           (setf (context-pointer-press context) event)
           (let ((previous (context-last-click context)))
             (when (and previous (equal target (second previous))
                        (eq (event-button event) (third previous))
                        (<= (- (context-time context) (first previous)) 0.4)
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
               (setf (context-focus context) target))))
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
          (otherwise nil))
        (let ((id (or (event-id event)
                      (case (event-kind event)
                        ((:press :move :release)
                         (or (context-active context) captured target))
                        (:cancel captured)
                        (otherwise (context-focus context))))))
          (when id (push event (gethash id (context-events context)))))))
    (unless resized (advance-scroll context (context-time context))))
  ;; Native selection still needs the focused input after a composite editor
  ;; consumes its events. Share the immutable event list with the observer.
  (setf (context-focus-input context)
        (when (context-selection context)
          (let* ((id (context-focus context))
                 (input (gethash id (context-events context))))
            (when input (cons id input)))))
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
        (context-tabs-handled-p context) nil
        (context-previous-root context) (context-root context)
        (context-width context) width
        (context-height context) (if (and (context-page-height-p context) (context-root context))
                                     (max height (context-height context)) height)
        (context-viewport-height context) height
        (context-root context) (make-element :width (grow) :height (grow))
        (context-building-p context) t))

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

(fn scroll-position (id)
  "Return the retained horizontal and vertical scroll offsets."
  (let ((offset (gethash id (context-scroll *context*))))
    (values (or (car offset) 0) (or (cdr offset) 0))))

(fn scroll-to (id (x real) (y real))
  "Set scroll offsets; layout clamps them to the content extent."
  (setf (context-scroll-motion *context*) nil)
  (let ((offset (cons (max 0 x) (max 0 y))))
    (setf (gethash id (context-scroll *context*)) offset)
    (let ((node (gethash id (context-ids *context*))))
      (when node
        (setf (element-scroll-x node) (car offset)
              (element-scroll-y node) (cdr offset))))))

(fn previous-box (id)
  "Return ID's solved box from the previous completed frame, or NIL."
  (gethash id (context-regions *context*)))

(fn (events-for list) (id)
  "Return ID's input events in chronological order for the current frame."
  (reverse (gethash id (context-events *context*))))

(fn (hovered-p boolean) (id)
  "Whether the pointer currently hovers over the non-NIL control ID."
  (and id (equal id (context-hover *context*))))

(fn (activated-p boolean) (id)
  "Whether ID was activated by this frame's pointer or keyboard input."
  (not (null (gethash id (context-activated *context*)))))

(fn (end-frame element) ((context context))
  "Complete CONTEXT: draw its overlay, solve layout, and retain input regions.
Clear focus/hover for removed controls and return the completed root element."
  (assert (context-building-p context))
  (dolist (popup (nreverse (context-popups context)))
    (append-child (context-root context) popup))
  (when (context-overlay context)
    (let ((*context* context) (*parent* (context-root context)))
      (funcall (context-overlay context) (context-previous-root context))))
  (let ((page-top (when (context-page-height-p context) (context-page-top context))))
    (solve (context-root context) (context-width context) (context-viewport-height context) page-top)
    (setf (context-height context) (box-height (element-box (context-root context)))))
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
  (let ((removed nil))
    (maphash
     (lambda (id value)
       (declare (ignore value))
       (unless (gethash id (context-ids context)) (push id removed)))
     (context-state context))
    (dolist (id removed) (remhash id (context-state context))))
  (clrhash (context-scroll context))
  (walk-elements
   (context-root context)
   (lambda (node)
     (when (and (element-id node) (element-scroll-p node))
       (setf (gethash (element-id node) (context-scroll context))
             (cons (element-scroll-x node) (element-scroll-y node))))))
  (let ((motion (context-scroll-motion context)))
    (when motion
      (if (gethash (first (scroll-motion-path motion)) (context-ids context))
          (let ((*context* context)) (request-frame (/ 1 60)))
          (setf (context-scroll-motion context) nil))))
  (setf (context-building-p context) nil
        (context-previous-root context) nil)
  (context-root context))

(defmacro with-frame ((context width height &key events) &body body)
  "Dispatch input, build and solve one frame, and return its root element."
  `(let ((*context* ,context))
     (begin-frame *context* ,width ,height ,events)
     (let ((*parent* (context-root *context*))
           (complete nil))
       (unwind-protect
            (progn
              ,@body
              (end-frame *context*)
              (setf complete t)
              (context-root *context*))
         (unless complete
           (setf (context-root *context*) nil
                 (context-building-p *context*) nil
                 (context-previous-root *context*) nil
                 (context-hover *context*) nil
                 (context-focus-visible-p *context*) nil
                 (context-active *context*) nil
                 (context-focus *context*) nil))))))

(defmacro row ((&rest options) &body body)
  "Lay out children declared by BODY horizontally, using element options."
  `(let ((*parent* (emit (make-element :direction :row ,@options))))
     ,@body))

(defmacro column ((&rest options) &body body)
  "Lay out children declared by BODY vertically, using element options."
  `(let ((*parent* (emit (make-element :direction :column ,@options))))
     ,@body))
